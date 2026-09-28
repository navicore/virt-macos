import Foundation
import Testing

@testable import virt

@Suite
struct CloneTests {
  /// Test VMs live under the real base dir (~/.virt/vms) — the same
  /// pattern as VMLockTests — with unique names and cleanup.
  private func makeTempVMDir(_ label: String) throws -> VMDirectory {
    let dir = VMDirectory(name: "clonetest-\(label)-\(UUID().uuidString)")
    try dir.create()
    return dir
  }

  /// End-to-end clone of a synthetic VM: config restamped, disk/NVRAM/
  /// kernel copied, transient files excluded, hardware + network pass
  /// through unchanged.
  @Test func performCopiesDiskAndRestampsIdentity() throws {
    let src = try makeTempVMDir("src")
    let dst = try makeTempVMDir("dst")
    defer {
      try? src.remove()
      try? dst.remove()
    }

    let config = VMConfig(
      name: src.name, cpus: 4, memoryMB: 4096, diskSizeGB: 20,
      description: "gold image", macAddress: "02:aa:bb:cc:dd:ee",
      rootDevice: "/dev/vda2", extraKernelArgs: "console=hvc0",
      networkMode: "bridge", bridgeInterface: "en0")
    try config.write(to: src.configURL)

    try Data("disk-bytes".utf8).write(to: src.diskURL)
    try Data("nvram".utf8).write(to: src.nvramURL)
    try Data("kernel".utf8).write(to: src.kernelURL)
    try Data("initrd".utf8).write(to: src.initrdURL)
    try Data("999".utf8).write(to: src.pidURL)  // transient — must not travel

    try Clone.perform(
      source: src, destination: dst, config: config,
      identity: Clone.Identity(
        name: dst.name, description: "clone of \(src.name)",
        macAddress: "02:11:22:33:44:55"))

    let cloned = try VMConfig.load(from: dst.configURL)
    #expect(cloned.name == dst.name)
    #expect(cloned.description == "clone of \(src.name)")
    #expect(cloned.macAddress == "02:11:22:33:44:55")
    // Hardware, boot setup, and network mode pass through unchanged.
    #expect(cloned.cpus == 4)
    #expect(cloned.memoryMB == 4096)
    #expect(cloned.diskSizeGB == 20)
    #expect(cloned.rootDevice == "/dev/vda2")
    #expect(cloned.extraKernelArgs == "console=hvc0")
    #expect(cloned.networkMode == "bridge")
    #expect(cloned.bridgeInterface == "en0")

    #expect(try String(contentsOf: dst.diskURL, encoding: .utf8) == "disk-bytes")
    #expect(FileManager.default.fileExists(atPath: dst.nvramURL.path))
    #expect(FileManager.default.fileExists(atPath: dst.kernelURL.path))
    #expect(FileManager.default.fileExists(atPath: dst.initrdURL.path))
    #expect(!FileManager.default.fileExists(atPath: dst.pidURL.path))
    #expect(!FileManager.default.fileExists(atPath: dst.lockURL.path))
  }

  /// Whatever the copy path (clonefile or fallback), content survives.
  @Test func apfsClonePreservesContent() throws {
    let dir = try makeTempVMDir("clonefile")
    defer { try? dir.remove() }

    let src = dir.rootURL.appendingPathComponent("src.raw")
    let dst = dir.rootURL.appendingPathComponent("dst.raw")
    try Data("0123456789".utf8).write(to: src)

    #expect(clonefile(src.path, dst.path, 0) == 0)
    #expect(try String(contentsOf: dst, encoding: .utf8) == "0123456789")
  }

  @Test func humanBytesFormats() throws {
    let dir = try makeTempVMDir("human")
    defer { try? dir.remove() }

    let file = dir.rootURL.appendingPathComponent("disk.raw")
    try Data(repeating: 0, count: 5 * 1024 * 1024).write(to: file)
    #expect(Clone.humanBytes(at: file) == "5 MB")

    // 3 GB logical — truncate (sparse) instead of writing 3 GB.
    try? FileManager.default.removeItem(at: file)
    FileManager.default.createFile(atPath: file.path, contents: nil)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 3 * 1024 * 1024 * 1024)
    try handle.close()
    #expect(Clone.humanBytes(at: file) == "3.0 GB")
  }
}
