import Foundation

/// Reads what the user types inside Keep Awake.
enum KeepAwakeInput {
  // "45", "45m", "1h", "1.5 hours", "1h30", "1 hr 30 min". A number without a unit is minutes.
  private static let durationPattern = try! Regex(
    #"^(?:for\s+)?(?:(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours))?\s*(?:(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes)?)?$"#
  ).ignoresCase()

  // "until 6pm", "till 6:30", "6:30 pm", "18:00".
  private static let clockPattern = try! Regex(
    #"^(?:(until|till|til|to)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?$"#
  ).ignoresCase()

  static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> KeepAwakeRequest? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let date = clockTime(text, now: now, calendar: calendar) {
      return .until(date)
    }
    if let seconds = duration(text), seconds > 0 {
      return .duration(seconds)
    }
    return nil
  }

  private static func duration(_ text: String) -> TimeInterval? {
    guard let match = try? durationPattern.wholeMatch(in: text) else { return nil }
    let hours = match.output[1].substring.flatMap { Double($0) }
    let minutes = match.output[2].substring.flatMap { Double($0) }
    guard hours != nil || minutes != nil else { return nil }
    return (hours ?? 0) * 3600 + (minutes ?? 0) * 60
  }

  /// The next time the clock shows the typed time. A plain number only counts as a time
  /// after "until", so "45" stays 45 minutes.
  private static func clockTime(_ text: String, now: Date, calendar: Calendar) -> Date? {
    guard let match = try? clockPattern.wholeMatch(in: text),
      let hour = match.output[2].substring.flatMap({ Int($0) })
    else { return nil }
    let hasUntil = match.output[1].substring != nil
    let minuteText = match.output[3].substring
    let meridiem = match.output[4].substring?.lowercased()
    guard hasUntil || minuteText != nil || meridiem != nil else { return nil }
    let minute = minuteText.flatMap { Int($0) } ?? 0
    guard minute < 60 else { return nil }

    let hours: [Int]
    switch meridiem {
    case "am", "a":
      guard (1...12).contains(hour) else { return nil }
      hours = [hour % 12]
    case "pm", "p":
      guard (1...12).contains(hour) else { return nil }
      hours = [hour % 12 + 12]
    default:
      guard hour < 24 else { return nil }
      // "until 6" means whichever 6 o'clock comes first.
      hours = (1...12).contains(hour) ? [hour % 12, hour % 12 + 12] : [hour]
    }
    return
      hours
      .compactMap {
        calendar.nextDate(
          after: now, matching: DateComponents(hour: $0, minute: minute, second: 0),
          matchingPolicy: .nextTime)
      }
      .min()
  }
}

/// Words shown in Tuna.
enum KeepAwakeText {
  /// "45 min", "1 hr 30 min", "2 hr". Rounds up, so the last seconds still read "1 min".
  static func duration(_ seconds: TimeInterval) -> String {
    let minutes = max(1, Int((seconds / 60).rounded(.up)))
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return "\(rest) min" }
    if rest == 0 { return "\(hours) hr" }
    return "\(hours) hr \(rest) min"
  }

  /// "3:40 PM", with "tomorrow" or "yesterday" when the time is not today.
  static func clock(
    _ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    let time = date.formatted(
      Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
        timeZone: calendar.timeZone))
    let days =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
      ).day ?? 0
    switch days {
    case 0: return time
    case 1: return "\(time) tomorrow"
    case -1: return "\(time) yesterday"
    default:
      return date.formatted(
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
          .weekday(.abbreviated).hour().minute())
    }
  }

  /// Subtitle of the Keep Awake entry: "Off", "On · 37 min left · until 3:40 PM", "On · until you stop".
  static func status(
    _ session: KeepAwakeSession?, now: Date, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    guard let session else { return "Off" }
    guard let endsAt = session.endsAt else { return "On · until you stop" }
    return "On · \(timeLeft(until: endsAt, now: now, calendar: calendar, locale: locale))"
  }

  /// Subtitle of the Stop row: "37 min left · until 3:40 PM", or "On since 2:10 PM".
  static func stopDetail(
    _ session: KeepAwakeSession, now: Date, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    guard let endsAt = session.endsAt else {
      return "On since \(clock(session.startedAt, now: now, calendar: calendar, locale: locale))"
    }
    return timeLeft(until: endsAt, now: now, calendar: calendar, locale: locale)
  }

  static func until(
    _ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    "Until \(clock(date, now: now, calendar: calendar, locale: locale))"
  }

  private static func timeLeft(until endsAt: Date, now: Date, calendar: Calendar, locale: Locale)
    -> String
  {
    let left = duration(endsAt.timeIntervalSince(now))
    return "\(left) left · until \(clock(endsAt, now: now, calendar: calendar, locale: locale))"
  }
}
