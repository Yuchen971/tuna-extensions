import Foundation
import XCTest

@testable import KeepAwakeTuna

final class KeepAwakeTextTests: XCTestCase {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()
  static let locale = Locale(identifier: "en_US")
  /// Tuesday 2026-10-27 14:10:00 UTC.
  static let now = Date(timeIntervalSince1970: 1_793_110_200)

  private func parse(_ text: String) -> KeepAwakeRequest? {
    KeepAwakeInput.parse(text, now: Self.now, calendar: Self.calendar)
  }

  private func time(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
    let day = Self.calendar.date(byAdding: .day, value: dayOffset, to: Self.now)!
    return Self.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
  }

  func testNowIsTheExpectedAfternoon() {
    XCTAssertEqual(Self.calendar.component(.hour, from: Self.now), 14)
    XCTAssertEqual(Self.calendar.component(.minute, from: Self.now), 10)
  }

  func testDurations() {
    XCTAssertEqual(parse("45"), .duration(45 * 60))
    XCTAssertEqual(parse("45m"), .duration(45 * 60))
    XCTAssertEqual(parse("45 min"), .duration(45 * 60))
    XCTAssertEqual(parse("90 minutes"), .duration(90 * 60))
    XCTAssertEqual(parse("1h"), .duration(3600))
    XCTAssertEqual(parse("2 Hours"), .duration(7200))
    XCTAssertEqual(parse("1.5h"), .duration(5400))
    XCTAssertEqual(parse("1h30"), .duration(5400))
    XCTAssertEqual(parse("1h30m"), .duration(5400))
    XCTAssertEqual(parse("1 hr 30 min"), .duration(5400))
    XCTAssertEqual(parse("for 20m"), .duration(1200))
    XCTAssertEqual(parse(" 10 "), .duration(600))
  }

  func testClockTimes() {
    XCTAssertEqual(parse("until 6pm"), .until(time(18, 0)))
    XCTAssertEqual(parse("6:30 pm"), .until(time(18, 30)))
    XCTAssertEqual(parse("18:00"), .until(time(18, 0)))
    XCTAssertEqual(parse("till 9am"), .until(time(9, 0, dayOffset: 1)))
    XCTAssertEqual(parse("until 2:00 PM"), .until(time(14, 0, dayOffset: 1)))
  }

  func testClockWithoutAmPmPicksTheNextOne() {
    XCTAssertEqual(parse("until 6"), .until(time(18, 0)))
    XCTAssertEqual(parse("until 3"), .until(time(15, 0)))
    XCTAssertEqual(parse("until 2"), .until(time(2, 0, dayOffset: 1)))
    XCTAssertEqual(parse("until 12"), .until(time(0, 0, dayOffset: 1)))
    XCTAssertEqual(parse("1:30"), .until(time(1, 30, dayOffset: 1)))
  }

  func testUnreadableInput() {
    XCTAssertNil(parse(""))
    XCTAssertNil(parse("0"))
    XCTAssertNil(parse("stop"))
    XCTAssertNil(parse("until"))
    XCTAssertNil(parse("25:00"))
    XCTAssertNil(parse("13pm"))
    XCTAssertNil(parse("6:75"))
    XCTAssertNil(parse("1 30"))
  }

  func testDurationText() {
    XCTAssertEqual(KeepAwakeText.duration(10), "1 min")
    XCTAssertEqual(KeepAwakeText.duration(60), "1 min")
    XCTAssertEqual(KeepAwakeText.duration(61), "2 min")
    XCTAssertEqual(KeepAwakeText.duration(45 * 60), "45 min")
    XCTAssertEqual(KeepAwakeText.duration(3600), "1 hr")
    XCTAssertEqual(KeepAwakeText.duration(5400), "1 hr 30 min")
    XCTAssertEqual(KeepAwakeText.duration(4 * 3600), "4 hr")
  }

  private func clock(_ date: Date) -> String {
    KeepAwakeText.clock(date, now: Self.now, calendar: Self.calendar, locale: Self.locale)
  }

  func testClockText() {
    let space = "\u{202F}"
    XCTAssertEqual(clock(time(15, 40)), "3:40\(space)PM")
    XCTAssertEqual(clock(time(1, 5, dayOffset: 1)), "1:05\(space)AM tomorrow")
    XCTAssertEqual(clock(time(23, 0, dayOffset: -1)), "11:00\(space)PM yesterday")
  }

  func testStatus() {
    let space = "\u{202F}"
    func status(_ session: KeepAwakeSession?) -> String {
      KeepAwakeText.status(session, now: Self.now, calendar: Self.calendar, locale: Self.locale)
    }
    func stopDetail(_ session: KeepAwakeSession) -> String {
      KeepAwakeText.stopDetail(session, now: Self.now, calendar: Self.calendar, locale: Self.locale)
    }
    let timed = KeepAwakeSession(
      pid: 1, startedAt: time(13, 0), endsAt: time(14, 47), screen: .stayOn)
    let untilStopped = KeepAwakeSession(
      pid: 1, startedAt: time(13, 0), endsAt: nil, screen: .stayOn)

    XCTAssertEqual(status(nil), "Off")
    XCTAssertEqual(status(timed), "On · 37 min left · until 2:47\(space)PM")
    XCTAssertEqual(status(untilStopped), "On · until you stop")
    XCTAssertEqual(stopDetail(timed), "37 min left · until 2:47\(space)PM")
    XCTAssertEqual(stopDetail(untilStopped), "On since 1:00\(space)PM")
  }
}
