import ArgumentParser
import Foundation
import Virtualization

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new VM"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Disk size in GB")
    var disk: Int = 10

    @Option(help: "Number of CPU cores")
    var cpus: Int = 2

    @Option(help: "Memory in MB")
    var memory: Int = 2048

    @Option(help: "Network mode: nat (default) or bridge (VM sits directly on the LAN)")
    var network: String = "nat"

    @Option(help: "Host interface for bridge mode (default: primary interface)")
    var bridgeInterface: String? = nil

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
        print("  CPUs:   \(cpus)")
        print("  Memory: \(memory) MB")
        print("  Disk:   \(disk) GB")
        print("  MAC:    \(mac)")
        print("  Net:    \(network == "bridge" ? "bridge\(bridgeInterface.map { " (\($0))" } ?? "")" : "nat")")
        print("  Path:   \(dir.rootURL.path)")
    }

    private func checkFreeDiskSpace() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let requested = Int64(disk) * 1_073_741_824
        guard available >= 1_073_741_824 else {
            throw ValidationError("Less than 1 GB of free disk space.")
        }
        if available < requested {
            let freeGB = Double(available) / 1_073_741_824
            fputs(String(format: "warning: %.1f GB free — less than the %d GB disk (sparse image, but guest writes will fail when the host fills up).\n", freeGB, disk), stderr)
        }
    }
}
