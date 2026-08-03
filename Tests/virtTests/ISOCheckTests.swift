import XCTest
@testable import virt

final class ISOCheckTests: XCTestCase {
    private func writeTempISO(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("iso")
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testDetectsARM64() throws {
        let url = try writeTempISO(contents: "padding… /EFI/BOOT/BOOTAA64.EFI;1 …more")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ISOCheck.detect(url: url), .arm64)
    }

    func testDetectsARM64GrubTree() throws {
        let url = try writeTempISO(contents: "EFI/BOOT/GRUBAA64.EFI;1")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ISOCheck.detect(url: url), .arm64)
    }

    /// GRUB ships `file`-command help text for every architecture on all
    /// builds ("is-arm64-efi — Check if FILE is ARM64 EFI file"). Filename
    /// markers must not be fooled by it.
    func testHelpTextDoesNotFoolDetector() throws {
        let url = try writeTempISO(contents: "is-arm64-efi.Check if FILE is ARM64 EFI file. … /EFI/BOOT/BOOTX64.EFI;1")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ISOCheck.detect(url: url), .x86_64)
    }

    func testDetectsX86() throws {
        let url = try writeTempISO(contents: "padding… boot/grub/x86_64-efi/acpi.mod … BOOTX64.EFI;1")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ISOCheck.detect(url: url), .x86_64)
    }

    func testUnknownWhenNoMarkers() throws {
        let url = try writeTempISO(contents: "nothing recognizable here")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ISOCheck.detect(url: url), .unknown)
    }

    func testMissingFileIsUnknown() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).iso")
        XCTAssertEqual(ISOCheck.detect(url: url), .unknown)
    }
}
