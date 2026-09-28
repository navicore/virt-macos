import Foundation

struct VMConfig: Codable {
  let name: String
  let cpus: Int
  let memoryMB: Int
  let diskSizeGB: Int
  /// Human description of the VM's purpose (required at `virt create`,
  /// editable with `virt set`). Optional in storage for backward
  /// compatibility with configs written before descriptions existed.
  let description: String?
  /// Stable MAC address assigned at create time. Optional for backward
  /// compatibility with configs written before MACs were persisted;
  /// one is assigned and saved on first boot.
  let macAddress: String?
  /// Root device for direct kernel boot (e.g. /dev/vda2). Set by
  /// `virt kernel-import`.
  let rootDevice: String?
  /// Extra kernel command-line arguments for direct kernel boot.
  let extraKernelArgs: String?
  /// "nat" (default when absent) or "bridge" (VM sits directly on the LAN).
  let networkMode: String?
  /// Host interface to bridge onto (e.g. "en0"). Nil = primary interface.
  let bridgeInterface: String?

  init(
    name: String, cpus: Int, memoryMB: Int, diskSizeGB: Int, description: String? = nil,
    macAddress: String? = nil,
    rootDevice: String? = nil, extraKernelArgs: String? = nil,
    networkMode: String? = nil, bridgeInterface: String? = nil
  ) {
    self.name = name
    self.cpus = cpus
    self.memoryMB = memoryMB
    self.diskSizeGB = diskSizeGB
    self.description = description
    self.macAddress = macAddress
    self.rootDevice = rootDevice
    self.extraKernelArgs = extraKernelArgs
    self.networkMode = networkMode
    self.bridgeInterface = bridgeInterface
  }

  func withMAC(_ mac: String) -> VMConfig {
    VMConfig(
      name: name, cpus: cpus, memoryMB: memoryMB, diskSizeGB: diskSizeGB,
      description: description, macAddress: mac, rootDevice: rootDevice,
      extraKernelArgs: extraKernelArgs, networkMode: networkMode,
      bridgeInterface: bridgeInterface)
  }

  func withKernelBoot(rootDevice: String, extraArgs: String?) -> VMConfig {
    VMConfig(
      name: name, cpus: cpus, memoryMB: memoryMB, diskSizeGB: diskSizeGB,
      description: description, macAddress: macAddress, rootDevice: rootDevice,
      extraKernelArgs: extraArgs, networkMode: networkMode,
      bridgeInterface: bridgeInterface)
  }

  func withDescription(_ newDescription: String) -> VMConfig {
    VMConfig(
      name: name, cpus: cpus, memoryMB: memoryMB, diskSizeGB: diskSizeGB,
      description: newDescription, macAddress: macAddress, rootDevice: rootDevice,
      extraKernelArgs: extraKernelArgs, networkMode: networkMode,
      bridgeInterface: bridgeInterface)
  }

  /// `virt clone`: same hardware, boot setup, and network mode — new
  /// name, description, and MAC.
  func withCloneIdentity(name: String, description: String, macAddress: String) -> VMConfig {
    VMConfig(
      name: name, cpus: cpus, memoryMB: memoryMB, diskSizeGB: diskSizeGB,
      description: description, macAddress: macAddress, rootDevice: rootDevice,
      extraKernelArgs: extraKernelArgs, networkMode: networkMode,
      bridgeInterface: bridgeInterface)
  }

  /// Short network descriptor for `virt list`: nat | bridge (en0).
  var networkDisplay: String {
    switch networkMode {
    case "bridge":
      return "bridge (\(bridgeInterface ?? "primary"))"
    default:
      return "nat"
    }
  }

  func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(self)
    try data.write(to: url)
  }

  static func load(from url: URL) throws -> VMConfig {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(VMConfig.self, from: data)
  }
}
