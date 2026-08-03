import Foundation

/// Terminal, PID-file, and signal-handling helpers for VMInstance.
extension VMInstance {

    // MARK: - Terminal

    func enableRawMode() {
        var current = termios()
        tcgetattr(STDIN_FILENO, &current)
        originalTermios = current
        var raw = current
        cfmakeraw(&raw)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }

    func restoreTerminal() {
        guard var saved = originalTermios else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &saved)
        originalTermios = nil
    }

    // MARK: - PID file

    func writePIDFile() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        try "\(pid)".write(to: dir.pidURL, atomically: true, encoding: .utf8)
    }

    func removePIDFile() {
        try? FileManager.default.removeItem(at: dir.pidURL)
    }

    // MARK: - Signal handling

    /// Route termination signals to a graceful guest shutdown.
    /// Covers SIGINT (sent by `virt stop`), SIGTERM, and SIGHUP (terminal
    /// closed while the console was attached).
    func setupSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.requestShutdown()
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
