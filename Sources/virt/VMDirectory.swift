import Foundation

struct VMDirectory {
  static let baseURL: URL = {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".virt")
      .appendingPathComponent("vms")
  }()

  let name: String

  var rootURL: URL {
    VMDirectory.baseURL.appendingPathComponent(name)
  }

  var configURL: URL {
    rootURL.appendingPathComponent("config.json")
  }

  var diskURL: URL {
    rootURL.appendingPathComponent("disk.raw")
  }

  var nvramURL: URL {
    rootURL.appendingPathComponent("nvram.bin")
  }

  var pidURL: URL {
    rootURL.appendingPathComponent("vm.pid")
  }

  var lockURL: URL {
    rootURL.appendingPathComponent("vm.lock")
  }

  var logURL: URL {
    rootURL.appendingPathComponent("vm.log")
  }

  var kernelURL: URL {
    rootURL.appendingPathComponent("kernel")
  }

  var initrdURL: URL {
    rootURL.appendingPathComponent("initrd")
  }

  /// Direct kernel boot requires both files; exactly one is a broken import.
  var hasKernelBoot: Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: kernelURL.path) && fm.fileExists(atPath: initrdURL.path)
  }

  var hasPartialKernelBoot: Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: kernelURL.path) != fm.fileExists(atPath: initrdURL.path)
  }

  var exists: Bool {
    FileManager.default.fileExists(atPath: rootURL.path)
  }

  func create() throws {
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
  }

  func remove() throws {
    try FileManager.default.removeItem(at: rootURL)
  }

  /// Returns all VM directories under ~/.virt/vms/
  static func allVMs() throws -> [VMDirectory] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: baseURL.path) else { return [] }
    let contents = try fm.contentsOfDirectory(
      at: baseURL,
      includingPropertiesForKeys: [.isDirectoryKey]
    )
    return contents.compactMap { url in
      let name = url.lastPathComponent
      guard !name.hasPrefix("."),
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
      else {
        return nil
      }
      return VMDirectory(name: name)
    }
  }

  /// A VM name becomes a directory name — keep it safe. Returns an
  /// error message, or nil when the name is acceptable (same rules as
  /// virt-linux, so names move between the two tools unchanged).
  static func nameValidationError(_ name: String) -> String? {
    if name.isEmpty { return "VM name must not be empty" }
    if name.count > 64 { return "VM name must be at most 64 characters" }
    if name.hasPrefix(".") {
      return "VM name must not start with '.' (hidden directory)"
    }
    let charactersAllowed = name.allSatisfy { character in
      (character.isASCII && character.isLetter)
        || (character.isASCII && character.isNumber)
        || character == "-" || character == "_" || character == "."
    }
    if !charactersAllowed {
      return "VM name may contain only letters, digits, '-', '_', '.'"
    }
    return nil
  }
}
