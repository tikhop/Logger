import Foundation

public enum LogLevel: Int, Comparable, Sendable {
  case debug = 0
  case info = 1
  case warning = 2
  case error = 3

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  var stringValue: String {
    switch self {
    case .debug: "DEBUG"
    case .info: "INFO"
    case .warning: "WARN"
    case .error: "ERROR"
    }
  }
}
