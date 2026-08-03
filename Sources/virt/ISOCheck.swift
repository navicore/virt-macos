import Foundation

enum ISOArchitecture {
    case arm64
    case x86_64
    case unknown
}

/// Best-effort architecture detection for ISO images.
///
/// Scans the raw image for EFI boot-loader filenames in the ISO9660
/// directory records. Bootable arm64 media must carry /EFI/BOOT/BOOTAA64.EFI;
/// x86 media carries BOOTX64.EFI. (Substring markers like "arm64-efi" are
/// unreliable — GRUB's `file` command embeds them as help text on every arch.)
///
/// Markers are matched as raw bytes: decoding image chunks to String is
/// orders of magnitude slower on binary data.
enum ISOCheck {
    private static let arm64Markers = ["BOOTAA64", "bootaa64", "AA64.EFI", "aa64.efi"]
        .map { Data($0.utf8) }
    private static let x86Markers = ["BOOTX64", "bootx64", "X64.EFI", "x64.efi"]
        .map { Data($0.utf8) }

    static func detect(url: URL) -> ISOArchitecture {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }

        var foundX86 = false
        var carry = Data()
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            var window = carry
            window.append(chunk)
            for marker in arm64Markers where window.range(of: marker) != nil {
                return .arm64
            }
            if !foundX86 {
                foundX86 = x86Markers.contains { window.range(of: $0) != nil }
            }
            carry = window.suffix(64) // keep a tail so split markers still match
        }
        return foundX86 ? .x86_64 : .unknown
    }
}
