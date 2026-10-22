import Foundation

/// Talks to the local API of the Cardinal app (a fork with a search API).
///
/// Cardinal listens on 127.0.0.1 and writes the port and a fresh access token to
/// `local-api.json` every time it starts. Only the current user can read that file.
struct CardinalClient: Sendable {
  var connectionFile: URL
  var session: URLSession

  static let live = CardinalClient(
    connectionFile: FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/com.cardinal.one/local-api.json"),
    session: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 10
      return URLSession(configuration: configuration)
    }()
  )

  func search(_ query: String, limit: Int) async throws -> CardinalSearchResponse {
    let data = try await send(
      path: "/v1/search",
      method: "GET",
      query: [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "limit", value: String(limit)),
      ]
    )
    do {
      return try JSONDecoder().decode(CardinalSearchResponse.self, from: data)
    } catch {
      throw CardinalError.unexpected("Cardinal sent a response this extension does not understand.")
    }
  }

  /// Brings up the Cardinal window with `query` in its search field.
  func show(_ query: String) async throws {
    _ = try await send(path: "/v1/show", method: "POST", query: [URLQueryItem(name: "q", value: query)])
  }

  private func send(path: String, method: String, query: [URLQueryItem]) async throws -> Data {
    let connection = try readConnection()
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = connection.port
    components.path = path
    components.queryItems = query
    guard let url = components.url else {
      throw CardinalError.unexpected("Could not build the request to Cardinal.")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as URLError
      where [.cannotConnectToHost, .networkConnectionLost, .cannotFindHost].contains(error.code)
    {
      // The connection file outlives a crashed or force-quit Cardinal.
      throw CardinalError.notRunning
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200..<300:
      return data
    case 400:
      throw CardinalError.invalidQuery(Self.errorMessage(in: data) ?? "Cardinal could not read this search.")
    case 401:
      // Another Cardinal instance replaced the token; treat it like a restart in progress.
      throw CardinalError.notRunning
    case 503:
      throw CardinalError.busy
    default:
      throw CardinalError.unexpected(Self.errorMessage(in: data) ?? "Cardinal answered with status \(status).")
    }
  }

  private func readConnection() throws -> Connection {
    guard let data = try? Data(contentsOf: connectionFile) else {
      throw CardinalError.notRunning
    }
    do {
      return try JSONDecoder().decode(Connection.self, from: data)
    } catch {
      throw CardinalError.notRunning
    }
  }

  static func errorMessage(in data: Data) -> String? {
    struct ErrorBody: Decodable { var error: String }
    return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
  }

  struct Connection: Decodable {
    var port: Int
    var token: String
  }
}

enum CardinalError: Error, Equatable {
  /// Cardinal is not running, or it is a version without the local API.
  case notRunning
  /// The query uses Cardinal syntax incorrectly, e.g. an unclosed regex group.
  case invalidQuery(String)
  /// Cardinal is rebuilding its index or took too long to answer.
  case busy
  case unexpected(String)
}

struct CardinalSearchResponse: Decodable, Sendable, Equatable {
  enum State: String, Decodable, Sendable {
    case ready
    /// Catching up on file changes made while Cardinal was closed. Searches work.
    case updating
    /// Scanning the disk for the first time. Searches return nothing yet.
    case indexing
  }

  var state: State
  var indexedFiles: Int
  /// Number of matches before Cardinal cut the list down to the requested limit.
  var total: Int
  /// A newer search replaced this one.
  var cancelled: Bool
  var results: [CardinalFile]
}

struct CardinalFile: Decodable, Sendable, Equatable {
  var name: String
  var path: String
  /// `file`, `folder`, `symlink` or `unknown`.
  var kind: String
  var size: Int64?
  /// Unix timestamp in seconds.
  var modified: Int?
}
