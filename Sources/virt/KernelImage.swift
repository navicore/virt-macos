import Foundation

enum KernelFormat {
    /// arm64 magic at offset 56 — bootable by VZLinuxBootLoader as-is.
    case arm64Raw
    /// PE/COFF EFI stub (arm64) without the raw magic — compressed payload
    /// (zboot). VZ cannot boot it; must be decompressed first.
    case arm64Compressed
    /// PE/COFF with x86_64 machine type.
    case x86_64
    case unknown
}

enum KernelImage {
    /// Classify a kernel image.
    ///
    /// VZLinuxBootLoader needs the uncompressed arm64 Image header, which
    /// carries the magic "ARM\x64" at offset 56
    /// (Documentation/arm64/booting.rst) — this survives even when an EFI
    /// stub prefixes the file with "MZ". Distro kernels are usually
    /// gzip-compressed zboot images: PE/COFF (machine 0xAA64) whose payload
    /// — including the magic — is inside the gzip stream.
    static func classify(url: URL) -> KernelFormat {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4096), header.count >= 64 else { return .unknown }

        if header[56..<60] == Data([0x41, 0x52, 0x4D, 0x64]) { // "ARMd"
            return .arm64Raw
        }

        if header[0...1] == Data([0x4D, 0x5A]) { // "MZ" — PE/COFF
            let peOffset = Int(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0x3C, as: UInt32.self) })
            guard peOffset + 6 <= header.count,
                  header[peOffset...(peOffset + 3)] == Data([0x50, 0x45, 0, 0]) // "PE\0\0"
            else { return .unknown }
            let machine = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: peOffset + 4, as: UInt16.self) }
            switch machine {
            case 0xAA64: return .arm64Compressed
            case 0x8664: return .x86_64
            default: return .unknown
            }
        }

        return .unknown
    }
}
