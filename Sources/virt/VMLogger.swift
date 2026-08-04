import Foundation

/// Timestamped lifecycle log appended to `vm.log` in the VM's directory.
/// Written by both the running VM process and `virt stop`, so the log
/// shows the full story of a VM across processes.
enum VMLogger {
  static func log(_ dir: VMDirectory, _ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = Data("\(stamp) \(message)\n".utf8)
    if let handle = try? FileHandle(forWritingTo: dir.logURL) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
    } else {
      try? data.write(to: dir.logURL)
    }
  }
}
