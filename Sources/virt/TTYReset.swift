import Foundation

/// Restores a terminal left in raw mode by a force-killed `virt start`.
///
/// The headless console puts its tty in raw mode and restores it via a
/// `defer` — which SIGKILL skips. `virt stop` captures the target's tty
/// before escalating and repairs it afterwards.
enum TTYReset {
  /// Path like `/dev/ttys003` for the process's controlling terminal, if any.
  static func controllingTTY(of pid: Int32) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "tty=", "-p", String(pid)]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let tty = (String(data: data, encoding: .utf8) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !tty.isEmpty, tty != "??" else { return nil }
    return "/dev/" + tty
  }

  /// Run `stty sane` on a tty, restoring echo and cooked mode.
  static func restoreSane(ttyPath: String) {
    guard let input = FileHandle(forReadingAtPath: ttyPath) else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/stty")
    process.arguments = ["sane"]
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    try? input.close()
  }
}
