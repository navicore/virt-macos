import Foundation

/// Checks the running binary's entitlements via codesign.
enum Entitlements {
    static func has(_ entitlement: String) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        var size = UInt32(buffer.count)
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", String(cString: buffer)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .contains(entitlement)
    }
}
