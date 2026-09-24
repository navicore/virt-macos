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
}
