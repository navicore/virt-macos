import XCTest

@testable import virt

final class VMLockTests: XCTestCase {
  private func makeTempVMDir() throws -> VMDirectory {
    let dir = VMDirectory(name: "locktest-\(UUID().uuidString)")
    try dir.create()
    return dir
  }

  func testAcquireThenSecondAcquireFails() throws {
    let dir = try makeTempVMDir()
    defer { try? dir.remove() }

    let lock = try VMLock.acquire(dir: dir)
    XCTAssertThrowsError(try VMLock.acquire(dir: dir)) { error in
      XCTAssertTrue("\(error)".contains("already running"))
    }
    lock.release()
  }

  func testIsLockedReflectsLockState() throws {
    let dir = try makeTempVMDir()
    defer { try? dir.remove() }

    XCTAssertFalse(VMLock.isLocked(dir))
    let lock = try VMLock.acquire(dir: dir)
    XCTAssertTrue(VMLock.isLocked(dir))
    lock.release()
    XCTAssertFalse(VMLock.isLocked(dir))
  }

  func testAcquireSucceedsAfterRelease() throws {
    let dir = try makeTempVMDir()
    defer { try? dir.remove() }

    try VMLock.acquire(dir: dir).release()
    XCTAssertNoThrow(try VMLock.acquire(dir: dir).release())
  }
}
