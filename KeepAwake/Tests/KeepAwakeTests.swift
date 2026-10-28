import Foundation
import TunaKit
import XCTest

@testable import KeepAwakeTuna

/// Stands in for caffeinate: records launches and lets tests end processes.
final class FakeCaffeinate: @unchecked Sendable {
  var launched: [[String]] = []
  var terminated: [Int32] = []
  var running: Set<Int32> = []
  private var lastPID: Int32 = 100

  var process: CaffeinateProcess {
    CaffeinateProcess(
      launch: { arguments in
        self.launched.append(arguments)
        self.lastPID += 1
        self.running.insert(self.lastPID)
        return self.lastPID
      },
      isRunning: { self.running.contains($0) },
      terminate: { pid in
        self.terminated.append(pid)
        self.running.remove(pid)
      }
    )
  }
}

final class TestClock: @unchecked Sendable {
  var now: Date
  init(_ now: Date) { self.now = now }
  func advance(minutes: Double) { now.addTimeInterval(minutes * 60) }
}

final class KeepAwakeTests: XCTestCase {
  private var caffeinate: FakeCaffeinate!
  private var clock: TestClock!
  private var stateURL: URL!
  private var keepAwake: KeepAwake!

  override func setUpWithError() throws {
    caffeinate = FakeCaffeinate()
    clock = TestClock(KeepAwakeTextTests.now)
    stateURL = FileManager.default.temporaryDirectory
      .appending(path: "keepawake-tests-\(UUID().uuidString)/session.json")
    keepAwake = makeKeepAwake()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: stateURL.deletingLastPathComponent())
  }

  private func makeKeepAwake() -> KeepAwake {
    let clock = clock!
    return KeepAwake(stateURL: stateURL, caffeinate: caffeinate.process, now: { clock.now })
  }

  func testTimedSessionPassesTheLengthToCaffeinate() throws {
    let session = try keepAwake.start(.duration(30 * 60), screen: .stayOn)

    XCTAssertEqual(caffeinate.launched, [["-d", "-i", "-t", "1800"]])
    XCTAssertEqual(session.endsAt, clock.now.addingTimeInterval(1800))
    XCTAssertEqual(keepAwake.current(), session)
  }

  func testScreenCanTurnOffOnlyKeepsTheMacAwake() throws {
    try keepAwake.start(.indefinitely, screen: .canTurnOff)
    XCTAssertEqual(caffeinate.launched, [["-i"]])
    XCTAssertNil(keepAwake.current()?.endsAt)
  }

  func testStartingAgainReplacesTheSession() throws {
    let first = try keepAwake.start(.duration(15 * 60), screen: .stayOn)
    let second = try keepAwake.start(.duration(2 * 3600), screen: .stayOn)

    XCTAssertEqual(caffeinate.terminated, [first.pid])
    XCTAssertEqual(keepAwake.current(), second)
  }

  func testAddingTimeMovesTheEndLaterAndKeepsTheSessionsScreen() throws {
    let first = try keepAwake.start(.duration(15 * 60), screen: .canTurnOff)
    clock.advance(minutes: 5)

    let extended = try keepAwake.extend(by: 30 * 60, screen: .stayOn)

    XCTAssertEqual(extended.endsAt, first.endsAt?.addingTimeInterval(30 * 60))
    XCTAssertEqual(extended.startedAt, first.startedAt)
    XCTAssertEqual(extended.screen, .canTurnOff)
    XCTAssertEqual(caffeinate.launched.last, ["-i", "-t", "2400"])
    XCTAssertEqual(caffeinate.terminated, [first.pid])
  }

  func testAddingTimeWithNothingRunningStartsASession() throws {
    let session = try keepAwake.extend(by: 30 * 60, screen: .stayOn)
    XCTAssertEqual(session.endsAt, clock.now.addingTimeInterval(30 * 60))
  }

  func testStopEndsCaffeinateAndClearsTheStatus() throws {
    let session = try keepAwake.start(.duration(3600), screen: .stayOn)
    keepAwake.stop()

    XCTAssertEqual(caffeinate.terminated, [session.pid])
    XCTAssertNil(keepAwake.current())
    XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
  }

  func testSessionIsOverOnceItsTimeIsUp() throws {
    try keepAwake.start(.duration(15 * 60), screen: .stayOn)
    clock.advance(minutes: 15)
    XCTAssertNil(keepAwake.current())
  }

  func testSessionIsOverWhenCaffeinateIsGone() throws {
    let session = try keepAwake.start(.indefinitely, screen: .stayOn)
    caffeinate.running.remove(session.pid)
    XCTAssertNil(keepAwake.current())
  }

  func testStatusSurvivesARestart() throws {
    let session = try keepAwake.start(.duration(3600), screen: .stayOn)
    XCTAssertEqual(makeKeepAwake().current(), session)
  }
}
