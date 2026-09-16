import XCTest

@testable import virt

final class KernelImageTests: XCTestCase {
  private func writeTempFile(bytes: [UInt8]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try Data(bytes).write(to: url)
    return url
  }

  /// Bare arm64 Image: magic "ARM\x64" at offset 56.
  private func makeRawARM64() -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 1024)
    bytes[56] = 0x41
    bytes[57] = 0x52
    bytes[58] = 0x4D
    bytes[59] = 0x64
    return bytes
  }

  /// PE/COFF (EFI stub) kernel: MZ header, PE signature at 0x40, machine type.
  private func makePE(machine: UInt16) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 1024)
    bytes[0] = 0x4D
    bytes[1] = 0x5A  // "MZ"
    bytes[0x3C] = 0x40  // PE header at offset 0x40
    bytes[0x40] = 0x50
    bytes[0x41] = 0x45  // "PE"
    bytes[0x44] = UInt8(machine & 0xFF)
    bytes[0x45] = UInt8(machine >> 8)
    return bytes
  }

  func testRawARM64Image() throws {
    let url = try writeTempFile(bytes: makeRawARM64())
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(KernelImage.classify(url: url), .arm64Raw)
  }

  /// Uncompressed kernels with an EFI stub have both "MZ" and the raw magic.
  func testPEWithRawMagicIsBootable() throws {
    var bytes = makeRawARM64()
    bytes[0] = 0x4D
    bytes[1] = 0x5A
    let url = try writeTempFile(bytes: bytes)
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(KernelImage.classify(url: url), .arm64Raw)
  }

  /// PE arm64 without the raw magic — a compressed (zboot) kernel.
  func testPEARM64Compressed() throws {
    let url = try writeTempFile(bytes: makePE(machine: 0xAA64))
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(KernelImage.classify(url: url), .arm64Compressed)
  }

  func testPEX86() throws {
    let url = try writeTempFile(bytes: makePE(machine: 0x8664))
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(KernelImage.classify(url: url), .x8664)
  }

  func testGarbageIsUnknown() throws {
    let url = try writeTempFile(bytes: [UInt8](repeating: 0xFF, count: 1024))
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(KernelImage.classify(url: url), .unknown)
  }

  func testShortFileIsUnknown() throws {
    let url = try writeTempFile(bytes: [0x4D, 0x5A])
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(KernelImage.classify(url: url), .unknown)
  }

  func testMissingFileIsUnknown() {
    let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
    XCTAssertEqual(KernelImage.classify(url: url), .unknown)
  }
}
