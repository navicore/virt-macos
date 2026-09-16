import Foundation

enum ISOArchitecture {
  case arm64
  case x8664
  case unknown
}

/// Best-effort architecture detection for ISO images.
///
/// Scans the raw image for EFI boot-loader filenames in the ISO9660
/// directory records. Bootable arm64 media must carry /EFI/BOOT/BOOTAA64.EFI;
/// x86 media carries BOOTX64.EFI.
///
/// Only full loader filenames are trusted. Loose substrings ("aa64.efi")
/// false-positive on package text buried deep in DVD images: a Rocky
/// x86_64 DVD contains the string at offset ~10.16 GB (grub2-efi-aa64
/// RPM payload), which flipped the verdict to arm64 and booted a black
/// window. (Substring markers like "arm64-efi" are equally unreliable —
/// GRUB's `file` command embeds them as help text on every arch.)
///
/// Markers are matched as raw bytes: decoding image chunks to String is
/// orders of magnitude slower on binary data.
enum ISOCheck {
  private static let arm64Markers = [
    "BOOTAA64.EFI", "bootaa64.efi", "GRUBAA64.EFI", "grubaa64.efi",
  ].map { Data($0.utf8) }
  private static let x86Markers = [
    "BOOTX64.EFI", "bootx64.efi", "GRUBX64.EFI", "grubx64.efi",
  ].map { Data($0.utf8) }

  /// EFI/BOOT directory records and the El Torito catalog sit within the
  /// first few MB of an ISO (observed: ~1.3 MB on distro DVDs). Scanning
  /// a full 10 GB DVD takes minutes; the cap bounds detection to ~1s.
  private static let defaultScanLimit = 64 << 20

  static func detect(url: URL) -> ISOArchitecture {
    detect(url: url, scanLimit: defaultScanLimit)
  }

  static func detect(url: URL, scanLimit: Int) -> ISOArchitecture {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
    defer { try? handle.close() }

    var foundArm64 = false
    var foundX86 = false
    var carry = Data()
    var scanned = 0
    while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
      let budget = scanLimit - scanned
      if budget <= 0 { break }
      var window = carry
      window.append(chunk.prefix(budget))
      scanned += chunk.count
      if !foundArm64 {
        foundArm64 = arm64Markers.contains { window.range(of: $0) != nil }
      }
      if !foundX86 {
        foundX86 = x86Markers.contains { window.range(of: $0) != nil }
      }
      carry = window.suffix(64)  // keep a tail so split markers still match
    }
    // Multi-arch media (both loaders present) boots BOOTAA64.EFI on VZ,
    // so arm64 evidence wins; x86 evidence alone is fatal on Apple Silicon.
    if foundArm64 { return .arm64 }
    if foundX86 { return .x8664 }
    return .unknown
  }
}
