import ArgumentParser
import Foundation

struct Stop: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Stop a running VM"
  )

  @Argument(help: "Name of the VM")
  var name: String

  func run() throws {
    let dir = VMDirectory(name: name)

    guard dir.exists else {
      throw ValidationError("VM '\(name)' does not exist.")
    }

    // The flock is authoritative: a held lock always means a live virt
    // process. The PID file only tells us *where* to send the signal,
    // and is only trusted once we know the lock is held.
    guard VMLock.isLocked(dir) else {
      if FileManager.default.fileExists(atPath: dir.pidURL.path) {
        try? FileManager.default.removeItem(at: dir.pidURL)
        throw ValidationError("VM '\(name)' is not running (stale PID file removed).")
      }
      throw ValidationError("VM '\(name)' is not running.")
    }

    let pid = try readPID(dir: dir)

    print("Sending shutdown signal to VM '\(name)' (PID \(pid))...")
    VMLogger.log(dir, "virt stop: SIGINT → pid \(pid)")
    if kill(pid, SIGINT) != 0 {
      let err = errno
      if err == ESRCH {
        print("VM '\(name)' stopped.")
        return
      }
      throw ValidationError("Failed to signal PID \(pid): \(String(cString: strerror(err)))")
    }

    if waitForExit(pid: pid, timeout: 15) {
      print("VM '\(name)' stopped.")
      VMLogger.log(dir, "stopped gracefully")
      return
    }

    try forceKill(dir: dir, pid: pid)
  }

  private func readPID(dir: VMDirectory) throws -> Int32 {
    let pidString = try? String(contentsOf: dir.pidURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let pidString = pidString, let pid = Int32(pidString) else {
      throw ValidationError(
        "VM '\(dir.name)' is running but its PID file is missing or corrupt. Find it with: ps aux | grep virt"
      )
    }
    return pid
  }

  private func waitForExit(pid: Int32, timeout: TimeInterval) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
      if kill(pid, 0) != 0 { return true }
      Thread.sleep(forTimeInterval: 0.5)
    }
    return false
  }

  /// Escalate to SIGKILL. The killed process can't restore its terminal
  /// from raw mode, so capture its tty first and repair it after.
  private func forceKill(dir: VMDirectory, pid: Int32) throws {
    print("VM did not stop gracefully, force killing...")
    VMLogger.log(dir, "virt stop: SIGKILL → pid \(pid)")
    let tty = TTYReset.controllingTTY(of: pid)
    kill(pid, SIGKILL)
    Thread.sleep(forTimeInterval: 1.0)
    if let tty = tty {
      TTYReset.restoreSane(ttyPath: tty)
    }

    guard kill(pid, 0) != 0 else {
      throw ValidationError("Failed to stop VM '\(dir.name)' (PID \(pid)).")
    }
    try? FileManager.default.removeItem(at: dir.pidURL)
    print("VM '\(dir.name)' killed.")
    VMLogger.log(dir, "force killed by virt stop")
    if tty != nil {
      fputs("Terminal restored (the VM held it in raw mode when killed).\n", stderr)
    }
  }
}
