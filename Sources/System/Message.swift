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
