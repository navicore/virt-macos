import ArgumentParser
import Foundation

/// Race-free mutual exclusion for a running VM.
///
/// A running `virt start`/`virt install` holds an exclusive flock on
/// `vm.lock` for its entire lifetime. Locks are released by the kernel when
/// the process dies (even on SIGKILL), so a held lock always means a live
/// VM — unlike a PID file, which can go stale or point at a recycled PID.
final class VMLock {
    private var fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    /// Acquire the exclusive lock for a VM, or throw if another virt
    /// process already holds it.
    static func acquire(dir: VMDirectory) throws -> VMLock {
        let fd = open(dir.lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw ValidationError("Cannot open lock file: \(dir.lockURL.path)")
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            var detail = ""
            if let pid = try? String(contentsOf: dir.pidURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !pid.isEmpty {
                detail = " (PID \(pid))"
            }
            throw ValidationError("VM '\(dir.name)' is already running\(detail).")
        }
        return VMLock(fd: fd)
    }

    /// True if some process currently holds the VM's lock.
    static func isLocked(_ dir: VMDirectory) -> Bool {
        let fd = open(dir.lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return true
        }
        flock(fd, LOCK_UN)
        close(fd)
        return false
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit {
        release()
    }
}
