// MARK: - LoggerBackend

public protocol LoggerBackend: Sendable {
    func log(_ message: LogMessage)
}
