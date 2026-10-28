import Darwin
import Foundation

/// What a session keeps awake. The Mac itself never sleeps during a session.
enum ScreenMode: String, Codable, Sendable {
  case stayOn = "on"
  case canTurnOff = "off"

  var caffeinateArguments: [String] {
    switch self {
    case .stayOn: ["-d", "-i"]
    case .canTurnOff: ["-i"]
    }
  }
}

/// How long the user asked to stay awake.
enum KeepAwakeRequest: Equatable, Sendable {
  case duration(TimeInterval)
  case until(Date)
  case indefinitely

  /// nil when the session runs until the user stops it.
  func endDate(from now: Date) -> Date? {
    switch self {
    case .duration(let seconds): now.addingTimeInterval(seconds)
    case .until(let date): date
    case .indefinitely: nil
    }
  }
}

struct KeepAwakeSession: Codable, Equatable, Sendable {
  var pid: Int32
  var startedAt: Date
  /// nil when the session runs until the user stops it.
  var endsAt: Date?
  var screen: ScreenMode
}

/// Launches and signals `/usr/bin/caffeinate`. Replaceable in tests.
struct CaffeinateProcess: Sendable {
  var launch: @Sendable (_ arguments: [String]) throws -> Int32
  var isRunning: @Sendable (_ pid: Int32) -> Bool
  var terminate: @Sendable (_ pid: Int32) -> Void

  static let path = "/usr/bin/caffeinate"

  static let live = CaffeinateProcess(
    launch: { arguments in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      process.terminationHandler = { RunningProcesses.shared.remove($0) }
      RunningProcesses.shared.insert(process)
      do {
        try process.run()
      } catch {
        RunningProcesses.shared.remove(process)
        throw error
      }
      return process.processIdentifier
    },
    isRunning: { pid in executablePath(of: pid) == path },
    terminate: { pid in
      // The pid comes from a file and may have been reused: only ever signal caffeinate.
      guard executablePath(of: pid) == path else { return }
      kill(pid, SIGTERM)
    }
  )

  static func executablePath(of pid: Int32) -> String? {
    guard pid > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
  }
}

/// Keeps each Process alive until caffeinate exits, so Foundation is still around to reap it.
private final class RunningProcesses: @unchecked Sendable {
  static let shared = RunningProcesses()

  private let lock = NSLock()
  private var processes: Set<Process> = []

  func insert(_ process: Process) {
    lock.withLock { _ = processes.insert(process) }
  }

  func remove(_ process: Process) {
    lock.withLock { _ = processes.remove(process) }
  }
}

/// Starts and stops keep-awake sessions. Each session is one caffeinate process, which
/// exits by itself when a timed session ends. The session is saved to disk so its status
/// survives a Tuna restart; caffeinate keeps running if Tuna quits.
final class KeepAwake: @unchecked Sendable {
  static let live = KeepAwake()
  static let maximumDuration: TimeInterval = 24 * 60 * 60

  static var defaultStateURL: URL {
    URL.applicationSupportDirectory.appending(path: "com.yuchenli.tuna.keepawake/session.json")
  }

  private let stateURL: URL
  private let caffeinate: CaffeinateProcess
  private let now: @Sendable () -> Date
  private let lock = NSLock()

  init(
    stateURL: URL = KeepAwake.defaultStateURL,
    caffeinate: CaffeinateProcess = .live,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.stateURL = stateURL
    self.caffeinate = caffeinate
    self.now = now
  }

  /// The running session, or nil when the Mac can sleep as usual.
  func current() -> KeepAwakeSession? {
    lock.withLock { activeSession() }
  }

  /// Replaces any running session.
  @discardableResult
  func start(_ request: KeepAwakeRequest, screen: ScreenMode) throws -> KeepAwakeSession {
    try lock.withLock {
      let time = now()
      return try replaceSession(with: request.endDate(from: time), screen: screen, startedAt: time)
    }
  }

  /// Moves the end of a timed session later. Starts a new session when none is running.
  @discardableResult
  func extend(by seconds: TimeInterval, screen: ScreenMode) throws -> KeepAwakeSession {
    try lock.withLock {
      let time = now()
      guard let session = activeSession() else {
        return try replaceSession(with: time.addingTimeInterval(seconds), screen: screen, startedAt: time)
      }
      guard let endsAt = session.endsAt else { return session }
      return try replaceSession(
        with: endsAt.addingTimeInterval(seconds), screen: session.screen, startedAt: session.startedAt)
    }
  }

  func stop() {
    lock.withLock {
      if let session = load() {
        caffeinate.terminate(session.pid)
      }
      try? FileManager.default.removeItem(at: stateURL)
    }
  }

  // MARK: - Called with the lock held

  private func activeSession() -> KeepAwakeSession? {
    guard let session = load() else { return nil }
    let notExpired = session.endsAt.map { $0 > now() } ?? true
    if notExpired, caffeinate.isRunning(session.pid) {
      return session
    }
    try? FileManager.default.removeItem(at: stateURL)
    return nil
  }

  /// Starts the new caffeinate before stopping the old one, so the Mac is never left able to sleep.
  private func replaceSession(with endsAt: Date?, screen: ScreenMode, startedAt: Date) throws
    -> KeepAwakeSession
  {
    let previous = load()
    var arguments = screen.caffeinateArguments
    if let endsAt {
      let seconds = max(1, endsAt.timeIntervalSince(now()).rounded(.up))
      arguments += ["-t", String(Int(seconds))]
    }
    let pid = try caffeinate.launch(arguments)
    let session = KeepAwakeSession(pid: pid, startedAt: startedAt, endsAt: endsAt, screen: screen)
    do {
      try save(session)
    } catch {
      caffeinate.terminate(pid)
      throw error
    }
    // An old session that already ended may have freed the very pid the new one got.
    if let previous, previous.pid != pid {
      caffeinate.terminate(previous.pid)
    }
    return session
  }

  private func load() -> KeepAwakeSession? {
    guard let data = try? Data(contentsOf: stateURL) else { return nil }
    return try? JSONDecoder().decode(KeepAwakeSession.self, from: data)
  }

  private func save(_ session: KeepAwakeSession) throws {
    try FileManager.default.createDirectory(
      at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(session).write(to: stateURL, options: .atomic)
  }
}
