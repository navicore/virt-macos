import ArgumentParser
import Foundation
import Virtualization

/// `virt clone` — copy a VM (disk, NVRAM, kernel-boot files, config)
/// under a new name with a fresh MAC. Mirrors virt-linux's clone, with
/// an APFS twist: `clonefile(2)` copies even a 100 GB disk instantly,
/// blocks shared copy-on-write until either side writes.
///
/// The template workflow: keep a fully configured VM stopped (GUI
/// installed, kernel imported) and clone it for each new instance.
/// Clones inherit network mode — clone a bridge VM three times and
/// each gets its own LAN identity.
struct Clone: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Clone a stopped VM under a new name (fresh MAC)"
  )

  @Argument(help: "Name of the VM to clone (must be stopped)")
  var source: String

  @Argument(help: "Name for the new VM")
  var newName: String

  @Option(help: "Description for the clone (default: \"clone of <source>\")")
  var description: String?

  func run() throws {
    let src = VMDirectory(name: source)
    let dst = VMDirectory(name: newName)

    guard src.exists else {
      throw ValidationError("VM '\(source)' does not exist.")
    }
    if let error = VMDirectory.nameValidationError(newName) {
      throw ValidationError(error)
    }
    guard !dst.exists else {
      throw ValidationError("VM '\(newName)' already exists.")
    }
    if VMLock.isLocked(src) {
      var detail = ""
      let pid = try? String(contentsOf: src.pidURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let pid = pid, !pid.isEmpty {
        detail = " (PID \(pid))"
      }
      throw ValidationError(
        "VM '\(source)' is running\(detail) — stop it first; a clone needs a quiet disk.")
    }

    let config = try VMConfig.load(from: src.configURL)
    let mac = VZMACAddress.randomLocallyAdministered().string
    let description = self.description ?? "clone of \(source)"

    try dst.create()
    do {
      try Clone.perform(
        source: src, destination: dst, config: config,
        identity: Identity(name: newName, description: description, macAddress: mac))
    } catch {
      // Leave no half-cloned VM behind.
      try? dst.remove()
      throw error
    }
  }

  /// The clone's new identity; everything else passes through.
  struct Identity {
    let name: String
    let description: String
    let macAddress: String
  }

  /// Copy everything the VM owns except transient runtime files
  /// (pid, lock, log). Internal for tests.
  static func perform(
    source: VMDirectory,
    destination: VMDirectory,
    config: VMConfig,
    identity: Identity
  ) throws {
    // Same hardware and boot setup, new identity.
    try config
      .withCloneIdentity(
        name: identity.name, description: identity.description,
        macAddress: identity.macAddress
      )
      .write(to: destination.configURL)

    let started = Date()
    let mode = try Clone.copyDisk(from: source.diskURL, to: destination.diskURL)
    let elapsed = Date().timeIntervalSince(started)

    // EFI variable store and direct-kernel-boot files, when present.
    let fm = FileManager.default
    for (srcURL, dstURL) in [
      (source.nvramURL, destination.nvramURL),
      (source.kernelURL, destination.kernelURL),
      (source.initrdURL, destination.initrdURL),
    ] where fm.fileExists(atPath: srcURL.path) {
      try fm.copyItem(at: srcURL, to: dstURL)
    }

    VMLogger.log(source, "cloned to '\(identity.name)' (mac \(identity.macAddress))")
    VMLogger.log(
      destination, "cloned from '\(source.name)' (mac \(identity.macAddress))")

    let size = Clone.humanBytes(at: destination.diskURL)
    print("Cloned '\(source.name)' -> '\(identity.name)'")
    switch mode {
    case .apfsClone:
      print("  Disk:   \(size) (APFS clone — instant, space shared until written)")
    case .fullCopy:
      print("  Disk:   \(size) copied in \(String(format: "%.1f", elapsed))s")
    }
    print("  MAC:    \(identity.macAddress) (fresh — the template keeps its own)")
    print("  Path:   \(destination.rootURL.path)")
    print("  note: the guest's machine-id and SSH host keys are copied too;")
    print("        reset them inside the clone for clusters (see README).")
  }

  private enum DiskCopyMode {
    case apfsClone
    case fullCopy
  }

  /// clonefile(2) shares disk blocks CoW; on filesystems where it is
  /// unsupported (non-APFS volumes, some exotic setups) fall back to a
  /// plain byte copy.
  private static func copyDisk(from source: URL, to destination: URL) throws -> DiskCopyMode {
    if clonefile(source.path, destination.path, 0) == 0 {
      return .apfsClone
    }
    try FileManager.default.copyItem(at: source, to: destination)
    return .fullCopy
  }

  /// Logical disk size (sparse images report their declared size).
  /// Uses `attributesOfItem` — `URL.resourceValues` caches per URL
  /// object and can report a stale size.
  static func humanBytes(at url: URL) -> String {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    let gb = Double(bytes) / 1_073_741_824
    return gb >= 1.0
      ? String(format: "%.1f GB", gb)
      : String(format: "%.0f MB", Double(bytes) / 1_048_576)
  }
}
