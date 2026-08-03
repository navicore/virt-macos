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

        guard let pidString = try? String(contentsOf: dir.pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidString) else {
            throw ValidationError("VM '\(name)' is running but its PID file is missing or corrupt. Find the process with: ps aux | grep virt")
        }

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

        // Wait up to 15 seconds for the process to exit
        let deadline = Date(timeIntervalSinceNow: 15)
        while Date() < deadline {
            if kill(pid, 0) != 0 {
                print("VM '\(name)' stopped.")
                VMLogger.log(dir, "stopped gracefully")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Escalate to SIGKILL. The killed process can't restore its terminal
        // from raw mode, so capture its tty first and repair it after.
        print("VM did not stop gracefully, force killing...")
        VMLogger.log(dir, "virt stop: SIGKILL → pid \(pid)")
        let tty = TTYReset.controllingTTY(of: pid)
        kill(pid, SIGKILL)
        Thread.sleep(forTimeInterval: 1.0)
        if let tty = tty {
            TTYReset.restoreSane(ttyPath: tty)
        }

        if kill(pid, 0) != 0 {
            try? FileManager.default.removeItem(at: dir.pidURL)
            print("VM '\(name)' killed.")
            VMLogger.log(dir, "force killed by virt stop")
            if tty != nil {
                fputs("Terminal restored (the VM held it in raw mode when killed).\n", stderr)
            }
        } else {
            throw ValidationError("Failed to stop VM '\(name)' (PID \(pid)).")
        }
    }
}
