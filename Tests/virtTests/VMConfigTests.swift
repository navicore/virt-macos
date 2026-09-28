import Foundation
import Testing

@testable import virt

@Suite
struct VMConfigTests {
  private func makeTempConfigURL() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir.appendingPathComponent("config.json")
  }

  @Test func roundTrip() throws {
    let config = VMConfig(name: "test", cpus: 4, memoryMB: 2048, diskSizeGB: 20)
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try config.write(to: url)
    let loaded = try VMConfig.load(from: url)

    #expect(loaded.name == "test")
    #expect(loaded.cpus == 4)
    #expect(loaded.memoryMB == 2048)
    #expect(loaded.diskSizeGB == 20)
  }

  @Test func jsonIsPrettyPrinted() throws {
    let config = VMConfig(name: "vm1", cpus: 1, memoryMB: 512, diskSizeGB: 5)
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try config.write(to: url)
    let json = try String(contentsOf: url, encoding: .utf8)

    // Pretty printed JSON contains newlines
    #expect(json.contains("\n"))
    // Sorted keys means cpus comes before name
    let cpusRange = json.range(of: "cpus")!
    let nameRange = json.range(of: "name")!
    #expect(cpusRange.lowerBound < nameRange.lowerBound)
  }

  @Test func macRoundTrip() throws {
    let config = VMConfig(
      name: "test", cpus: 4, memoryMB: 2048, diskSizeGB: 20,
      macAddress: "02:11:22:33:44:55")
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try config.write(to: url)
    let loaded = try VMConfig.load(from: url)

    #expect(loaded.macAddress == "02:11:22:33:44:55")
  }

  @Test func legacyConfigWithoutMACDecodes() throws {
    // Configs written before MACs were persisted must still load
    let legacy = """
      {"cpus":2,"diskSizeGB":10,"memoryMB":2048,"name":"old"}
      """
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try legacy.write(to: url, atomically: true, encoding: .utf8)
    let loaded = try VMConfig.load(from: url)

    #expect(loaded.name == "old")
    #expect(loaded.macAddress == nil)
  }

  @Test func networkModeRoundTrip() throws {
    let config = VMConfig(
      name: "test", cpus: 2, memoryMB: 2048, diskSizeGB: 20,
      macAddress: "02:11:22:33:44:55", networkMode: "bridge", bridgeInterface: "en0")
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try config.write(to: url)
    let loaded = try VMConfig.load(from: url)

    #expect(loaded.networkMode == "bridge")
    #expect(loaded.bridgeInterface == "en0")
  }

  @Test func withMACPreservesOtherFields() {
    let config = VMConfig(name: "vm", cpus: 2, memoryMB: 1024, diskSizeGB: 8)
    let updated = config.withMAC("02:aa:bb:cc:dd:ee")
    #expect(updated.macAddress == "02:aa:bb:cc:dd:ee")
    #expect(updated.name == "vm")
    #expect(updated.cpus == 2)
    #expect(updated.memoryMB == 1024)
    #expect(updated.diskSizeGB == 8)
  }

  @Test func descriptionRoundTrip() throws {
    let config = VMConfig(
      name: "milford", cpus: 4, memoryMB: 8192, diskSizeGB: 100,
      description: "medium size vm with rocky 10 os")
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try config.write(to: url)
    let loaded = try VMConfig.load(from: url)

    #expect(loaded.description == "medium size vm with rocky 10 os")
  }

  @Test func legacyConfigWithoutDescriptionDecodes() throws {
    // Configs written before descriptions existed must still load
    let legacy = """
      {"cpus":2,"diskSizeGB":10,"memoryMB":2048,"name":"old"}
      """
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try legacy.write(to: url, atomically: true, encoding: .utf8)
    let loaded = try VMConfig.load(from: url)

    #expect(loaded.description == nil)
  }

  @Test func withDescriptionPreservesOtherFields() {
    let config = VMConfig(
      name: "milford", cpus: 4, memoryMB: 8192, diskSizeGB: 100,
      description: "before", macAddress: "02:11:22:33:44:55",
      networkMode: "bridge", bridgeInterface: "en0")
    let updated = config.withDescription("after")
    #expect(updated.description == "after")
    #expect(updated.name == "milford")
    #expect(updated.cpus == 4)
    #expect(updated.memoryMB == 8192)
    #expect(updated.diskSizeGB == 100)
    #expect(updated.macAddress == "02:11:22:33:44:55")
    #expect(updated.networkMode == "bridge")
    #expect(updated.bridgeInterface == "en0")
  }

  @Test func withCloneIdentityPreservesHardwareAndNetwork() {
    let config = VMConfig(
      name: "template", cpus: 4, memoryMB: 8192, diskSizeGB: 100,
      description: "gold image", macAddress: "02:aa:bb:cc:dd:ee",
      rootDevice: "/dev/vda2", extraKernelArgs: "console=hvc0",
      networkMode: "bridge", bridgeInterface: "en0")
    let cloned = config.withCloneIdentity(
      name: "node1", description: "clone of template", macAddress: "02:11:22:33:44:55")

    #expect(cloned.name == "node1")
    #expect(cloned.description == "clone of template")
    #expect(cloned.macAddress == "02:11:22:33:44:55")
    #expect(cloned.cpus == 4)
    #expect(cloned.memoryMB == 8192)
    #expect(cloned.diskSizeGB == 100)
    #expect(cloned.rootDevice == "/dev/vda2")
    #expect(cloned.extraKernelArgs == "console=hvc0")
    #expect(cloned.networkMode == "bridge")
    #expect(cloned.bridgeInterface == "en0")
  }

  @Test func networkDisplayModes() {
    #expect(VMConfig(name: "n", cpus: 1, memoryMB: 512, diskSizeGB: 1).networkDisplay == "nat")
    #expect(
      VMConfig(name: "n", cpus: 1, memoryMB: 512, diskSizeGB: 1, networkMode: "nat")
        .networkDisplay == "nat")
    #expect(
      VMConfig(name: "n", cpus: 1, memoryMB: 512, diskSizeGB: 1, networkMode: "bridge")
        .networkDisplay == "bridge (primary)")
    #expect(
      VMConfig(
        name: "n", cpus: 1, memoryMB: 512, diskSizeGB: 1, networkMode: "bridge",
        bridgeInterface: "en0"
      )
      .networkDisplay == "bridge (en0)")
  }

  @Test func loadCorruptFileThrows() throws {
    let url = try makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try "not json".write(to: url, atomically: true, encoding: .utf8)

    #expect(throws: (any Error).self) { try VMConfig.load(from: url) }
  }
}
