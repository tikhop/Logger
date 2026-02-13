import Foundation

public class DefaultLogger: Logger, @unchecked Sendable {
  private let fileLogger: FileLogger
  private let osLogger: OSLogger

  init(subsystem: LogSubsystem) {
    var config = FileLoggerConfiguration.default
    config.maximumNumberOfLogFiles = 3
    config.maximumFileAge = 60 * 60 * 24  // 24 hours

    fileLogger = FileLogger(configuration: config)
    osLogger = OSLogger(subsystem: subsystem.identifier, category: subsystem.category)
  }

  public func log(
    _ message: String,
    level: LogLevel = .debug,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) {
    let logMessage = LogMessage(
      level: level,
      message: message,
      file: file,
      function: function,
      line: line
    )

    osLogger.log(logMessage)
    fileLogger.log(logMessage)
  }

  public var logFileURLs: [URL] {
    fileLogger.retrieveAllLogFiles().map { $0.url }
  }
}
