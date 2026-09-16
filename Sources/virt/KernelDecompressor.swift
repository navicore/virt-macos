import Foundation

/// Decompresses gzip-compressed (zboot) kernel images for VZLinuxBootLoader,
/// which only boots uncompressed arm64 Images.
///
/// The gzip stream is located by its magic bytes (the approach used by the
/// kernel's own scripts/extract-vmlinux) — it sits at an arbitrary offset
/// inside the PE/zboot wrapper, followed by trailing data.
enum KernelDecompressor {
  /// Returns a URL to the decompressed kernel (in a temp directory), or
  /// nil if no gzip stream was found or decompression failed.
  static func decompress(url: URL) -> URL? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
      let gzipOffset = data.range(of: Data([0x1F, 0x8B, 0x08]))?.lowerBound
    else {
      return nil
    }

    let payload = FileManager.default.temporaryDirectory
      .appendingPathComponent("virt-kernel-\(UUID().uuidString).gz")
    let output = payload.deletingPathExtension()
    defer { try? FileManager.default.removeItem(at: payload) }

    do {
      try data[gzipOffset...].write(to: payload)
    } catch {
      return nil
    }

    // gunzip exits 2 on the trailing garbage after the stream — expected.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
    process.arguments = ["-c", payload.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let decompressed = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard !decompressed.isEmpty, (try? decompressed.write(to: output)) != nil else { return nil }
    return output
  }
}
