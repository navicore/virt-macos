import ArgumentParser
import Foundation

struct KernelImport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kernel-import",
        abstract: "Import a kernel and initrd for direct boot (no EFI/GRUB)"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Directory containing the guest's kernel/initrd (e.g. the virtiofs share)")
    var from: String

    @Option(help: "Root device for the kernel command line")
    var root: String = "/dev/vda2"

    @Option(help: "Extra kernel command-line arguments")
    var kernelArgs: String? = nil

    func run() throws {
        let dir = VMDirectory(name: name)
        guard dir.exists else {
            throw ValidationError("VM '\(name)' does not exist.")
        }

        let source = URL(fileURLWithPath: from)
        let kernel = try findFile(in: source, exact: "vmlinuz", prefix: "vmlinuz-", kind: "kernel")
        let initrd = try findFile(in: source, exact: "initrd.img", prefixes: ["initrd.img-", "initramfs-"], kind: "initrd")

        // VZLinuxBootLoader only boots uncompressed arm64 Images; distro
        // kernels are usually gzip-compressed zboot and need extraction.
        var kernelToImport = kernel
        var wasDecompressed = false
        switch KernelImage.classify(url: kernel) {
        case .arm64Raw:
            break
        case .x86_64:
            throw ValidationError("\(kernel.lastPathComponent) is an x86_64 kernel — virt requires arm64.")
        case .arm64Compressed, .unknown:
            guard let decompressed = KernelDecompressor.decompress(url: kernel),
                  KernelImage.classify(url: decompressed) == .arm64Raw else {
                throw ValidationError("\(kernel.lastPathComponent) is not a recognized arm64 kernel image (raw or gzip-compressed). Files swapped? Corrupt copy?")
            }
            kernelToImport = decompressed
            wasDecompressed = true
        }

        try FileManager.default.copyItem(at: kernelToImport, to: dir.kernelURL, replacing: true)
        try FileManager.default.copyItem(at: initrd, to: dir.initrdURL, replacing: true)
        if wasDecompressed {
            try? FileManager.default.removeItem(at: kernelToImport)
        }

        let config = try VMConfig.load(from: dir.configURL)
        try config.withKernelBoot(rootDevice: root, extraArgs: kernelArgs).write(to: dir.configURL)

        VMLogger.log(dir, "kernel imported (\(kernel.lastPathComponent), root=\(root))")
        print("Imported kernel for direct boot:")
        print("  Kernel: \(kernel.lastPathComponent)\(wasDecompressed ? " (decompressed)" : "")")
        print("  Initrd: \(initrd.lastPathComponent)")
        print("  Root:   \(root)")
        print("'virt start \(name)' now boots directly — console output in ~1s, no GRUB setup needed.")
    }

    /// Locate a kernel/initrd file: prefer the exact (symlink-dereferenced)
    /// name, else the newest versioned match.
    private func findFile(in dir: URL, exact: String, prefix: String? = nil,
                          prefixes: [String] = [], kind: String) throws -> URL {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let allPrefixes = ([prefix] + prefixes).compactMap { $0 }

        if entries.contains(exact) {
            return dir.appendingPathComponent(exact)
        }
        if let versioned = entries.filter({ name in allPrefixes.contains(where: name.hasPrefix) }).sorted().last {
            return dir.appendingPathComponent(versioned)
        }
        throw ValidationError("No \(kind) found in \(dir.path) — expected \(exact) or \(allPrefixes.first ?? "")*")
    }
}

private extension FileManager {
    func copyItem(at src: URL, to dst: URL, replacing: Bool) throws {
        if replacing, fileExists(atPath: dst.path) {
            try removeItem(at: dst)
        }
        try copyItem(at: src, to: dst)
    }
}
