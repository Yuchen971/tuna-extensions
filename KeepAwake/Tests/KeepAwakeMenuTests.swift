import Foundation
import TunaKit
import XCTest

@testable import KeepAwakeTuna

final class KeepAwakeMenuTests: XCTestCase {
  private var caffeinate: FakeCaffeinate!
  private var keepAwake: KeepAwake!
  private var stateDirectory: URL!
  private let space = "\u{202F}"

  override func setUpWithError() throws {
    caffeinate = FakeCaffeinate()
    stateDirectory = FileManager.default.temporaryDirectory
      .appending(path: "keepawake-menu-tests-\(UUID().uuidString)")
    keepAwake = KeepAwake(
      stateURL: stateDirectory.appending(path: "session.json"), caffeinate: caffeinate.process,
      now: { KeepAwakeTextTests.now })
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: stateDirectory)
  }

  private func items(_ query: String) -> [CatalogItem] {
    KeepAwakeMenu(
      keepAwake: keepAwake, screen: .stayOn, now: KeepAwakeTextTests.now,
      calendar: KeepAwakeTextTests.calendar, locale: KeepAwakeTextTests.locale
    ).items(for: query)
  }

  private func titles(_ query: String) -> [String] {
    items(query).map(\.title)
  }

  func testWhenOffListsLengths() {
    XCTAssertEqual(titles(""), ["15 min", "30 min", "1 hr", "2 hr", "4 hr", "Until I stop"])
    XCTAssertEqual(items("")[0].detail, "Until 2:25\(space)PM")
  }

  func testWhenOnStartsWithStopAndAddTime() throws {
    try keepAwake.start(.duration(15 * 60), screen: .stayOn)

    let rows = items("")
    XCTAssertEqual(
      rows.map(\.title),
      ["Stop", "Add 30 min", "15 min", "30 min", "1 hr", "2 hr", "4 hr", "Until I stop"])
    XCTAssertEqual(rows[0].detail, "15 min left · until 2:25\(space)PM")
    XCTAssertEqual(rows[1].detail, "Until 2:55\(space)PM")
  }

  func testWhenOnUntilStoppedHidesAddTimeAndUntilIStop() throws {
    try keepAwake.start(.indefinitely, screen: .stayOn)
    XCTAssertEqual(titles(""), ["Stop", "15 min", "30 min", "1 hr", "2 hr", "4 hr"])
  }

  func testTypedLengthComesFirst() {
    XCTAssertEqual(titles("45m"), ["45 min"])
    XCTAssertEqual(items("45m")[0].detail, "Until 2:55\(space)PM")
    XCTAssertEqual(titles("1h30"), ["1 hr 30 min"])
  }

  func testTypedLengthDoesNotRepeatAPreset() {
    XCTAssertEqual(titles("1"), ["1 min", "15 min", "1 hr"])
    XCTAssertEqual(titles("1 hr"), ["1 hr"])
  }

  func testTypedClockTime() {
    let rows = items("until 6pm")
    XCTAssertEqual(rows.map(\.title), ["Until 6:00\(space)PM"])
    XCTAssertEqual(rows[0].detail, "3 hr 50 min")
  }

  func testTypingFiltersRows() throws {
    try keepAwake.start(.duration(15 * 60), screen: .stayOn)
    XCTAssertEqual(titles("stop"), ["Stop", "Until I stop"])
    XCTAssertEqual(titles("add"), ["Add 30 min"])
    XCTAssertEqual(titles("extend"), ["Add 30 min"])
  }

  func testUnreadableAndTooLong() {
    XCTAssertEqual(titles("banana"), ["Can’t read “banana”"])
    XCTAssertEqual(titles("30h"), ["Up to 24 hr"])
  }

  func testRowsRunTheirAction() async throws {
    let rows = items("").compactMap { $0 as? KeepAwakeChoiceItem }
    let thirtyMinutes = try XCTUnwrap(rows.first { $0.title == "30 min" })

    let result = await thirtyMinutes.run()

    guard case .success = result else { return XCTFail("\(result)") }
    XCTAssertEqual(caffeinate.launched, [["-d", "-i", "-t", "1800"]])

    let stop = try XCTUnwrap(items("stop").first as? KeepAwakeChoiceItem)
    XCTAssertEqual(stop.action, .stop)
    _ = await stop.run()
    XCTAssertNil(keepAwake.current())
  }
}
