//
//  Notarizer.swift
//  MPAgentUploader
//
//  Created by Charles Heizer on 3/6/26.
//  Copyright © 2026 Lawrence Livermore Nat'l Lab. All rights reserved.
//
import Foundation

enum NotarizationError: Error {
    case notarizationFailed(String)
    case invalidArguments
}

class KeychainNotarizer {
    let credentialName: String
    
    init(credentialName: String) {
        self.credentialName = credentialName
    }
    
    func notarizePackage(at package: String) async throws {
        let cliArgs = [
            "/usr/bin/xcrun", "notarytool", "submit", package,
            "--keychain-profile", credentialName,
            "--wait"
        ]
        
        let output = try await runProcess(with: cliArgs)
        log.info(output)
        
        if output.contains("status: Accepted") {
            log.info("✓ Package successfully notarized!")
        } else {
            throw NotarizationError.notarizationFailed("Check output for details")
        }
    }
    
    func staplePackage(at package: String) async throws {
        let cliArgs = ["/usr/bin/xcrun", "stapler", "staple", package]
        
        let output = try await runProcess(with: cliArgs)
        log.info(output)
        
        if output.contains("action worked") {
            log.info("✓ Package successfully stapled!")
        } else {
            throw NotarizationError.notarizationFailed("Check output for details")
        }
    }
    
    
    
    private func runProcess(with arguments: [String]) async throws -> String {
        guard let executable = arguments.first else {
            throw NotarizationError.invalidArguments
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let combined = output + error
                continuation.resume(returning: combined)
            }
        }
    }
}

// Usage:
// First run in terminal:
// xcrun notarytool store-credentials "my-profile" --apple-id "email@example.com" --team-id "ABC1234567"

// Then in Swift:
// let notarizer = KeychainNotarizer(credentialName: "my-profile")
// try await notarizer.notarizePackage(at: "/path/to/App.dmg")
