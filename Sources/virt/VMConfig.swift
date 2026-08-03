import Foundation

struct VMConfig: Codable {
    let name: String
    let cpus: Int
    let memoryMB: Int
    let diskSizeGB: Int
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

    init(name: String, cpus: Int, memoryMB: Int, diskSizeGB: Int, macAddress: String? = nil,
         rootDevice: String? = nil, extraKernelArgs: String? = nil,
         networkMode: String? = nil, bridgeInterface: String? = nil) {
        self.name = name
        self.cpus = cpus
        self.memoryMB = memoryMB
        self.diskSizeGB = diskSizeGB
        self.macAddress = macAddress
        self.rootDevice = rootDevice
        self.extraKernelArgs = extraKernelArgs
        self.networkMode = networkMode
        self.bridgeInterface = bridgeInterface
    }

    func withMAC(_ mac: String) -> VMConfig {
        VMConfig(name: name, cpus: cpus, memoryMB: memoryMB, diskSizeGB: diskSizeGB,
                 macAddress: mac, rootDevice: rootDevice, extraKernelArgs: extraKernelArgs,
                 networkMode: networkMode, bridgeInterface: bridgeInterface)
    }

    func withKernelBoot(rootDevice: String, extraArgs: String?) -> VMConfig {
        VMConfig(name: name, cpus: cpus, memoryMB: memoryMB, diskSizeGB: diskSizeGB,
                 macAddress: macAddress, rootDevice: rootDevice, extraKernelArgs: extraArgs,
                 networkMode: networkMode, bridgeInterface: bridgeInterface)
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
