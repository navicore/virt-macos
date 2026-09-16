import ArgumentParser
import Foundation
import Virtualization

/// Shared VM runtime for both headless and GUI modes.
/// Hardware configuration lives in VMConfiguration.swift;
/// terminal/PID/signal helpers live in VMInstance+Support.swift.
final class VMInstance: NSObject, VZVirtualMachineDelegate {
  let config: VMConfig
  let dir: VMDirectory
  let isoPath: String?
  let sharePath: String?
  var virtualMachine: VZVirtualMachine?
  var shutdownRequested = false
  var shutdownDeadline: Date?
  var stopRequestIssued = false
  var signalSources: [any DispatchSourceSignal] = []
  var originalTermios: termios?

  init(config: VMConfig, dir: VMDirectory, isoPath: String?, sharePath: String? = nil) {
    self.config = config
    self.dir = dir
    self.isoPath = isoPath
    self.sharePath = sharePath
  }

  // MARK: - Headless run (virt start)

  func runHeadless() throws {
    defer {
      restoreTerminal()
      removePIDFile()
    }
    let vzConfig = try buildConfiguration(gui: false)
    try vzConfig.validate()

    let vm = VZVirtualMachine(configuration: vzConfig)
    vm.delegate = self
    self.virtualMachine = vm

    try writePIDFile()
    setupSignalHandlers()
    VMLogger.log(dir, "starting headless (cpus=\(config.cpus), memory=\(config.memoryMB) MB)")

    var startError: Error?
    vm.start { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          VMLogger.log(self.dir, "started")
          fputs("VM running. Console output appears once the guest boots.\n", stderr)
        case .failure(let error):
          VMLogger.log(self.dir, "start failed: \(error.localizedDescription)")
          fputs("VM start failed: \(error.localizedDescription)\n", stderr)
          startError = error
        }
      }
    }

    while true {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
      if startError != nil { break }
      if vm.state == .stopped || vm.state == .error { break }
      if shutdownRequested {
        issueStopIfPossible()
        if let deadline = shutdownDeadline, Date() > deadline {
          fputs("Force stopping VM...\n", stderr)
          VMLogger.log(dir, "force stopping — guest did not shut down within 10s")
          vm.stop { error in
            if let error = error {
              fputs("Force stop failed: \(error.localizedDescription)\n", stderr)
            }
          }
          RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
          break
        }
      }
    }

    if let startError = startError {
      throw startError
    }
  }

  // MARK: - GUI run (virt install)

  func startVM(_ vm: VZVirtualMachine) {
    self.virtualMachine = vm
    try? writePIDFile()
    VMLogger.log(dir, "starting GUI (iso=\(isoPath ?? "none"))")

    vm.start { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          VMLogger.log(self.dir, "started")
        case .failure(let error):
          VMLogger.log(self.dir, "start failed: \(error.localizedDescription)")
          fputs("VM start failed: \(error.localizedDescription)\n", stderr)
          self.cleanup()
          exit(1)
        }
      }
    }
  }

  func cleanup() {
    removePIDFile()
    VMLogger.log(dir, "session ended")
  }

  // MARK: - Shutdown

  /// Record shutdown intent. The ACPI request is issued by
  /// `issueStopIfPossible()` once the VM can accept it — during early
  /// boot `canRequestStop` is false, and issuing immediately would just
  /// drop the request.
  func requestShutdown() {
    guard !shutdownRequested else { return }
    shutdownRequested = true
    shutdownDeadline = Date(timeIntervalSinceNow: 10)
    VMLogger.log(dir, "shutdown requested")
    fputs("Shutdown requested, waiting up to 10 seconds...\n", stderr)
    issueStopIfPossible()
  }

  /// Issue the ACPI shutdown request if the VM is ready. Idempotent.
  func issueStopIfPossible() {
    guard shutdownRequested, !stopRequestIssued,
      let vm = virtualMachine, vm.canRequestStop
    else { return }
    stopRequestIssued = true
    do {
      try vm.requestStop()
    } catch {
      fputs("Failed to request stop: \(error.localizedDescription)\n", stderr)
      VMLogger.log(dir, "requestStop failed: \(error.localizedDescription)")
    }
  }

  // MARK: - VZVirtualMachineDelegate

  func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
    fputs("VM stopped with error: \(error.localizedDescription)\n", stderr)
    VMLogger.log(dir, "stopped with error: \(error.localizedDescription)")
    shutdownRequested = true
  }

  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    fputs("VM stopped.\n", stderr)
    VMLogger.log(dir, "guest stopped")
    shutdownRequested = true
  }
}
