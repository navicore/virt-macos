import AppKit
import Virtualization

/// Minimal AppKit application that displays a VM's framebuffer in a window.
/// Used by `virt install` for ISO-based OS installation.
class InstallerApp: NSObject, NSApplicationDelegate, VZVirtualMachineDelegate, NSWindowDelegate {
    private let vmInstance: VMInstance
    private var vm: VZVirtualMachine?
    private var window: NSWindow?
    private var forceClose = false
    private var closeTimer: Timer?

    init(vmInstance: VMInstance) {
        self.vmInstance = vmInstance
    }

    func run() throws {
        let vzConfig = try vmInstance.buildGUIConfiguration()

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self

        let vm = VZVirtualMachine(configuration: vzConfig)
        vm.delegate = self
        self.vm = vm

        let vmView = VZVirtualMachineView()
        vmView.virtualMachine = vm
        vmView.capturesSystemKeys = true
        if #available(macOS 14.0, *) {
            // Disable auto-resize during ISO install — installers can't handle high DPI.
            // Enable for post-install GUI boots so the user can resize freely.
            vmView.automaticallyReconfiguresDisplay = (vmInstance.isoPath == nil)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "virt install: \(vmInstance.config.name)"
        window.contentView = vmView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        vmInstance.startVM(vm)

        app.activate(ignoringOtherApps: true)
        app.run()
    }

    // MARK: - VZVirtualMachineDelegate

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        fputs("VM stopped with error: \(error.localizedDescription)\n", stderr)
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        fputs("VM stopped.\n", stderr)
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - NSWindowDelegate

    /// Veto window close while the guest is running; request a graceful
    /// shutdown and close only once the guest has stopped (15s cap, then
    /// forced with a warning). Closing the window mid-write is a power cut.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let vm = vm, !forceClose else { return true }
        switch vm.state {
        case .stopped, .error:
            return true
        default:
            break
        }
        vmInstance.requestShutdown()
        startCloseMonitor()
        return false
    }

    private func startCloseMonitor() {
        guard closeTimer == nil else { return }
        var waited = 0.0
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, let vm = self.vm else {
                timer.invalidate()
                return
            }
            waited += 0.5
            self.vmInstance.issueStopIfPossible()
            if vm.state == .stopped || vm.state == .error {
                timer.invalidate()
                self.closeTimer = nil
                self.window?.close()
            } else if waited >= 15 {
                timer.invalidate()
                self.closeTimer = nil
                fputs("Guest did not shut down within 15s; forcing off (guest filesystem may be unclean).\n", stderr)
                self.forceClose = true
                self.window?.close()
            }
        }
    }

    // MARK: - NSApplicationDelegate

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        vmInstance.cleanup()
    }
}
