import ArgumentParser
import Foundation

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a VM (headless, console in terminal)"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Host directory to share with the VM")
    var share: String? = nil

    func run() throws {
        let dir = VMDirectory(name: name)

        guard dir.exists else {
            throw ValidationError("VM '\(name)' does not exist.")
        }

        // Held for the life of the process; released by the kernel on death.
        let lock = try VMLock.acquire(dir: dir)
        defer { lock.release() }

        let config = try VMConfig.load(from: dir.configURL)

        fputs("Starting VM '\(name)'...\n", stderr)
        fputs("  CPUs: \(config.cpus), Memory: \(config.memoryMB) MB\n", stderr)
        if config.networkMode == "bridge" {
            fputs("  Network: bridge\(config.bridgeInterface.map { " (\($0))" } ?? "") — the VM is directly on your LAN\n", stderr)
        }
        if dir.hasKernelBoot {
            fputs("  Boot: direct kernel (console=hvc0)\n", stderr)
        } else {
            if dir.hasPartialKernelBoot {
                fputs("  warning: kernel and initrd must both be present; falling back to EFI.\n", stderr)
            }
            fputs("  Boot: EFI/GRUB (silent until the guest configures console=hvc0 —\n", stderr)
            fputs("        or run 'virt kernel-import \(name) --from <dir>' for direct boot)\n", stderr)
        }
        fputs("  Console attached. Use 'virt stop \(name)' to shut down.\n", stderr)

        if let share = share {
            fputs("  Shared folder: \(share) (mount with: mount -t virtiofs share /mnt)\n", stderr)
        }

        let instance = VMInstance(config: config, dir: dir, isoPath: nil, sharePath: share)
        try instance.runHeadless()
    }
}
