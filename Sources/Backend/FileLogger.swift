import Foundation
import os.log

// MARK: - FileLoggerConfiguration

public struct FileLoggerConfiguration: Sendable {
    public var logDirectory: URL
    public var fileNamePrefix: String
    public var maximumFileSize: Int64  // in bytes
    public var maximumFileAge: TimeInterval  // in seconds
    public var maximumNumberOfLogFiles: Int
    public var minimumLogLevel: LogLevel
    public var shouldUseMultiProcessLocking: Bool

    public static var `default`: FileLoggerConfiguration {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let logsDirectory = documentsPath.appendingPathComponent("Logs")

        return FileLoggerConfiguration(
            logDirectory: logsDirectory,
            fileNamePrefix: "app",
            maximumFileSize: 1024 * 1024,  // 1 MB
            maximumFileAge: 24 * 60 * 60,  // 24 hours
            maximumNumberOfLogFiles: 5,
            minimumLogLevel: .debug,
            shouldUseMultiProcessLocking: true
        )
    }

    public init(
        logDirectory: URL,
        fileNamePrefix: String = "app",
        maximumFileSize: Int64 = 1024 * 1024,
        maximumFileAge: TimeInterval = 24 * 60 * 60,
        maximumNumberOfLogFiles: Int = 5,
        minimumLogLevel: LogLevel = .debug,
        shouldUseMultiProcessLocking: Bool = true
    ) {
        self.logDirectory = logDirectory
        self.fileNamePrefix = fileNamePrefix
        self.maximumFileSize = maximumFileSize
        self.maximumFileAge = maximumFileAge
        self.maximumNumberOfLogFiles = maximumNumberOfLogFiles
        self.minimumLogLevel = minimumLogLevel
        self.shouldUseMultiProcessLocking = shouldUseMultiProcessLocking
    }
}

// MARK: - LogFileInfo

public struct LogFileInfo {
    public let url: URL
    public let creationDate: Date
    public let modificationDate: Date
    public let fileSize: Int64
    public let isArchived: Bool

    public var age: TimeInterval {
        Date().timeIntervalSince(creationDate)
    }

    public var fileName: String {
        url.lastPathComponent
    }
}

// MARK: - FileLogger

private let fileOperationQueue = DispatchQueue(label: "dev.bonzer.filelogger")

public final class FileLogger: LoggerBackend, @unchecked Sendable {
    // MARK: - Properties

    private let configuration: FileLoggerConfiguration
    private let formatter: LogMessageFormatter
    private var fileManager: FileManager { FileManager.default }

    private var currentFileHandle: FileHandle?
    private var currentFileURL: URL?
    private var currentFileSize: Int64 = 0

    private var fileMonitoringSource: DispatchSourceFileSystemObject?

    // MARK: - Initialization

    public init(
        configuration: FileLoggerConfiguration = .default,
        formatter: LogMessageFormatter = DefaultLogMessageFormatter()
    ) {
        self.configuration = configuration
        self.formatter = formatter

        ensureLogDirectoryExists()

        fileOperationQueue.async { [weak self] in
            self?.openOrCreateLogFile()
        }
    }

    deinit {
        fileMonitoringSource?.cancel()

        fileOperationQueue.sync {
            closeCurrentFile()
        }
    }

    // MARK: - Public Methods

    public func log(_ message: LogMessage) {
        guard message.level >= configuration.minimumLogLevel else { return }

        let formattedMessage = formatter.formatMessage(message) + "\n"

        fileOperationQueue.async { [weak self] in
            self?.writeMessageToFile(formattedMessage)
        }
    }

    public func synchronize() {
        fileOperationQueue.sync {
            currentFileHandle?.synchronizeFile()
        }
    }

    public func rotateLogFile() {
        fileOperationQueue.async { [weak self] in
            self?.performFileRotation()
        }
    }

    public func retrieveAllLogFiles() -> [LogFileInfo] {
        fileOperationQueue.sync {
            findAllLogFiles()
        }
    }

