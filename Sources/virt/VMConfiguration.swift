import ArgumentParser
import Foundation
import SystemConfiguration
import Virtualization

/// Builds the VZVirtualMachineConfiguration for headless and GUI modes.
extension VMInstance {

  func buildConfiguration(gui: Bool) throws -> VZVirtualMachineConfiguration {
    let vzConfig = VZVirtualMachineConfiguration()
    vzConfig.cpuCount = config.cpus
    vzConfig.memorySize = UInt64(config.memoryMB) * 1024 * 1024
    vzConfig.bootLoader = try makeBootLoader(gui: gui)
    vzConfig.storageDevices = try makeStorageDevices()
    vzConfig.networkDevices = [try makeNetworkDevice()]
    vzConfig.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    vzConfig.graphicsDevices = [makeGraphicsDevice()]
    if let shareDevice = try makeShareDevice() {
      vzConfig.directorySharingDevices = [shareDevice]
    }
    if gui {
      configureGUIDevices(vzConfig)
    } else {
      configureHeadlessConsole(vzConfig)
    }
    return vzConfig
  }

  func buildGUIConfiguration() throws -> VZVirtualMachineConfiguration {
    let vzConfig = try buildConfiguration(gui: true)
    try vzConfig.validate()
    return vzConfig
  }

