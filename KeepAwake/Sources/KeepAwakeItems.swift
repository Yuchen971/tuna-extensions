import AppKit
import Foundation
import TunaKit

/// The rows inside Keep Awake, built fresh each time they are shown.
struct KeepAwakeMenu {
  static let presets: [(id: String, title: String, seconds: TimeInterval)] = [
    ("keepawake.15m", "15 min", 15 * 60),
    ("keepawake.30m", "30 min", 30 * 60),
    ("keepawake.1h", "1 hr", 60 * 60),
    ("keepawake.2h", "2 hr", 2 * 60 * 60),
    ("keepawake.4h", "4 hr", 4 * 60 * 60),
  ]
  static let extensionStep: TimeInterval = 30 * 60

  let keepAwake: KeepAwake
  let screen: ScreenMode
  let now: Date
  var calendar: Calendar = .current
  var locale: Locale = .current

  func items(for query: String) -> [CatalogItem] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let choices = choices(session: keepAwake.current())
    guard !query.isEmpty else { return choices }

    let matches = choices.filter { $0.matches(query) }
    guard let request = KeepAwakeInput.parse(query, now: now, calendar: calendar) else {
      return matches.isEmpty ? [KeepAwakeMessages.unreadable(query)] : matches
    }
    if case .duration(let seconds) = request, seconds > KeepAwake.maximumDuration {
      return [KeepAwakeMessages.tooLong()]
    }
    let typed = typedChoice(request)
    return [typed] + matches.filter { $0.title != typed.title }
  }

  /// Stop and Add 30 min while a session runs, then the lengths to start a new one.
  func choices(session: KeepAwakeSession?) -> [KeepAwakeChoiceItem] {
    var items: [KeepAwakeChoiceItem] = []
    if let session {
      items.append(
        choice(
          id: "keepawake.stop", title: "Stop",
          detail: KeepAwakeText.stopDetail(session, now: now, calendar: calendar, locale: locale),
          symbolName: "stop.circle", keywords: ["Off", "End", "Sleep"], action: .stop))
      if let endsAt = session.endsAt {
        items.append(
          choice(
            id: "keepawake.add30m", title: "Add 30 min",
            detail: until(endsAt.addingTimeInterval(Self.extensionStep)),
            symbolName: "plus.circle", keywords: ["Extend", "More"],
            action: .extend(Self.extensionStep)))
      }
    }
    for preset in Self.presets {
      items.append(
        choice(
          id: preset.id, title: preset.title, detail: until(now.addingTimeInterval(preset.seconds)),
          symbolName: "timer", action: .start(.duration(preset.seconds))))
    }
    let runsUntilStopped = session != nil && session?.endsAt == nil
    if !runsUntilStopped {
      items.append(
        choice(
          id: "keepawake.indefinitely", title: "Until I stop", detail: nil,
          symbolName: "infinity", keywords: ["Forever", "Indefinitely", "Always"],
          action: .start(.indefinitely)))
    }
    return items
  }

  /// The row for a length the user typed, e.g. "45 min" or "Until 6:00 PM".
  private func typedChoice(_ request: KeepAwakeRequest) -> KeepAwakeChoiceItem {
    switch request {
    case .until(let date):
      choice(
        id: "keepawake.typed", title: until(date),
        detail: KeepAwakeText.duration(date.timeIntervalSince(now)),
        symbolName: "clock", action: .start(request))
    case .duration(let seconds):
      choice(
        id: "keepawake.typed", title: KeepAwakeText.duration(seconds),
        detail: until(now.addingTimeInterval(seconds)),
        symbolName: "timer", action: .start(request))
    case .indefinitely:
      choice(
        id: "keepawake.indefinitely", title: "Until I stop", detail: nil,
        symbolName: "infinity", action: .start(request))
    }
  }

  private func until(_ date: Date) -> String {
    KeepAwakeText.until(date, now: now, calendar: calendar, locale: locale)
  }

  private func choice(
    id: String, title: String, detail: String?, symbolName: String, keywords: [String] = [],
    action: KeepAwakeChoiceItem.Action
  ) -> KeepAwakeChoiceItem {
    KeepAwakeChoiceItem(
      id: id, title: title, detail: detail, symbolName: symbolName, keywords: keywords,
      action: action, keepAwake: keepAwake, screen: screen)
  }
}

/// A row inside Keep Awake. Runs right away and closes Tuna.
final class KeepAwakeChoiceItem: CatalogItem, Runnable, @unchecked Sendable {
  enum Action: Equatable {
    case start(KeepAwakeRequest)
    case extend(TimeInterval)
    case stop
  }

  let action: Action
  private let subtitle: String?
  private let symbolName: String
  private let keywords: [String]
  private let keepAwake: KeepAwake
  private let screen: ScreenMode

  init(
    id: String, title: String, detail: String?, symbolName: String, keywords: [String],
    action: Action, keepAwake: KeepAwake, screen: ScreenMode
  ) {
    self.action = action
    self.subtitle = detail
    self.symbolName = symbolName
    self.keywords = keywords
    self.keepAwake = keepAwake
    self.screen = screen
    super.init(id: id, title: title, type: .entity)
    // Tuna offers Run as the default action only for commands.
    typeID = .command
  }

  override var detail: String? { subtitle }

  override var searchKeys: [String] { [title] + keywords }

  /// True when the query starts the row's title, a keyword, or one of their words.
  func matches(_ query: String) -> Bool {
    let query = query.lowercased()
    return searchKeys.contains { key in
      let key = key.lowercased()
      return key.hasPrefix(query) || key.split(separator: " ").contains { $0.hasPrefix(query) }
    }
  }

  var headlessEligibility: CommandHeadlessEligibility { .guaranteed }
  var executionPolicy: CommandExecutionPolicy { .dismiss }

  func run() async -> ActionResult {
    do {
      switch action {
      case .start(let request): try keepAwake.start(request, screen: screen)
      case .extend(let seconds): try keepAwake.extend(by: seconds, screen: screen)
      case .stop: keepAwake.stop()
      }
      return .success
    } catch {
      return .failure("Could not keep this Mac awake.")
    }
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol(symbolName)
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }
}

enum KeepAwakeMessages {
  static func unreadable(_ query: String) -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Can’t read “\(query)”",
      message: "Try 45m, 1h30m or until 6pm",
      symbolName: "questionmark.circle",
      tintColor: .secondaryLabelColor
    )
  }

  static func tooLong() -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Up to 24 hr",
      message: "For longer, pick Until I stop",
      symbolName: "exclamationmark.triangle",
      tintColor: .systemOrange
    )
  }
}
