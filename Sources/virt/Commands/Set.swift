import ArgumentParser
import Foundation

struct Set: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Update VM settings"
  )

  @Argument(help: "Name of the VM")
  var name: String

  @Option(help: "Short description of the VM's purpose")
  var description: String

  func run() throws {
    let dir = VMDirectory(name: name)
    guard dir.exists else {
      throw ValidationError("VM '\(name)' does not exist.")
    }

    let config = try VMConfig.load(from: dir.configURL)
    try config.withDescription(description).write(to: dir.configURL)

    print("Updated '\(name)': description = \(description)")
  }
}
