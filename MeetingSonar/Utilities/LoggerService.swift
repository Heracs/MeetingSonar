//
//  LoggerService.swift
//  MeetingSonar
//
//  Structured logging service for MeetingSonar.
//  v0.1-rebuild: Core logging functionality.
//

import Foundation
import AppKit
import os.log

/// Log categories for structured logging
enum LogCategory: String {
    case general = "General"
    case audio = "Audio"
    case recording = "Recording"
    case permission = "Permission"
    case ui = "UI"
    case error = "Error"
    case detection = "Detection"
    case ai = "AI"           // v0.5.0: AI processing
    case system = "System"   // v0.5.0: System info
}

/// Log levels
enum LogLevel {
    case info
    case debug
    case warning
    case error
    
    var osLogType: OSLogType {
        switch self {
        case .info: return .info
        case .debug: return .debug
        case .warning: return .default
        case .error: return .error
        }
    }
}

/// Centralized logging service with file and console output.
class LoggerService {
    static let shared = LoggerService()
    
    // MARK: - Private Properties
    
    private let osLog: OSLog
    private var fileHandle: FileHandle?
    private var logFileURL: URL?
    private let dateFormatter: DateFormatter
    private let fileDateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.meetingsonar.logger", qos: .utility)
    
    private var currentLogDateString: String = ""
    private let maxLogAgeDays: Double = 7
    
    // MARK: - Initialization
    
    private init() {
        osLog = OSLog(subsystem: "com.meetingsonar.app", category: "MeetingSonar")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        
        setupLogFile()
        cleanOldLogs()
    }
    
    deinit {
        try? fileHandle?.close()
    }
    
    // MARK: - Private Methods
    
    private func setupLogFile() {
        let now = Date()
        let dateString = fileDateFormatter.string(from: now)
        
        // If already setup for today, do nothing
        if dateString == currentLogDateString && fileHandle != nil {
            return
        }
        
        // Close existing handle
        try? fileHandle?.close()
        fileHandle = nil
        
        currentLogDateString = dateString
        
        // v0.5.1: Use user-visible data directory instead of hidden Application Support
        let logsDir = PathManager.shared.logsURL
        
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            
            let logFileName = "MeetingSonar-\(dateString).log"
            let fileURL = logsDir.appendingPathComponent(logFileName)
            
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                // Initial header
                let header = "MeetingSonar Log Started: \(dateFormatter.string(from: now))\nVersion: \(BuildInfo.fullBuildString)\n----------------------------------------\n"
                try header.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle?.seekToEndOfFile()
            logFileURL = fileURL
            
            print("LoggerService: Log file set to \(fileURL.path)")
            
        } catch {
            print("LoggerService: Failed to setup log file: \(error)")
        }
    }
    
    private func cleanOldLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            // v0.5.1: Use PathManager for consistent log path
            let logsDir = PathManager.shared.logsURL
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                
                let thresholdDate = Date().addingTimeInterval(-1 * self.maxLogAgeDays * 24 * 3600)
                
                for url in fileURLs {
                    guard url.lastPathComponent.hasPrefix("MeetingSonar-") && url.pathExtension == "log" else { continue }
                    
                    if let resources = try? url.resourceValues(forKeys: [.creationDateKey]),
                       let creationDate = resources.creationDate,
                       creationDate < thresholdDate {
                        
                        try? FileManager.default.removeItem(at: url)
                        self.log(category: .general, message: "Cleaned old log file: \(url.lastPathComponent)")
                    }
                }
            } catch {
                print("LoggerService: Failed to clean old logs: \(error)")
            }
        }
    }
    
    private func checkRotation() {
        let now = Date()
        let dateString = fileDateFormatter.string(from: now)
        if dateString != currentLogDateString {
            setupLogFile()
        }
    }
    
    // MARK: - Public API
    
    /// Log a message with category (compatible with existing code)
    func log(category: LogCategory, message: String) {
        log(category: category, level: .info, message: message)
    }
    
    /// Log a message with category and level
    func log(category: LogCategory, level: LogLevel = .info, message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let levelStr = String(describing: level).uppercased()
        let formattedMessage = "[\(timestamp)] [\(levelStr)] [\(category.rawValue)] \(message)"
        
        // Console output
        os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
        
        // File output
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.checkRotation()
            
            guard let handle = self.fileHandle else { return }
            if let data = "\(formattedMessage)\n".data(using: .utf8) {
                // Handle exception if disk full etc? For now, basic write.
                try? handle.write(contentsOf: data) 
            }
        }
    }
    
    /// Log an error with optional Error object
    func logError(_ message: String, error: Error? = nil) {
        let errorDescription = error.map { ": \($0.localizedDescription)" } ?? ""
        log(category: .error, level: .error, message: "\(message)\(errorDescription)")
    }
    
    /// Log a metric event with attributes
    func logMetric(event: String, attributes: [String: Any]) {
        let attrString = attributes.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        log(category: .general, level: .info, message: "[METRIC] \(event) | \(attrString)")
    }
    
    /// Open log directory in Finder
    func openLogDirectory() {
        if let logsDir = logFileURL?.deletingLastPathComponent() {
            NSWorkspace.shared.open(logsDir)
        } else {
            // v0.5.1: Fallback to PathManager path
            NSWorkspace.shared.open(PathManager.shared.logsURL)
        }
    }
}

