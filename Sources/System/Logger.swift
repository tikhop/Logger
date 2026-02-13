import Foundation

// MARK: - LogMessage

public struct LogMessage {
    public let level: LogLevel
    public let message: String
    public let timestamp: Date
    public let file: String
    public let function: String
    public let line: Int

    public init(
        level: LogLevel,
        message: String,
        timestamp: Date = Date(),
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        self.level = level
        self.message = message
        self.timestamp = timestamp
        self.file = file
        self.function = function
        self.line = line
    }
}

// MARK: - LoggerBackend

public protocol LoggerBackend: Sendable {
    func log(_ message: LogMessage)
}

// MARK: - Logger

public protocol Logger: Sendable {
    func log(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    )
}

// MARK: - LogMessageFormatter

public protocol LogMessageFormatter: Sendable {
    func formatMessage(_ logMessage: LogMessage) -> String
}

// MARK: - Default Log Formatter

private let kDateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    return dateFormatter
}()

// MARK: - DefaultLogMessageFormatter

public struct DefaultLogMessageFormatter: LogMessageFormatter {
    public init() {}

    public func formatMessage(_ logMessage: LogMessage) -> String {
        let timestamp = kDateFormatter.string(from: logMessage.timestamp)
        let fileName = URL(fileURLWithPath: logMessage.file).lastPathComponent
        let thread =
            Thread.isMainThread ? "main" : Thread.current.name ?? "thread-\(Thread.current.hash)"

        return
            "\(timestamp) [\(logMessage.level.stringValue)] [\(thread)] \(fileName):\(logMessage.line) - \(logMessage.function) > \(logMessage.message)"
    }
}
