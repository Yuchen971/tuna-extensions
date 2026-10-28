import Foundation
import TunaKit
import XCTest

@testable import CardinalTuna

final class CardinalSearchTests: XCTestCase {
  private func response(
    state: CardinalSearchResponse.State = .ready,
    total: Int,
    files: [CardinalFile],
    cancelled: Bool = false
  ) -> CardinalSearchResponse {
    CardinalSearchResponse(
      state: state, indexedFiles: 1_234_567, total: total, cancelled: cancelled, results: files)
  }

  private let report = CardinalFile(
    name: "report.pdf", path: "/Users/me/Documents/report.pdf", kind: "file", size: 10,
    modified: 1_700_000_000)
  private let folder = CardinalFile(
    name: "Reports", path: "/Users/me/Reports", kind: "folder", size: nil, modified: nil)

  func testResultsKeepCardinalsOrderAndEndWithShowAll() throws {
    let items = try CardinalSearch.items(
      for: response(total: 120, files: [report, folder]), query: "report")

    XCTAssertEqual(items.count, 3)
    let first = try XCTUnwrap(items[0] as? CardinalFileItem)
    XCTAssertEqual(first.title, "report.pdf")
    XCTAssertEqual(first.url.path, "/Users/me/Documents/report.pdf")
    XCTAssertEqual(first.kind, .file)
    let second = try XCTUnwrap(items[1] as? CardinalFileItem)
    XCTAssertEqual(second.kind, .directory)

    let showAll = try XCTUnwrap(items[2] as? CardinalShowAllItem)
    XCTAssertEqual(showAll.title, "Show all \(120.formatted()) results in Cardinal")
    XCTAssertEqual(showAll.query, "report")
  }

  func testNoShowAllWhenEverythingFits() throws {
    let items = try CardinalSearch.items(for: response(total: 1, files: [report]), query: "report")
    XCTAssertEqual(items.count, 1)
    XCTAssertTrue(items[0] is CardinalFileItem)
  }

  func testPackagesAreNotBrowsedAsFolders() {
    let app = CardinalFile(
      name: "Tuna.app", path: "/Applications/Tuna.app", kind: "folder", size: nil, modified: nil)
    XCTAssertEqual(CardinalFileItem(file: app, isPackage: { _ in true }).kind, .package)
    XCTAssertEqual(CardinalFileItem(file: app, isPackage: { _ in false }).kind, .directory)
  }

  func testDetailShowsFolderAndAge() {
    let now = Date(timeIntervalSince1970: 1_700_000_000 + 2 * 86_400)
    let item = CardinalFileItem(file: report, now: now)
    let detail = item.detail ?? ""
    XCTAssertTrue(detail.hasPrefix("/Users/me/Documents · "), detail)
    XCTAssertEqual(CardinalFileItem(file: folder).detail, "/Users/me")
  }

  func testIndexingEmptyAndCancelledResponses() throws {
    let indexing = try CardinalSearch.items(
      for: response(state: .indexing, total: 0, files: []), query: "a")
    XCTAssertEqual(indexing.first?.title, "Cardinal is indexing this Mac")

    let empty = try CardinalSearch.items(for: response(total: 0, files: []), query: "zzz")
    XCTAssertEqual(empty.first?.title, "No files found")

    XCTAssertThrowsError(
      try CardinalSearch.items(for: response(total: 0, files: [], cancelled: true), query: "a")
    ) { XCTAssertTrue($0 is CancellationError) }
  }

  func testErrorsBecomeHelpfulRows() {
    XCTAssertTrue(CardinalSearch.items(for: .notRunning).first is CardinalLaunchItem)
    XCTAssertEqual(
      CardinalSearch.items(for: .invalidQuery("unclosed group")).first?.title,
      "Check the search syntax")
    XCTAssertEqual(CardinalSearch.items(for: .busy).first?.title, "Cardinal is busy")
  }

  func testLooseQuerySplitsPlainQueriesAtPunctuation() {
    XCTAssertEqual(CardinalSearch.looseQuery(for: "change.md"), "change md")
    XCTAssertEqual(CardinalSearch.looseQuery(for: "q3_report-final"), "q3 report final")
    XCTAssertEqual(CardinalSearch.looseQuery(for: "年度.报告"), "年度 报告")
    // Already plain words, a single word, or Cardinal syntax: nothing to loosen.
    XCTAssertNil(CardinalSearch.looseQuery(for: "annual report"))
    XCTAssertNil(CardinalSearch.looseQuery(for: "changes"))
    XCTAssertNil(CardinalSearch.looseQuery(for: "ext:pdf invoice"))
    XCTAssertNil(CardinalSearch.looseQuery(for: "*.md"))
    XCTAssertNil(CardinalSearch.looseQuery(for: "~/Documents"))
  }

  func testNoMatchRetriesWithLooseWords() async throws {
    StubProtocol.reset()
    StubProtocol.respond { request in
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "q" }?.value
      let results =
        query == "change md"
        ? #"[{"name":"changes.md","path":"/Users/me/changes.md","kind":"file","size":1,"modified":null}]"#
        : "[]"
      let total = query == "change md" ? 60 : 0
      return (
        200,
        #"{"state":"ready","indexedFiles":5,"total":\#(total),"cancelled":false,"results":\#(results)}"#
      )
    }
    let items = try await CardinalSearch.items(for: "change.md", client: try stubClient())

    XCTAssertEqual(items.first?.title, "changes.md")
    // "Show all" opens Cardinal with the query that actually found something.
    XCTAssertEqual((items.last as? CardinalShowAllItem)?.query, "change md")
  }

  private func stubClient() throws -> CardinalClient {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "cardinal-search-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "local-api.json")
    try Data(#"{"port":4321,"token":"secret"}"#.utf8).write(to: file)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return CardinalClient(connectionFile: file, session: URLSession(configuration: configuration))
  }

  func testEmptyQueryShowsTheHintWithoutAskingCardinal() async throws {
    let unreachable = CardinalClient(
      connectionFile: URL(fileURLWithPath: "/nonexistent/local-api.json"), session: .shared)
    let items = try await CardinalSearch.items(for: "   ", client: unreachable)
    XCTAssertEqual(items.first?.title, "Search every file on this Mac")
  }
}