    public static func retrieveAllLogFilesFromDefaultLocation() -> [LogFileInfo] {
        fileOperationQueue.sync {
            findAllLogFiles(for: FileLoggerConfiguration.default)
        }
    }

    public func purgeAllLogFiles() {
        fileOperationQueue.async { [weak self] in
            self?.deleteAllLogFiles()
        }
    }

    // MARK: - Private Methods - Directory Management

    private func ensureLogDirectoryExists() {
        if !fileManager.fileExists(atPath: configuration.logDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: configuration.logDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                os_log(.error, "Failed to create logs directory: %{public}@", error.localizedDescription)
            }
        }
    }

    // MARK: - Private Methods - File Management

    private func openOrCreateLogFile() {
        let existingFiles = findAllLogFiles().filter { !$0.isArchived }

        if let mostRecent = existingFiles.sorted(by: { $0.creationDate > $1.creationDate }).first,
            mostRecent.fileSize < configuration.maximumFileSize,
            mostRecent.age < configuration.maximumFileAge
        {
            openExistingLogFile(at: mostRecent.url, withSize: mostRecent.fileSize)
        } else {
            createNewLogFile()
        }
    }

    private func createNewLogFile() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "_")

        let fileName = "\(configuration.fileNamePrefix)_\(timestamp).log"
        let fileURL = configuration.logDirectory.appendingPathComponent(fileName)

        fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)

        openExistingLogFile(at: fileURL, withSize: 0)
    }

    private func openExistingLogFile(at url: URL, withSize size: Int64) {
        closeCurrentFile()

        do {
            currentFileHandle = try FileHandle(forWritingTo: url)
            currentFileURL = url
            currentFileSize = size

            if #available(iOS 13.4, macOS 10.15.4, *) {
                try currentFileHandle?.seekToEnd()
            } else {
                currentFileHandle?.seekToEndOfFile()
            }

            setupFileMonitoring(for: url)

        } catch {
            os_log(
                .error,
                "Failed to open log file at %{public}@: %{public}@",

                url.path,
                error.localizedDescription
            )
            currentFileHandle = nil
            currentFileURL = nil
        }
    }

    private func closeCurrentFile() {
        currentFileHandle?.closeFile()
        currentFileHandle = nil
        currentFileURL = nil
        currentFileSize = 0
    }

    // MARK: - Private Methods - Writing

    private func writeMessageToFile(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }

        guard let fileHandle = currentFileHandle else {
            openOrCreateLogFile()

            if let newHandle = currentFileHandle {
                writeDataToHandle(data, handle: newHandle)
            }
            return
        }

        writeDataToHandle(data, handle: fileHandle)
    }

    private func writeDataToHandle(_ data: Data, handle: FileHandle) {
        let fileDescriptor = handle.fileDescriptor

        do {
            if configuration.shouldUseMultiProcessLocking {
                let lockResult = flock(fileDescriptor, LOCK_EX)
                guard lockResult == 0 else {
                    flock(fileDescriptor, LOCK_UN)
                    os_log(.error, "Failed to acquire file lock: %{public}d", errno)
                    return
                }
            }

            if #available(iOS 13.4, macOS 10.15.4, *) {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                handle.seekToEndOfFile()
                handle.write(data)
            }

            currentFileSize += Int64(data.count)

            if shouldRotateFile() {
                performFileRotation()
            }

        } catch {
            os_log(.error, "Failed to write to log file: %{public}@", error.localizedDescription)

            closeCurrentFile()
            openOrCreateLogFile()
        }

        if configuration.shouldUseMultiProcessLocking {
            flock(fileDescriptor, LOCK_UN)
        }
    }

    // MARK: - Private Methods - Rotation

    private func shouldRotateFile() -> Bool {
        guard let url = currentFileURL else { return true }

        return currentFileSize >= configuration.maximumFileSize
            || calculateFileAge(url) >= configuration.maximumFileAge
    }

    private func performFileRotation() {
        if let url = currentFileURL {
            markFileAsArchived(url)
        }

        closeCurrentFile()
        createNewLogFile()
        cleanupOldLogFiles()
    }

    private func markFileAsArchived(_ url: URL) {
        do {
            try url.setExtendedAttribute(data: Data([1]), forName: "dev.bonzer.filelogger.archived")
        } catch {
            os_log(.error, "Failed to mark file as archived: %{public}@", error.localizedDescription)
        }
    }

    private func cleanupOldLogFiles() {
        let allFiles = findAllLogFiles().sorted { $0.creationDate < $1.creationDate }

        // Remove files exceeding maximum count
        if allFiles.count > configuration.maximumNumberOfLogFiles {
            let filesToDelete = allFiles.prefix(allFiles.count - configuration.maximumNumberOfLogFiles)

            for fileInfo in filesToDelete {
                do {
                    try fileManager.removeItem(at: fileInfo.url)
                    os_log(.info, "Deleted old log file: %{public}@", fileInfo.fileName)
                } catch {
                    os_log(.error, "Failed to delete log file: %{public}@", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Private Methods - File Discovery

    private func findAllLogFiles() -> [LogFileInfo] {
        Self.findAllLogFiles(for: configuration)
    }

    private static func findAllLogFiles(for configuration: FileLoggerConfiguration) -> [LogFileInfo] {
        let fileManager = FileManager.default

        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: configuration.logDirectory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
        else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension == "log",
                url.lastPathComponent.hasPrefix(configuration.fileNamePrefix)
            else {
                return nil
            }

            do {
                let attributes = try url.resourceValues(forKeys: [
                    .creationDateKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                ])

                let isArchived =
                    (try? url.extendedAttribute(forName: "dev.bonzer.filelogger.archived")) != nil

                return LogFileInfo(
                    url: url,
                    creationDate: attributes.creationDate ?? Date(),
                    modificationDate: attributes.contentModificationDate ?? Date(),
                    fileSize: Int64(attributes.fileSize ?? 0),
                    isArchived: isArchived
                )
            } catch {
                return nil
            }
        }
    }

    private func calculateFileAge(_ url: URL) -> TimeInterval {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let creationDate = attributes[.creationDate] as? Date {
                return Date().timeIntervalSince(creationDate)
            }
        } catch {
            os_log(.error, "Failed to get file age: %{public}@", error.localizedDescription)
        }

        return 0
    }

    private func deleteAllLogFiles() {
        let allFiles = findAllLogFiles()

        for fileInfo in allFiles {
            do {
                try fileManager.removeItem(at: fileInfo.url)
            } catch {
                os_log(.error, "Failed to delete log file: %{public}@", error.localizedDescription)
            }
        }

        // Reset and create new file
        closeCurrentFile()
        createNewLogFile()
    }

    // MARK: - Private Methods - File Monitoring

    private func setupFileMonitoring(for url: URL) {
        fileMonitoringSource?.cancel()

        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.delete, .rename],
            queue: fileOperationQueue
        )

        source.setEventHandler { [weak self] in
            self?.closeCurrentFile()
            self?.openOrCreateLogFile()
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()
        fileMonitoringSource = source
    }
}

// MARK: - URL Extension for Extended Attributes

extension URL {
    func extendedAttribute(forName name: String) throws -> Data? {
        let data = withUnsafeFileSystemRepresentation { fileSystemPath -> Data? in
            guard let fileSystemPath else { return nil }

            let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)
            guard length >= 0 else { return nil }

            var data = Data(count: length)
            let result = data.withUnsafeMutableBytes { buffer in
                getxattr(fileSystemPath, name, buffer.baseAddress, length, 0, 0)
            }

            guard result >= 0 else { return nil }
            return data
        }

        return data
    }

    func setExtendedAttribute(data: Data, forName name: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath else { return }

            let result = data.withUnsafeBytes { buffer in
                setxattr(fileSystemPath, name, buffer.baseAddress, data.count, 0, 0)
            }

            guard result >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            }
        }
    }
}
