import XCTest

@testable import virt

final class VersionTests: XCTestCase {
  func testVersionIsStrictSemver() {
    // The release workflow rewrites VirtVersion.current from the pushed
    // vX.Y.Z tag. A non-semver string here means that bump went wrong.
    XCTAssertNotNil(
      VirtVersion.current.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
      "VirtVersion.current is not X.Y.Z: \(VirtVersion.current)")
  }
}
