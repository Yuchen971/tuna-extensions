import Foundation
import XCTest

@testable import CardinalTuna

final class CardinalClientTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appending(path: "cardinal-client-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    StubProtocol.reset()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeClient(writeConnection: Bool = true) throws -> CardinalClient {
    let file = directory.appending(path: "local-api.json")
    if writeConnection {
      try Data(#"{"version":1,"port":4321,"token":"secret","pid":1}"#.utf8).write(to: file)
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return CardinalClient(connectionFile: file, session: URLSession(configuration: configuration))
  }

  func testSearchSendsTokenAndQueryAndDecodesResults() async throws {
    StubProtocol.respond(
      status: 200,
      body: """
        {"state":"ready","indexedFiles":10,"total":3,"cancelled":false,
         "results":[{"name":"report.pdf","path":"/Users/me/report.pdf","kind":"file",
                     "size":12,"modified":1700000000,"created":null}]}
        """
    )
    let response = try await makeClient().search("ext:pdf report", limit: 50)

    let request = try XCTUnwrap(StubProtocol.lastRequest)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    XCTAssertEqual(request.httpMethod, "GET")
    let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.host, "127.0.0.1")
    XCTAssertEqual(components.port, 4321)
    XCTAssertEqual(components.path, "/v1/search")
    XCTAssertEqual(components.queryItems?.first { $0.name == "q" }?.value, "ext:pdf report")
    XCTAssertEqual(components.queryItems?.first { $0.name == "limit" }?.value, "50")

    XCTAssertEqual(response.state, .ready)
    XCTAssertEqual(response.total, 3)
    XCTAssertEqual(
      response.results,
      [CardinalFile(name: "report.pdf", path: "/Users/me/report.pdf", kind: "file", size: 12, modified: 1_700_000_000)]
    )
  }

  func testMissingConnectionFileMeansNotRunning() async throws {
    let client = try makeClient(writeConnection: false)
    await assertThrows(CardinalError.notRunning) { _ = try await client.search("a", limit: 5) }
  }

  func testRefusedConnectionMeansNotRunning() async throws {
    StubProtocol.fail(with: URLError(.cannotConnectToHost))
    let client = try makeClient()
    await assertThrows(CardinalError.notRunning) { _ = try await client.search("a", limit: 5) }
  }

  func testBadSyntaxReturnsCardinalsMessage() async throws {
    StubProtocol.respond(status: 400, body: #"{"error":"Invalid query: unclosed group"}"#)
    let client = try makeClient()
    await assertThrows(CardinalError.invalidQuery("Invalid query: unclosed group")) {
      _ = try await client.search("regex:(", limit: 5)
    }
  }

  func testBusyAndWrongToken() async throws {
    let client = try makeClient()
    StubProtocol.respond(status: 503, body: #"{"error":"Cardinal is busy, try again"}"#)
    await assertThrows(CardinalError.busy) { _ = try await client.search("a", limit: 5) }
    StubProtocol.respond(status: 401, body: #"{"error":"Missing or wrong access token"}"#)
    await assertThrows(CardinalError.notRunning) { _ = try await client.search("a", limit: 5) }
  }

  func testShowPostsTheQuery() async throws {
    StubProtocol.respond(status: 200, body: #"{"ok":true}"#)
    try await makeClient().show("annual report")
    let request = try XCTUnwrap(StubProtocol.lastRequest)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.path, "/v1/show")
    XCTAssertEqual(
      URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
        .queryItems?.first?.value,
      "annual report"
    )
  }

  private func assertThrows(
    _ expected: CardinalError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
  ) async {
    do {
      try await body()
      XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as CardinalError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("Unexpected error \(error)", file: file, line: line)
    }
  }
}

/// Answers every request with a canned response, and remembers the last request.
final class StubProtocol: URLProtocol, @unchecked Sendable {
  private struct Stub {
    var status = 200
    var body = Data()
    var error: Error?
    var handler: (@Sendable (URLRequest) -> (status: Int, body: String))?
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var stub = Stub()
  nonisolated(unsafe) private static var requests: [URLRequest] = []

  static var lastRequest: URLRequest? { lock.withLock { requests.last } }

  static func reset() {
    lock.withLock {
      stub = Stub()
      requests = []
    }
  }

  static func respond(status: Int, body: String) {
    lock.withLock { stub = Stub(status: status, body: Data(body.utf8)) }
  }

  static func fail(with error: Error) {
    lock.withLock { stub = Stub(error: error) }
  }

  /// Answers each request based on what it asks for.
  static func respond(_ handler: @escaping @Sendable (URLRequest) -> (status: Int, body: String)) {
    lock.withLock { stub = Stub(handler: handler) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    var stub = Self.lock.withLock {
      Self.requests.append(request)
      return Self.stub
    }
    if let handler = stub.handler {
      let answer = handler(request)
      stub.status = answer.status
      stub.body = Data(answer.body.utf8)
    }
    if let error = stub.error {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: stub.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
