import ArgumentParser
import Foundation
import Virtualization

struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check the host setup and diagnose common problems"
  )

  func run() throws {
    var issues = 0
    issues += checkSystem()
    issues += checkDisk()
    checkDNS()
    checkVMs()
    print(issues == 0 ? "\nNo problems found." : "\n\(issues) problem(s) found.")
  }

  private func checkSystem() -> Int {
    var issues = 0
    print("System")
    print("  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    if VZVirtualMachine.isSupported {
      print("  ✓ Virtualization.framework supported")
    } else {
      print("  ✗ Virtualization.framework is not supported on this Mac")
      issues += 1
    }
    if Entitlements.has("com.apple.security.virtualization") {
      print("  ✓ virtualization entitlement present")
    } else {
      print("  ✗ virt lacks com.apple.security.virtualization — rebuild with 'just dev'")
      issues += 1
    }
    if Entitlements.has("com.apple.vm.networking") {
      print("  ✓ vm.networking entitlement present (bridge mode available)")
    } else {
      print("  ○ vm.networking missing — bridge mode needs paid Developer ID signing")
    }
    return issues
  }

  private func checkDisk() -> Int {
    print("\nDisk")
    let home = FileManager.default.homeDirectoryForCurrentUser
    let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    guard let available = values?.volumeAvailableCapacityForImportantUsage else { return 0 }
    print(String(format: "  %.1f GB free", Double(available) / 1_073_741_824))
    guard available < 5 * 1_073_741_824 else { return 0 }
    print("  ✗ low disk space — VM disk images grow with use")
    return 1
  }

  private func checkDNS() {
    print("\nDNS (port 53)")
    let listeners = port53Listeners()
    if listeners.isEmpty {
      print("  no process bound to port 53")
    } else {
      for entry in listeners {
        print("  \(entry)")
      }
    }
    print("  note: third-party DNS on :53 has historically broken VM DNS (see README).")
  }

  private func checkVMs() {
    print("\nVMs")
    let vms = (try? VMDirectory.allVMs()) ?? []
    if vms.isEmpty {
      print("  none")
    }
    for dir in vms.sorted(by: { $0.name < $1.name }) {
      print("  \(dir.name): \(VMLock.isLocked(dir) ? "running" : "stopped")")
    }
  }

  /// Command names and PIDs of processes bound to port 53 (TCP or UDP).
  private func port53Listeners() -> [String] {
    var results: [String] = []
    for args in [["-nP", "-iTCP:53", "-sTCP:LISTEN"], ["-nP", "-iUDP:53"]] {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
      process.arguments = args
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      guard (try? process.run()) != nil else { continue }
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      for line in output.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: " ", omittingEmptySubsequences: true)
        guard cols.count >= 2 else { continue }
        let entry = "\(cols[0]) (pid \(cols[1]))"
        if !results.contains(entry) {
          results.append(entry)
        }
      }
    }
    return results
  }
}
