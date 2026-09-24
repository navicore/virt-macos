import ArgumentParser

@main
struct Virt: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "virt",
    abstract: "Manage Linux VMs on macOS using Virtualization.framework",
    version: "virt \(VirtVersion.current)",
    subcommands: [
      Create.self,
      Install.self,
      Start.self,
      Stop.self,
      Delete.self,
      List.self,
      Set.self,
      KernelImport.self,
      Doctor.self,
      Completions.self,
    ]
  )
}