  private func makeBootLoader(gui: Bool) throws -> VZBootLoader {
    // Direct kernel boot — headless only. GUI/install boots real EFI.
    if !gui, dir.hasKernelBoot {
      let loader = VZLinuxBootLoader(kernelURL: dir.kernelURL)
      loader.initialRamdiskURL = dir.initrdURL
      let root = config.rootDevice ?? "/dev/vda2"
      var commandLine = "console=hvc0 root=\(root) ro"
      if let extra = config.extraKernelArgs, !extra.isEmpty {
        commandLine += " \(extra)"
      }
      loader.commandLine = commandLine
      return loader
    }

    let bootLoader = VZEFIBootLoader()
    if FileManager.default.fileExists(atPath: dir.nvramURL.path) {
      bootLoader.variableStore = VZEFIVariableStore(url: dir.nvramURL)
    } else {
      bootLoader.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: dir.nvramURL)
    }
    return bootLoader
  }

  private func makeStorageDevices() throws -> [VZStorageDeviceConfiguration] {
    var devices: [VZStorageDeviceConfiguration] = []

    // ISO first for boot priority
    if let isoPath = isoPath {
      let isoURL = URL(fileURLWithPath: isoPath)
      guard FileManager.default.fileExists(atPath: isoURL.path) else {
        throw ValidationError("ISO file not found: \(isoPath)")
      }
      let isoAttachment = try VZDiskImageStorageDeviceAttachment(url: isoURL, readOnly: true)
      devices.append(VZUSBMassStorageDeviceConfiguration(attachment: isoAttachment))
    }

    let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: dir.diskURL, readOnly: false)
    devices.append(VZVirtioBlockDeviceConfiguration(attachment: diskAttachment))
    return devices
  }

  private func makeNetworkDevice() throws -> VZVirtioNetworkDeviceConfiguration {
    let device = VZVirtioNetworkDeviceConfiguration()
    device.attachment = try makeNetworkAttachment()

    if let mac = config.macAddress {
      guard let address = VZMACAddress(string: mac) else {
        throw ValidationError("Invalid MAC address in config.json: \(mac)")
      }
      device.macAddress = address
    } else {
      // Legacy config from before MACs were persisted — assign and save
      let address = VZMACAddress.randomLocallyAdministered()
      device.macAddress = address
      try? config.withMAC(address.string).write(to: dir.configURL)
      VMLogger.log(dir, "assigned persistent MAC \(address.string)")
      fputs("Assigned persistent MAC \(address.string) (saved to config.json)\n", stderr)
    }
    return device
  }

  /// Bridged mode puts the VM directly on the LAN: the guest keeps DF on
  /// its packets and receives PMTUD ICMPs unmodified, so path MTU
  /// discovery self-heals exactly like a physical machine. Apple's NAT
  /// strips DF, turning recoverable MTU events into unrecoverable
  /// fragment loss (see docs/design/006).
  private func makeNetworkAttachment() throws -> VZNetworkDeviceAttachment {
    guard config.networkMode == "bridge" else {
      return VZNATNetworkDeviceAttachment()
    }
    // com.apple.vm.networking is a restricted entitlement: ad-hoc signed
    // binaries carrying it are SIGKILLed at launch by amfid, and it
    // effectively requires a paid Developer account. Fail clearly.
    guard Entitlements.has("com.apple.vm.networking") else {
      throw ValidationError(
        """
        Bridge mode requires the restricted com.apple.vm.networking entitlement \
        (paid Developer ID signing). This build is ad-hoc signed; use NAT mode \
        (see README for the guest MTU workaround).
        """)
    }
    let interfaces = VZBridgedNetworkInterface.networkInterfaces
    let chosen: VZBridgedNetworkInterface?
    if let name = config.bridgeInterface {
      chosen = interfaces.first { $0.identifier == name }
      guard chosen != nil else {
        let available = interfaces.map(\.identifier).joined(separator: ", ")
        throw ValidationError("No bridge interface '\(name)'. Available: \(available)")
      }
    } else {
      chosen = interfaces.first { $0.identifier == Self.primaryInterfaceName() } ?? interfaces.first
      guard chosen != nil else {
        throw ValidationError("No network interface available for bridging.")
      }
    }
    return VZBridgedNetworkDeviceAttachment(interface: chosen!)
  }

  private static func primaryInterfaceName() -> String? {
    let store = SCDynamicStoreCreate(nil, "virt" as CFString, nil, nil)
    let key = "State:/Network/Global/IPv4" as CFString
    let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any]
    return dict?["PrimaryInterface"] as? String
  }

  private func makeGraphicsDevice() -> VZVirtioGraphicsDeviceConfiguration {
    // Always present — EFI and GRUB need a framebuffer to function.
    // In GUI mode it's displayed in a window; headless it renders nowhere.
    let graphics = VZVirtioGraphicsDeviceConfiguration()
    let scanout = VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 800)
    graphics.scanouts = [scanout]
    return graphics
  }

  private func makeShareDevice() throws -> VZVirtioFileSystemDeviceConfiguration? {
    guard let sharePath = sharePath else { return nil }
    let shareURL = URL(fileURLWithPath: sharePath)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: shareURL.path, isDirectory: &isDir),
      isDir.boolValue
    else {
      throw ValidationError("Shared path is not a directory: \(sharePath)")
    }
    let sharedDir = VZSharedDirectory(url: shareURL, readOnly: false)
    let device = VZVirtioFileSystemDeviceConfiguration(tag: "share")
    device.share = VZSingleDirectoryShare(directory: sharedDir)
    return device
  }

  private func configureGUIDevices(_ vzConfig: VZVirtualMachineConfiguration) {
    vzConfig.keyboards = [VZUSBKeyboardConfiguration()]
    vzConfig.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

    // Clipboard sharing via SPICE agent (macOS 14+)
    if #available(macOS 14.0, *) {
      let clipboardDevice = VZVirtioConsoleDeviceConfiguration()
      let spicePort = VZVirtioConsolePortConfiguration()
      spicePort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
      spicePort.attachment = VZSpiceAgentPortAttachment()
      spicePort.isConsole = false
      clipboardDevice.ports[0] = spicePort
      vzConfig.consoleDevices = [clipboardDevice]
    }
  }

  private func configureHeadlessConsole(_ vzConfig: VZVirtualMachineConfiguration) {
    // Wire the serial console to stdin/stdout. Must be direct FileHandles —
    // pipes do not carry data with this API.
    let attachment = VZFileHandleSerialPortAttachment(
      fileHandleForReading: FileHandle.standardInput,
      fileHandleForWriting: FileHandle.standardOutput
    )
    let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
    serialPort.attachment = attachment
    vzConfig.serialPorts = [serialPort]

    if isatty(STDIN_FILENO) != 0 {
      enableRawMode()
    }
  }
}
