//
//  AppLogger.swift
//  MPAgentUploder
//
//  Native OSLog replacement for LogKit
//
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.
 
 This file is part of MacPatch, a program for installing and patching
 software.
 
 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.
 
 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.
 
 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

import Foundation
import os.log

/// Native OSLog-based logger that replaces LogKit
/// Provides file logging with rotation and console logging via OSLog
public final class AppLogger {
    
    // MARK: - Properties
    
    /// The OSLog instance for console logging
    private let osLog: OSLog
    
    /// File logging configuration
    private let fileURL: URL
    private let maxFileSize: Int
    private let numberOfFiles: Int
    
    /// Current log level (for filtering)
    private var minimumLevel: LogLevel
    
    /// Date formatter for log entries
    private let dateFormatter: DateFormatter
    
    /// Queue for thread-safe file operations
    private let fileQueue = DispatchQueue(label: "gov.llnl.mp.agentuploader.logger", qos: .background)
    
    // MARK: - Log Levels
    
    public enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case notice = 2
        case warning = 3
        case error = 4
        case critical = 5
        
        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .notice: return .default
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
        
        var description: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .notice: return "NOTICE"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            case .critical: return "CRITICAL"
            }
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize logger with file rotation support
    /// - Parameters:
    ///   - subsystem: Bundle identifier for OSLog
    ///   - category: Category name for OSLog
    ///   - fileURL: Base URL for log files
    ///   - numberOfFiles: Number of log files to keep in rotation (default: 7)
    ///   - maxFileSizeKB: Maximum file size in KB before rotation (default: 10MB)
    ///   - minimumLevel: Minimum log level to record (default: .info)
    public init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.macpatch",
        category: String = "AgentUploader",
        fileURL: URL,
        numberOfFiles: Int = 7,
        maxFileSizeKB: Int = 10 * 1024,
        minimumLevel: LogLevel = .info
    ) {
        self.osLog = OSLog(subsystem: subsystem, category: category)
        self.fileURL = fileURL
        self.numberOfFiles = numberOfFiles
        self.maxFileSize = maxFileSizeKB * 1024 // Convert to bytes
        self.minimumLevel = minimumLevel
        
        // Configure date formatter
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.dateFormatter.locale = Locale.current
        self.dateFormatter.timeZone = TimeZone.current
        
        // Create log directory if needed
        createLogDirectoryIfNeeded()
    }
    
    /// Convenience initializer for default console-only logging
    public convenience init() {
        let fileURL = URL(fileURLWithPath: logPath)
        self.init(fileURL: fileURL)
    }
    
    // MARK: - Public Logging Methods
    
    /// Log a debug message
    public func debug(
        _ message: @autoclosure () -> String,
        functionName: String = #function,
        filePath: String = #file,
        lineNumber: Int = #line
    ) {
        log(message(), level: .debug, functionName: functionName, filePath: filePath, lineNumber: lineNumber)
    }
    
    /// Log an info message
    public func info(
        _ message: @autoclosure () -> String,
        functionName: String = #function,
        filePath: String = #file,
        lineNumber: Int = #line
    ) {
        log(message(), level: .info, functionName: functionName, filePath: filePath, lineNumber: lineNumber)
    }
    
    /// Log a notice message
    public func notice(
        _ message: @autoclosure () -> String,
        functionName: String = #function,
        filePath: String = #file,
        lineNumber: Int = #line
    ) {
        log(message(), level: .notice, functionName: functionName, filePath: filePath, lineNumber: lineNumber)
    }
    
    /// Log a warning message
    public func warning(
        _ message: @autoclosure () -> String,
        functionName: String = #function,
        filePath: String = #file,
        lineNumber: Int = #line
    ) {
        log(message(), level: .warning, functionName: functionName, filePath: filePath, lineNumber: lineNumber)
    }
    
    /// Log an error message
    public func error(
        _ message: @autoclosure () -> String,
        functionName: String = #function,
        filePath: String = #file,
        lineNumber: Int = #line
    ) {
        log(message(), level: .error, functionName: functionName, filePath: filePath, lineNumber: lineNumber)
    }
    
    /// Log a critical message
    public func critical(
        _ message: @autoclosure () -> String,
        functionName: String = #function,
        filePath: String = #file,
        lineNumber: Int = #line
    ) {
        log(message(), level: .critical, functionName: functionName, filePath: filePath, lineNumber: lineNumber)
    }
    
    // MARK: - Configuration
    
    /// Update the minimum log level
    public func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }
    
    // MARK: - Private Methods
    
    private func log(
        _ message: String,
        level: LogLevel,
        functionName: String,
        filePath: String,
        lineNumber: Int
    ) {
        // Filter by log level
        guard level >= minimumLevel else { return }
        
        let fileName = (filePath as NSString).lastPathComponent
        
        // Log to OSLog (Console.app)
        os_log(
            "%{public}@ [%{public}@] %{public}@:%{public}d --- %{public}@",
            log: osLog,
            type: level.osLogType,
            level.description,
            fileName,
            functionName,
            lineNumber,
            message
        )
        
        // Log to file
        logToFile(message: message, level: level, fileName: fileName, functionName: functionName, lineNumber: lineNumber)
    }
    
    private func logToFile(
        message: String,
        level: LogLevel,
        fileName: String,
        functionName: String,
        lineNumber: Int
    ) {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry = "\(timestamp) [\(level.description)] [\(fileName)] \(functionName):\(lineNumber) --- \(message)\n"
            
            guard let data = logEntry.data(using: .utf8) else { return }
            
            // Check if rotation is needed
            self.rotateLogFilesIfNeeded()
            
            // Append to current log file
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: self.fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }
    
    private func createLogDirectoryIfNeeded() {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func rotateLogFilesIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        // Check file size
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int,
              fileSize >= maxFileSize else {
            return
        }
        
        // Perform rotation
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        
        // Remove oldest file if exists
        let oldestFile = directory.appendingPathComponent("\(numberOfFiles)_\(baseName).\(ext)")
        try? fileManager.removeItem(at: oldestFile)
        
        // Rotate existing files
        for i in (1..<numberOfFiles).reversed() {
            let currentFile = directory.appendingPathComponent("\(i)_\(baseName).\(ext)")
            let nextFile = directory.appendingPathComponent("\(i + 1)_\(baseName).\(ext)")
            
            if fileManager.fileExists(atPath: currentFile.path) {
                try? fileManager.moveItem(at: currentFile, to: nextFile)
            }
        }
        
        // Move current file to 1_
        let firstRotatedFile = directory.appendingPathComponent("1_\(baseName).\(ext)")
        try? fileManager.moveItem(at: fileURL, to: firstRotatedFile)
    }
    
    // MARK: - Log File Access
    
    /// Get the current log file URL
    public func currentLogFileURL() -> URL {
        return fileURL
    }
    
    /// Get all rotated log file URLs
    public func allLogFileURLs() -> [URL] {
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        
        var urls = [fileURL]
        
        for i in 1...numberOfFiles {
            let rotatedFile = directory.appendingPathComponent("\(i)_\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: rotatedFile.path) {
                urls.append(rotatedFile)
            }
        }
        
        return urls
    }
}
