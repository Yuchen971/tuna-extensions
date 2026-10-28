import AppKit
import Foundation
import TunaKit

/// A file or folder found by Cardinal. As a `FileSystemEntity` it gets Tuna's file
/// icon, preview, Quick Look and every file action (Open, Reveal in Finder, …).
final class CardinalFileItem: FileSystemEntity, @unchecked Sendable {
  private let location: String

  init(file: CardinalFile, now: Date = Date(), isPackage: (URL) -> Bool = CardinalFileItem.isPackage) {
    let url = URL(fileURLWithPath: file.path)
    let kind: FileSystemEntity.Kind =
      switch file.kind {
      case "folder": isPackage(url) ? .package : .directory
      default: .file
      }
    let modified = file.modified.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    location = Self.location(of: url, modified: modified, now: now)
    super.init(displayName: file.name, url: url, kind: kind, capturedAtDate: modified ?? .distantPast)
  }

  /// The containing folder and how long ago the item changed, e.g. `~/Documents · 2 days ago`.
  override var detail: String? { location }

  static func location(of url: URL, modified: Date?, now: Date) -> String {
    let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    guard let modified else { return folder }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return "\(folder) · \(formatter.localizedString(for: modified, relativeTo: now))"
  }

  /// Apps, libraries and other folders that Finder shows as a single file.
  static func isPackage(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
  }
}

/// Last row when Cardinal found more than Tuna shows: opens Cardinal with the same query.
final class CardinalShowAllItem: CatalogItem, Runnable, @unchecked Sendable {
  let query: String
  private let client: CardinalClient

  init(query: String, total: Int, client: CardinalClient = .live) {
    self.query = query
    self.client = client
    super.init(
      id: "cardinal.show-all",
      title: "Show all \(total.formatted()) results in Cardinal",
      type: .entity
    )
  }

  override var detail: String? { "Open Cardinal with “\(query)”" }

  var headlessEligibility: CommandHeadlessEligibility { .guaranteed }
  var executionPolicy: CommandExecutionPolicy { .dismiss }

  func run() async -> ActionResult {
    do {
      try await client.show(query)
      return .success
    } catch CardinalError.notRunning {
      return .failure("Cardinal is not running.")
    } catch {
      return .failure("Could not open Cardinal.")
    }
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol("arrow.up.forward.app")
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }
}

/// Shown instead of results when Cardinal is not running: launches it in the background.
final class CardinalLaunchItem: CatalogItem, Runnable, @unchecked Sendable {
  static let bundleIdentifier = "com.cardinal.one"

  init() {
    super.init(id: "cardinal.launch", title: "Open Cardinal", type: .entity)
  }

  override var detail: String? {
    "Cardinal is not running. It keeps running in the background after you close its window."
  }

  var headlessEligibility: CommandHeadlessEligibility { .guaranteed }
  // Stay open so the user can search again once Cardinal is up.
  var executionPolicy: CommandExecutionPolicy { .keepVisible }

  func run() async -> ActionResult {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier)
    else {
      return .failure("Cardinal is not installed.")
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    do {
      try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
      return .success
    } catch {
      return .failure("Could not open Cardinal.")
    }
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol("play.circle", tintColor: .systemOrange)
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    preview(maxDimension: maxDimension)
  }
}

enum CardinalMessages {
  static func hint() -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Search every file on this Mac",
      message: "Type a name. Cardinal syntax such as ext:pdf, size:>100MB or in:~/Documents also works.",
      symbolName: "magnifyingglass",
      tintColor: .secondaryLabelColor
    )
  }

  static func indexing(indexedFiles: Int) -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Cardinal is indexing this Mac",
      message: "\(indexedFiles.formatted()) files so far. Results appear when the first scan finishes.",
      symbolName: "hourglass",
      tintColor: .secondaryLabelColor
    )
  }

  static func noResults(query: String) -> CatalogMessageItem {
    CatalogMessageItem(
      title: "No files found",
      message: "Nothing in Cardinal matches “\(query)”.",
      symbolName: "magnifyingglass",
      tintColor: .secondaryLabelColor
    )
  }

  static func invalidQuery(_ message: String) -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Check the search syntax",
      message: message,
      symbolName: "exclamationmark.triangle",
      tintColor: .systemOrange
    )
  }

  static func busy() -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Cardinal is busy",
      message: "It is updating its index. Try again in a moment.",
      symbolName: "clock",
      tintColor: .systemOrange
    )
  }

  static func failed(_ message: String) -> CatalogMessageItem {
    CatalogMessageItem(
      title: "Cardinal search failed",
      message: message,
      symbolName: "exclamationmark.triangle",
      tintColor: .systemOrange
    )
  }
}

enum CardinalSearch {
  static let resultLimit = 50

  static func items(for query: String, client: CardinalClient = .live) async throws -> [CatalogItem] {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return [CardinalMessages.hint()]
    }
    do {
      let response = try await client.search(query, limit: resultLimit)
      // Cardinal matches names literally, so "change.md" misses "changes.md". Before
      // saying nothing matched, retry with the words on their own.
      if response.state != .indexing, !response.cancelled, response.total == 0,
        let looseQuery = looseQuery(for: query)
      {
        let looseResponse = try await client.search(looseQuery, limit: resultLimit)
        return try items(for: looseResponse, query: query, searchedQuery: looseQuery)
      }
      return try items(for: response, query: query)
    } catch let error as CardinalError {
      return items(for: error)
    }
  }

  /// Splits a plain query at punctuation, e.g. `change.md` → `change md`, which Cardinal
  /// reads as two words that must both appear in the name. Returns nil for queries that
  /// use Cardinal syntax or that would not change.
  static func looseQuery(for query: String) -> String? {
    let syntax: Set<Character> = [":", "*", "?", "\"", "/", "!", "|", ";", "<", ">", "~"]
    guard !query.contains(where: syntax.contains) else { return nil }
    let words = query.split { !$0.isLetter && !$0.isNumber }
    let loose = words.joined(separator: " ")
    guard words.count > 1, loose != query.trimmingCharacters(in: .whitespaces) else { return nil }
    return loose
  }

  /// - Parameters:
  ///   - query: What the user typed, used in messages.
  ///   - searchedQuery: What was actually sent to Cardinal, when it differs.
  static func items(
    for response: CardinalSearchResponse,
    query: String,
    searchedQuery: String? = nil,
    makeFileItem: (CardinalFile) -> CatalogItem = { CardinalFileItem(file: $0) }
  ) throws -> [CatalogItem] {
    // A newer keystroke already replaced this search; Tuna drops cancelled searches.
    if response.cancelled {
      throw CancellationError()
    }
    if response.state == .indexing {
      return [CardinalMessages.indexing(indexedFiles: response.indexedFiles)]
    }
    if response.results.isEmpty {
      return [CardinalMessages.noResults(query: query)]
    }
    var items = response.results.map(makeFileItem)
    if response.total > response.results.count {
      items.append(CardinalShowAllItem(query: searchedQuery ?? query, total: response.total))
    }
    return items
  }

  static func items(for error: CardinalError) -> [CatalogItem] {
    switch error {
    case .notRunning: [CardinalLaunchItem()]
    case .invalidQuery(let message): [CardinalMessages.invalidQuery(message)]
    case .busy: [CardinalMessages.busy()]
    case .unexpected(let message): [CardinalMessages.failed(message)]
    }
  }
}
