import Foundation

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
