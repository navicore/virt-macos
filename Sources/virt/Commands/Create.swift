import ArgumentParser
import Foundation
import Virtualization

struct Create: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Create a new VM"
  )

  @Argument(help: "Name of the VM")
  var name: String

  @Option(help: "Short description of the VM's purpose")
  var description: String

  @Option(help: "Disk size in GB", completion: .custom { Create.diskSizes($0) })
  var disk: Int

  @Option(help: "Number of CPU cores")
  var cpus: Int = 2

  @Option(help: "Memory in MB", completion: .custom { Create.memorySizes($0) })
  var memory: Int

  @Option(help: "Network mode: nat (default) or bridge (VM sits directly on the LAN)")
  var network: String = "nat"

  @Option(help: "Host interface for bridge mode (default: primary interface)")
  var bridgeInterface: String?

  /// Tab-completion candidates — suggestions only; any value at or above
  /// the validate() floors is accepted, exactly like today. The closure
  /// receives the words typed so far; the last is the word in progress.
  static func memorySizes(_ arguments: [String]) -> [String] {
    let word = arguments.last ?? ""
    return [1024, 2048, 4096, 8192]
      .map(String.init)
      .filter { $0.hasPrefix(word) }
  }

  static func diskSizes(_ arguments: [String]) -> [String] {
    let word = arguments.last ?? ""
    return [10, 20, 50]
      .map(String.init)
      .filter { $0.hasPrefix(word) }
  }

  func validate() throws {
    guard cpus >= 1 else {
      throw ValidationError("--cpus must be at least 1")
    }
    guard memory >= 512 else {
      throw ValidationError("--memory must be at least 512 MB")
    }
    guard disk >= 1 else {
      throw ValidationError("--disk must be at least 1 GB")
    }
    guard network == "nat" || network == "bridge" else {
      throw ValidationError("--network must be 'nat' or 'bridge'")
    }
    if bridgeInterface != nil && network != "bridge" {
      throw ValidationError("--bridge-interface requires --network bridge")
    }
  }

  func run() throws {
    let dir = VMDirectory(name: name)

    guard !dir.exists else {
      throw ValidationError("VM '\(name)' already exists.")
    }

    try checkFreeDiskSpace()

    // Stable MAC so the guest keeps its network identity
    // (and DHCP lease) across reboots
    let mac = VZMACAddress.randomLocallyAdministered().string

    do {
      try dir.create()

      let config = VMConfig(
        name: name,
        cpus: cpus,
        memoryMB: memory,
        diskSizeGB: disk,
        description: description,
        macAddress: mac,
        networkMode: network,
        bridgeInterface: bridgeInterface
      )
      try config.write(to: dir.configURL)

      // Allocate raw disk image (sparse — actual disk usage is near zero until written)
      let diskSizeBytes = UInt64(disk) * 1024 * 1024 * 1024
      try Data().write(to: dir.diskURL)
      let handle = try FileHandle(forWritingTo: dir.diskURL)
      try handle.truncate(atOffset: diskSizeBytes)
      try handle.close()

      // Initialize EFI variable store
      _ = try VZEFIVariableStore(creatingVariableStoreAt: dir.nvramURL)
    } catch {
      try? dir.remove()
      throw error
    }

    print("Created VM '\(name)'")
    print("  Desc:   \(description)")
    print("  CPUs:   \(cpus)")
    print("  Memory: \(memory) MB")
    print("  Disk:   \(disk) GB")
    print("  MAC:    \(mac)")
    print(
      "  Net:    \(network == "bridge" ? "bridge\(bridgeInterface.map { " (\($0))" } ?? "")" : "nat")"
    )
    print("  Path:   \(dir.rootURL.path)")
  }

  private func checkFreeDiskSpace() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    guard
      let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]
      ),
      let available = values.volumeAvailableCapacityForImportantUsage
    else { return }
    let requested = Int64(disk) * 1_073_741_824
    guard available >= 1_073_741_824 else {
      throw ValidationError("Less than 1 GB of free disk space.")
    }
    if available < requested {
      let freeGB = Double(available) / 1_073_741_824
      let message =
        "warning: %.1f GB free — less than the %d GB disk "
        + "(sparse image, but guest writes will fail when the host fills up).\n"
      fputs(
        String(
          format: message,
          freeGB, disk), stderr)
    }
  }
}
