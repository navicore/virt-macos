import Foundation
import Testing

@testable import virt

@Suite
struct VersionTests {
  @Test func versionIsStrictSemver() {
    // The release workflow rewrites VirtVersion.current from the pushed
    // vX.Y.Z tag. A non-semver string here means that bump went wrong.
    #expect(
      VirtVersion.current.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
      "VirtVersion.current is not X.Y.Z: \(VirtVersion.current)")
  }
}
