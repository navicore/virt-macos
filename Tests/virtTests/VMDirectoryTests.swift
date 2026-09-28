import Foundation
import Testing

@testable import virt

@Suite
struct VMDirectoryTests {
  @Test func pathConstruction() {
    let dir = VMDirectory(name: "myvm")
    #expect(dir.rootURL.path.hasSuffix(".virt/vms/myvm"))
    #expect(dir.configURL.path.hasSuffix("myvm/config.json"))
    #expect(dir.diskURL.path.hasSuffix("myvm/disk.raw"))
    #expect(dir.nvramURL.path.hasSuffix("myvm/nvram.bin"))
    #expect(dir.pidURL.path.hasSuffix("myvm/vm.pid"))
  }

  @Test func existsReturnsFalseForMissing() {
    let dir = VMDirectory(name: "nonexistent-\(UUID().uuidString)")
    #expect(!dir.exists)
  }

  @Test func createAndRemove() throws {
    let name = "test-\(UUID().uuidString)"
    let dir = VMDirectory(name: name)
    defer { try? dir.remove() }

    #expect(!dir.exists)
    try dir.create()
    #expect(dir.exists)
    try dir.remove()
    #expect(!dir.exists)
  }

  /// Same rules as virt-linux — names must stay safe as directory
  /// names and move between the two tools unchanged.
  @Test func nameValidation() {
    #expect(VMDirectory.nameValidationError("milford") == nil)
    #expect(VMDirectory.nameValidationError("k3s-node-1") == nil)
    #expect(VMDirectory.nameValidationError("a.b_c-d") == nil)

    #expect(VMDirectory.nameValidationError("") != nil)
    #expect(VMDirectory.nameValidationError(".hidden") != nil)
    #expect(VMDirectory.nameValidationError("..") != nil)
    #expect(VMDirectory.nameValidationError("a/b") != nil)
    #expect(VMDirectory.nameValidationError("a b") != nil)
    #expect(VMDirectory.nameValidationError("ño") != nil)
    #expect(VMDirectory.nameValidationError(String(repeating: "a", count: 65)) != nil)
  }
}
