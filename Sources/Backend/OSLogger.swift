import os.log

public class OSLogger: LoggerBackend, @unchecked Sendable {
  let logger: os.Logger

  public init(subsystem: String, category: String) {
    logger = os.Logger(subsystem: subsystem, category: category)
  }

  public func log(_ message: LogMessage) {
    let osLogType: OSLogType

    switch message.level {
    case .error:
      osLogType = .error
    case .warning:
      osLogType = .default
    case .info:
      osLogType = .info
    case .debug:
      osLogType = .debug
    }

    logger.log(level: osLogType, "\(message.message)")
  }
}
