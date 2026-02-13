import Foundation

public struct LogSubsystem: Sendable {
    public let identifier: String
    public let category: String

    public init(identifier: String, category: String) {
        self.identifier = identifier
        self.category = category
    }
}
