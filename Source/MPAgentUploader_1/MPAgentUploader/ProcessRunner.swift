//
//  ProcessRunner.swift
//  MPAgentUploder
//
//  Native Process replacement for SwiftShell
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

// MARK: - Errors

/// Errors that can occur during process execution
public enum ProcessError: Error, LocalizedError {
    case couldNotLaunch(String)
    case terminatedAbnormally(Int32)
    case outputError(String)
    
    public var errorDescription: String? {
        switch self {
        case .couldNotLaunch(let reason):
            return "Could not launch process: \(reason)"
        case .terminatedAbnormally(let code):
            return "Process terminated abnormally with exit code: \(code)"
        case .outputError(let reason):
            return "Output error: \(reason)"
        }
    }
}

// MARK: - Output Closure

/// Closure type for receiving output from a process
public typealias OutputClosure = (String) -> Void

// MARK: - ProcessRunner

/// Native Swift Process-based command runner
/// Replaces SwiftShell's Spawn functionality with native Foundation APIs
public final class ProcessRunner {
    
    // MARK: - Properties
    
    /// The process being executed
    private let process: Process
    
    /// The arguments to execute
    private let args: [String]
    
    /// Closure to receive output
    private let outputClosure: OutputClosure?
    
    /// Pipe for capturing stdout
    private let outputPipe = Pipe()
    
    /// Pipe for capturing stderr
    private let errorPipe = Pipe()
    
    /// Queue for reading output
    private let outputQueue = DispatchQueue(label: "com.macpatch.processrunner.output", qos: .userInitiated)
    
    /// Accumulated output
    private var accumulatedOutput = ""
    
    // MARK: - Initialization
    
    /// Initialize and run a process with the given arguments
    /// - Parameters:
    ///   - args: Array of arguments where first element is the executable path
    ///   - output: Optional closure to receive output line by line
    /// - Throws: ProcessError if the process cannot be launched
    public init(args: [String], output: OutputClosure? = nil) throws {
        guard !args.isEmpty else {
            throw ProcessError.couldNotLaunch("No arguments provided")
        }
        
        self.args = args
        self.outputClosure = output
        self.process = Process()
        
        // Configure process
        process.executableURL = URL(fileURLWithPath: args[0])
        if args.count > 1 {
            process.arguments = Array(args.dropFirst())
        }
        
        // Set up pipes
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Set up output handling
        setupOutputHandling()
        
        // Launch the process
        do {
            try process.run()
        } catch {
            throw ProcessError.couldNotLaunch(error.localizedDescription)
        }
        
        // Wait for completion
        process.waitUntilExit()
        
        // Check exit status
        let exitCode = process.terminationStatus
        if exitCode != 0 && process.terminationReason == .exit {
            // Note: We don't throw here because some commands may return non-zero
            // but still be considered successful by the caller
            // Let the caller decide based on output
        } else if process.terminationReason == .uncaughtSignal {
            throw ProcessError.terminatedAbnormally(exitCode)
        }
    }
    
    // MARK: - Private Methods
    
    /// Set up asynchronous output handling
    private func setupOutputHandling() {
        // Handle stdout
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            
            if let output = String(data: data, encoding: .utf8) {
                self.outputQueue.async {
                    self.accumulatedOutput += output
                    self.outputClosure?(output)
                }
            }
        }
        
        // Handle stderr
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            
            if let output = String(data: data, encoding: .utf8) {
                self.outputQueue.async {
                    self.accumulatedOutput += output
                    self.outputClosure?(output)
                }
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Get the exit code of the completed process
    public var exitCode: Int32 {
        return process.terminationStatus
    }
    
    /// Get the termination reason
    public var terminationReason: Process.TerminationReason {
        return process.terminationReason
    }
    
    /// Check if the process completed successfully
    public var isSuccess: Bool {
        return process.terminationStatus == 0 && process.terminationReason == .exit
    }
    
    /// Get all accumulated output
    public var output: String {
        return accumulatedOutput
    }
}

// MARK: - Convenience Functions

/// Run a shell command and return the result
/// - Parameters:
///   - command: The shell command to run
///   - arguments: Arguments to pass to the command
///   - output: Optional closure to receive output
/// - Returns: The exit code
/// - Throws: ProcessError if execution fails
@discardableResult
public func runCommand(
    _ command: String,
    arguments: [String] = [],
    output: OutputClosure? = nil
) throws -> Int32 {
    var args = [command]
    args.append(contentsOf: arguments)
    let runner = try ProcessRunner(args: args, output: output)
    return runner.exitCode
}

/// Run a shell command and capture output
/// - Parameters:
///   - command: The shell command to run
///   - arguments: Arguments to pass to the command
/// - Returns: Tuple containing exit code and output string
/// - Throws: ProcessError if execution fails
public func runCommandWithOutput(
    _ command: String,
    arguments: [String] = []
) throws -> (exitCode: Int32, output: String) {
    var capturedOutput = ""
    let args = [command] + arguments
    let runner = try ProcessRunner(args: args) { output in
        capturedOutput += output
    }
    return (runner.exitCode, capturedOutput)
}

// MARK: - Spawn Compatibility Alias

/// Compatibility alias for SwiftShell's Spawn class
/// Provides drop-in replacement with the same API
public typealias Spawn = ProcessRunner

// MARK: - Extensions for Common Tasks

extension ProcessRunner {
    
    /// Run a shell script
    /// - Parameters:
    ///   - script: The script content to run
    ///   - output: Optional closure to receive output
    /// - Returns: ProcessRunner instance
    /// - Throws: ProcessError if execution fails
    public static func runScript(_ script: String, output: OutputClosure? = nil) throws -> ProcessRunner {
        return try ProcessRunner(args: ["/bin/sh", "-c", script], output: output)
    }
    
    /// Run a bash command
    /// - Parameters:
    ///   - command: The bash command to run
    ///   - output: Optional closure to receive output
    /// - Returns: ProcessRunner instance
    /// - Throws: ProcessError if execution fails
    public static func runBash(_ command: String, output: OutputClosure? = nil) throws -> ProcessRunner {
        return try ProcessRunner(args: ["/bin/bash", "-c", command], output: output)
    }
    
    /// Check if a command exists in the system
    /// - Parameter command: The command name to check
    /// - Returns: true if the command exists, false otherwise
    public static func commandExists(_ command: String) -> Bool {
        do {
            let runner = try ProcessRunner(args: ["/usr/bin/which", command])
            return runner.isSuccess
        } catch {
            return false
        }
    }
    
    /// Get the path to a command
    /// - Parameter command: The command name
    /// - Returns: The full path to the command, or nil if not found
    public static func which(_ command: String) -> String? {
        do {
            var output = ""
            let runner = try ProcessRunner(args: ["/usr/bin/which", command]) { output += $0 }
            if runner.isSuccess {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}
        return nil
    }
}

// MARK: - Async/Await Support (for modern Swift)

#if swift(>=5.5)
@available(macOS 12.0, *)
extension ProcessRunner {
    
    /// Run a process asynchronously using Swift Concurrency
    /// - Parameters:
    ///   - args: Array of arguments where first element is the executable path
    ///   - streamOutput: Whether to stream output as it's received
    /// - Returns: Tuple containing exit code and full output
    public static func runAsync(
        args: [String],
        streamOutput: Bool = false
    ) async throws -> (exitCode: Int32, output: String) {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                var capturedOutput = ""
                let runner = try ProcessRunner(args: args) { output in
                    capturedOutput += output
                    if streamOutput {
                        print(output, terminator: "")
                    }
                }
                continuation.resume(returning: (runner.exitCode, capturedOutput))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
