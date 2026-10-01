//
//  PackageManager.swift
//  Lazarus
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

class PackageManager {

    // MARK: - Package Download and Installation

    func fetchPackageInfo(config: LazarusConfig) -> PackageInfo? {
        return downloadPackageInfo(config: config)
    }

    func downloadAndInstallLatestAgent(config: LazarusConfig, packageInfo: PackageInfo? = nil) -> Bool {
        Logger.shared.info("Starting download of latest MacPatch installer")

        let pkgInfo: PackageInfo
        if let info = packageInfo {
            pkgInfo = info
        } else {
            guard let info = downloadPackageInfo(config: config) else {
                Logger.shared.error("Failed to download or parse package info plist")
                return false
            }
            pkgInfo = info
        }

        let packageInfo = pkgInfo

        Logger.shared.info("Found package: \(packageInfo.name), version: \(packageInfo.version)")

        if let currentVersion = getCurrentAgentVersion() {
            Logger.shared.info("Current agent version: \(currentVersion)")

            let comparison = VersionComparator.compare(packageInfo.version, currentVersion)
            if comparison < 0 {
                Logger.shared.error("Package version (\(packageInfo.version)) is older than current version (\(currentVersion)). Skipping installation.")
                return false
            } else if comparison == 0 {
                Logger.shared.info("Package version (\(packageInfo.version)) matches current version. Installing anyway to repair.")
            } else {
                Logger.shared.info("Package version (\(packageInfo.version)) is newer than current version (\(currentVersion)). Proceeding with installation.")
            }
        } else {
            Logger.shared.info("Could not determine current version, proceeding with installation")
        }

        let packageURL = Constants.URLs.packageURL(server: config.mpServer, packageName: packageInfo.name)

        guard let packagePath = downloadPackage(urlString: packageURL, packageName: packageInfo.name, config: config) else {
            Logger.shared.error("Failed to download package")
            return false
        }

        guard verifyPackageHash(path: packagePath, expectedHash: packageInfo.hash) else {
            Logger.shared.error("Package hash verification failed")
            try? FileManager.default.removeItem(atPath: packagePath)
            return false
        }

        Logger.shared.info("Package hash verified successfully")

        let success = installPackage(path: packagePath)

        try? FileManager.default.removeItem(atPath: packagePath)

        return success
    }

    // MARK: - Private Methods

    private func downloadPackageInfo(config: LazarusConfig) -> PackageInfo? {
        let urlString = Constants.URLs.packageInfoPlist(server: config.mpServer)

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid plist URL: \(urlString)")
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.Timeouts.plistDownload

        let semaphore = DispatchSemaphore(value: 0)
        var packageInfo: PackageInfo?

        let session = createSession(config: config)

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                Logger.shared.error("Plist download failed: \(error.localizedDescription)")
                return
            }

            // Check HTTP response status
            if let httpResponse = response as? HTTPURLResponse {
                Logger.shared.info("HTTP Status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    Logger.shared.error("Server returned HTTP \(httpResponse.statusCode)")
                    if let data = data, let responseText = String(data: data, encoding: .utf8) {
                        Logger.shared.error("Response body: \(responseText.prefix(500))")
                    }
                    return
                }
            }

            guard let data = data else {
                Logger.shared.error("No data received from plist endpoint")
                return
            }

