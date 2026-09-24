import Foundation
import Testing

@testable import virt

@Suite
struct ISOCheckTests {
  private func writeTempISO(contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("iso")
    try Data(contents.utf8).write(to: url)
    return url
  }

  @Test func detectsARM64() throws {
    let url = try writeTempISO(contents: "padding… /EFI/BOOT/BOOTAA64.EFI;1 …more")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url) == .arm64)
  }

  @Test func detectsARM64GrubTree() throws {
    let url = try writeTempISO(contents: "EFI/BOOT/GRUBAA64.EFI;1")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url) == .arm64)
  }

  /// GRUB ships `file`-command help text for every architecture on all
  /// builds ("is-arm64-efi — Check if FILE is ARM64 EFI file"). Filename
  /// markers must not be fooled by it.
  @Test func helpTextDoesNotFoolDetector() throws {
    let url = try writeTempISO(
      contents: "is-arm64-efi.Check if FILE is ARM64 EFI file. … /EFI/BOOT/BOOTX64.EFI;1")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url) == .x8664)
  }

  @Test func detectsX86() throws {
    let url = try writeTempISO(contents: "padding… boot/grub/x86_64-efi/acpi.mod … BOOTX64.EFI;1")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url) == .x8664)
  }

  @Test func unknownWhenNoMarkers() throws {
    let url = try writeTempISO(contents: "nothing recognizable here")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url) == .unknown)
  }

  /// Regression: a Rocky x86_64 DVD contains the stray string "aa64.efi"
  /// ~10 GB deep (grub2-efi-aa64 RPM payload text). The detector must
  /// not let package text flip an x86 image to arm64.
  @Test func strayPackageTextDoesNotFlipVerdict() throws {
    let padding = String(repeating: "x", count: 1 << 20)
    let url = try writeTempISO(
      contents: "BOOTX64.EFI;1 \(padding) grub2-efi-aa64 provides aa64.efi")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url) == .x8664)
  }

  /// Markers past the scan cap must be ignored — that is what keeps
  /// detection of a 10 GB DVD fast.
  @Test func markerBeyondScanLimitIsIgnored() throws {
    let url = try writeTempISO(contents: "\(String(repeating: "x", count: 64)) BOOTX64.EFI;1")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url, scanLimit: 16) == .unknown)
  }

  /// Multi-arch media carries both loaders; VZ's EFI picks BOOTAA64.EFI,
  /// so it counts as arm64.
  @Test func multiArchImageCountsAsARM64() throws {
    let url = try writeTempISO(contents: "BOOTX64.EFI;1 and BOOTAA64.EFI;1")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ISOCheck.detect(url: url) == .arm64)
  }

  @Test func missingFileIsUnknown() {
    let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).iso")
    #expect(ISOCheck.detect(url: url) == .unknown)
  }
}
