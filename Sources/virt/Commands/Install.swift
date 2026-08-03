import ArgumentParser
import Foundation

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Boot a VM with a GUI window (for install or configuration)"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Path to ISO image to attach")
    var iso: String? = nil

    @Option(help: "Host directory to share with the VM")
    var share: String? = nil

    func run() throws {
        let dir = VMDirectory(name: name)

        guard dir.exists else {
            throw ValidationError("VM '\(name)' does not exist. Run 'virt create' first.")
        }

        if let iso = iso {
            try checkISOArchitecture(iso)
        }

        // Held for the life of the process; released by the kernel on death.
        let lock = try VMLock.acquire(dir: dir)
        defer { lock.release() }

        let config = try VMConfig.load(from: dir.configURL)

        fputs("Booting VM '\(name)' with GUI...\n", stderr)
        if let iso = iso {
            fputs("  ISO: \(iso)\n", stderr)
        }
        fputs("  CPUs: \(config.cpus), Memory: \(config.memoryMB) MB\n", stderr)

        let instance = VMInstance(config: config, dir: dir, isoPath: iso, sharePath: share)
        let app = InstallerApp(vmInstance: instance)
        try app.run()
    }

    /// Virtualization.framework cannot run x86 guests — fail fast with a
    /// clear error instead of a black window.
    private func checkISOArchitecture(_ iso: String) throws {
        let url = URL(fileURLWithPath: iso)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("ISO file not found: \(iso)")
        }
        switch ISOCheck.detect(url: url) {
        case .arm64:
            break
        case .x86_64:
            throw ValidationError("""
                ISO is x86_64 — only ARM64 (aarch64) ISOs can run on Apple Silicon.
                Download the arm64/aarch64 build of your distro instead.
                """)
        case .unknown:
            fputs("warning: could not determine ISO architecture; proceeding anyway.\n", stderr)
        }
    }
}
