import ArgumentParser
import Foundation

struct List: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List all VMs and their status"
  )

  func run() throws {
    let vms = try VMDirectory.allVMs()
      .filter { FileManager.default.fileExists(atPath: $0.configURL.path) }

    guard !vms.isEmpty else {
      print("No VMs found.")
      return
    }

    let headers = ["NAME", "CPUS", "MEMORY", "DISK", "STATUS"]
    let rightAlign = [false, true, true, true, false]

    var rows: [[String]] = []
    for dir in vms.sorted(by: { $0.name < $1.name }) {
      if let config = try? VMConfig.load(from: dir.configURL) {
        rows.append([
          config.name,
          String(config.cpus),
          "\(config.memoryMB) MB",
          "\(config.diskSizeGB) GB",
          vmStatus(dir: dir),
        ])
      } else {
        rows.append([dir.name, "-", "-", "-", "(corrupt config)"])
      }
    }

    let widths = headers.indices.map { column in
      max(headers[column].count, rows.map { $0[column].count }.max() ?? 0)
    }

    func line(_ cells: [String]) -> String {
      cells.indices.map { index in
        index == cells.count - 1
          ? cells[index]
          : pad(cells[index], toWidth: widths[index], rightAlign: rightAlign[index])
      }.joined(separator: "  ")
    }

    print(line(headers))
    print(String(repeating: "-", count: line(headers).count))
    for row in rows {
      print(line(row))
    }
  }

  private func pad(_ value: String, toWidth width: Int, rightAlign: Bool) -> String {
    let padding = String(repeating: " ", count: max(0, width - value.count))
    return rightAlign ? padding + value : value + padding
  }

  private func vmStatus(dir: VMDirectory) -> String {
    guard VMLock.isLocked(dir) else { return "stopped" }
    let pid = try? String(contentsOf: dir.pidURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let pid = pid, !pid.isEmpty else { return "running" }
    return "running (PID \(pid))"
  }
}