            do {
                if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let packages = plist[Constants.PackageInfoKeys.packageArray] as? [[String: Any]],
                   let firstPackage = packages.first,
                   let name = firstPackage[Constants.PackageInfoKeys.name] as? String,
                   let version = firstPackage[Constants.PackageInfoKeys.version] as? String,
                   let hash = firstPackage[Constants.PackageInfoKeys.hash] as? String {

                    let minVersion = firstPackage[Constants.PackageInfoKeys.minVersion] as? String

                    packageInfo = PackageInfo(name: name, version: version, hash: hash, minVersion: minVersion)
                    Logger.shared.info("Parsed package info from plist")

                    if let minVer = minVersion {
                        Logger.shared.info("Server-provided minimum version: \(minVer)")
                    }
                } else {
                    Logger.shared.error("Invalid plist format - missing required keys")
                    Logger.shared.error("Expected structure: Package array with MacPatch, Version, and PkgHash keys")
                }
            } catch {
                Logger.shared.error("Failed to parse plist: \(error.localizedDescription)")
            }
        }

        task.resume()
        semaphore.wait()

        return packageInfo
    }

    private func downloadPackage(urlString: String, packageName: String, config: LazarusConfig) -> String? {
        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid package URL: \(urlString)")
            return nil
        }

        let packagePath = "\(Constants.Paths.tmpDir)/\(packageName)"

        let semaphore = DispatchSemaphore(value: 0)
        var resultPath: String?

        let session = createSession(config: config)

        Logger.shared.info("Downloading package from: \(urlString)")

        let task = session.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }

            if let error = error {
                Logger.shared.error("Package download failed: \(error.localizedDescription)")
                return
            }

            guard let tempURL = tempURL else {
                Logger.shared.error("No temporary file URL")
                return
            }

            do {
                if FileManager.default.fileExists(atPath: packagePath) {
                    try FileManager.default.removeItem(atPath: packagePath)
                }

                try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: packagePath))
                Logger.shared.info("Package downloaded to: \(packagePath)")
                resultPath = packagePath

            } catch {
                Logger.shared.error("Failed to save package: \(error.localizedDescription)")
            }
        }

        task.resume()
        semaphore.wait()

        return resultPath
    }

    private func verifyPackageHash(path: String, expectedHash: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            Logger.shared.error("Failed to read package file for hash verification")
            return false
        }

        let actualHash = data.sha256Hash()

        Logger.shared.info("Expected SHA-256: \(expectedHash)")
        Logger.shared.info("Actual SHA-256:   \(actualHash)")

        if actualHash.lowercased() == expectedHash.lowercased() {
            return true
        } else {
            Logger.shared.error("SHA-256 hash mismatch! Package may be corrupted or tampered with.")
            return false
        }
    }

    private func installPackage(path: String) -> Bool {
        Logger.shared.info("Installing package: \(path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Constants.Paths.installerBinary)
        process.arguments = ["-pkg", path, "-target", Constants.Paths.installTarget]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                Logger.shared.info("Installer output: \(output)")

                // Check if installation failed because software is already installed
                if process.terminationStatus != 0 && output.contains("already installed") {
                    Logger.shared.warning("Installation blocked - software already installed. Running uninstall first...")

                    if uninstallMacPatch() {
                        Logger.shared.info("Uninstall successful, retrying installation...")
                        return retryInstallation(path: path)
                    } else {
                        Logger.shared.error("Uninstall failed, cannot proceed with installation")
                        return false
                    }
                }
            }

            if process.terminationStatus == 0 {
                Logger.shared.info("Package installed successfully")
                return true
            } else {
                Logger.shared.error("Package installation failed with exit code: \(process.terminationStatus)")
                return false
            }
        } catch {
            Logger.shared.error("Failed to run installer: \(error.localizedDescription)")
            return false
        }
    }

    private func uninstallMacPatch() -> Bool {
        let uninstallPath = Constants.Paths.uninstallScript

        guard FileManager.default.fileExists(atPath: uninstallPath) else {
            Logger.shared.error("Uninstall script not found at: \(uninstallPath)")
            return false
        }

        Logger.shared.info("Running uninstall script: \(uninstallPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [uninstallPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                Logger.shared.info("Uninstall output: \(output)")
            }

            if process.terminationStatus == 0 {
                Logger.shared.info("MacPatch uninstalled successfully")
                return true
            } else {
                Logger.shared.error("Uninstall failed with exit code: \(process.terminationStatus)")
                return false
            }
        } catch {
            Logger.shared.error("Failed to run uninstall script: \(error.localizedDescription)")
            return false
        }
    }

    private func retryInstallation(path: String) -> Bool {
        Logger.shared.info("Retrying package installation: \(path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Constants.Paths.installerBinary)
        process.arguments = ["-pkg", path, "-target", Constants.Paths.installTarget]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                Logger.shared.info("Retry installer output: \(output)")
            }

            if process.terminationStatus == 0 {
                Logger.shared.info("Package installed successfully on retry")
                return true
            } else {
                Logger.shared.error("Package installation retry failed with exit code: \(process.terminationStatus)")
                return false
            }
        } catch {
            Logger.shared.error("Failed to retry installation: \(error.localizedDescription)")
            return false
        }
    }

    private func getCurrentAgentVersion() -> String? {
        let versionPath = Constants.Paths.versionPlist

        guard FileManager.default.fileExists(atPath: versionPath),
              let plistData = FileManager.default.contents(atPath: versionPath),
              let versionPlist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let version = versionPlist[Constants.AgentVersionKeys.version] as? String,
              let build = versionPlist[Constants.AgentVersionKeys.build] as? String else {
            return nil
        }

        return "\(version).\(build)"
    }

    private func createSession(config: LazarusConfig) -> URLSession {
        if config.ignoreSSL {
            let delegate = SSLDelegate()
            return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            return URLSession.shared
        }
    }
}

// MARK: - Version Comparison

struct VersionComparator {
    static func compare(_ version1: String, _ version2: String) -> Int {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(v1Components.count, v2Components.count)

        for i in 0..<maxLength {
            let v1Value = i < v1Components.count ? v1Components[i] : 0
            let v2Value = i < v2Components.count ? v2Components[i] : 0

            if v1Value > v2Value {
                return 1
            } else if v1Value < v2Value {
                return -1
            }
        }

        return 0
    }
}
