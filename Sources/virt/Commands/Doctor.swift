import ArgumentParser
import Foundation
import Virtualization

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check the host setup and diagnose common problems"
    )

    func run() throws {
        var issues = 0

        print("System")
        print("  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if VZVirtualMachine.isSupported {
            print("  ✓ Virtualization.framework supported")
        } else {
            print("  ✗ Virtualization.framework is not supported on this Mac")
            issues += 1
        }
        if hasVirtualizationEntitlement() {
            print("  ✓ virtualization entitlement present")
        } else {
            print("  ✗ virt binary lacks com.apple.security.virtualization — rebuild with 'make' or reinstall with 'sudo make install'")
            issues += 1
        }
        if hasEntitlement("com.apple.vm.networking") {
            print("  ✓ vm.networking entitlement present (bridge mode available)")
        } else {
            print("  ○ vm.networking missing — bridge mode unavailable (restricted entitlement; needs paid Developer ID signing)")
        }

        print("\nDisk")
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            print(String(format: "  %.1f GB free", Double(available) / 1_073_741_824))
            if available < 5 * 1_073_741_824 {
                print("  ✗ low disk space — VM disk images grow with use")
                issues += 1
            }
        }

        print("\nDNS (port 53)")
        let listeners = port53Listeners()
        if listeners.isEmpty {
            print("  no process bound to port 53")
        } else {
            for entry in listeners {
                print("  \(entry)")
            }
        }
        print("  note: third-party DNS servers on :53 (dnsmasq, docker, ...) have historically broken VM DNS — see README troubleshooting.")

        print("\nVMs")
        let vms = (try? VMDirectory.allVMs()) ?? []
        if vms.isEmpty {
            print("  none")
        }
        for dir in vms.sorted(by: { $0.name < $1.name }) {
            print("  \(dir.name): \(VMLock.isLocked(dir) ? "running" : "stopped")")
        }

        print(issues == 0 ? "\nNo problems found." : "\n\(issues) problem(s) found.")
    }

    /// Read our own binary's entitlements via codesign.
    private func hasVirtualizationEntitlement() -> Bool {
        hasEntitlement("com.apple.security.virtualization")
    }

    private func hasEntitlement(_ entitlement: String) -> Bool {
        Entitlements.has(entitlement)
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
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
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
