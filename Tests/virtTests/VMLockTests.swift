import Foundation
import Testing

@testable import virt

@Suite
struct VMLockTests {
  private func makeTempVMDir() throws -> VMDirectory {
    let dir = VMDirectory(name: "locktest-\(UUID().uuidString)")
    try dir.create()
    return dir
  }

  @Test func acquireThenSecondAcquireFails() throws {
    let dir = try makeTempVMDir()
    defer { try? dir.remove() }

    let lock = try VMLock.acquire(dir: dir)
    do {
      _ = try VMLock.acquire(dir: dir)
      Issue.record("second acquire should have failed")
    } catch {
      #expect("\(error)".contains("already running"))
    }
    lock.release()
  }

  @Test func isLockedReflectsLockState() throws {
    let dir = try makeTempVMDir()
    defer { try? dir.remove() }

    #expect(!VMLock.isLocked(dir))
    let lock = try VMLock.acquire(dir: dir)
    #expect(VMLock.isLocked(dir))
    lock.release()
    #expect(!VMLock.isLocked(dir))
  }

  @Test func acquireSucceedsAfterRelease() throws {
    let dir = try makeTempVMDir()
    defer { try? dir.remove() }

    try VMLock.acquire(dir: dir).release()
    // An error here fails the test; success is the assertion.
    try VMLock.acquire(dir: dir).release()
  }
}
