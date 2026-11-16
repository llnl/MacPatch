//
//  HealthChecker.swift
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
import IOKit

class HealthChecker {

    // MARK: - Health Check Methods

    func hasAgent() -> Bool {
        return FileManager.default.fileExists(atPath: Constants.Paths.agentBinary)
    }

    func hasMinVersion(config: LazarusConfig) -> Bool {
        let versionPath = Constants.Paths.versionPlist

        guard FileManager.default.fileExists(atPath: versionPath),
              let plistData = FileManager.default.contents(atPath: versionPath),
              let versionPlist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let version = versionPlist["version"] as? String,
              let build = versionPlist["build"] as? String else {
            Logger.shared.error("Failed to read version plist")
            return false
        }

        let currentVersion = "\(version).\(build)"

        if VersionComparator.compare(config.minAgentVersion, currentVersion) > 0 {
            Logger.shared.warning("Failed Min Version, min=\(config.minAgentVersion), found=\(currentVersion)")
            return false
        }

        return true
    }

    func getClientID() -> String? {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(Constants.IOKit.platformExpertDevice))

        guard platformExpert != 0 else {
            return nil
        }

        defer {
            IOObjectRelease(platformExpert)
        }

        guard let uuid = IORegistryEntryCreateCFProperty(platformExpert, Constants.IOKit.platformUUID as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? String else {
            return nil
        }

        return uuid
    }

    func hasCheckedIn(clientID: String, config: LazarusConfig) -> Bool {
        let urlString = Constants.URLs.checkinURL(server: config.mpServer, clientID: clientID)

        guard let url = URL(string: urlString) else {
            Logger.shared.error("Invalid URL: \(urlString)")
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.Timeouts.networkRequest

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        let session = createSession(config: config)

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                Logger.shared.error("Checkin request failed: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                Logger.shared.error("No data received from checkin endpoint")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resultData = json[Constants.APIKeys.result] as? [String: Any],
                   let mdate = resultData[Constants.APIKeys.mdate] as? String {

                    let dateComponents = mdate.components(separatedBy: " ")
                    guard dateComponents.count > 0 else {
                        Logger.shared.error("Invalid date format: \(mdate)")
                        return
                    }

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = Constants.DateFormats.apiDate

                    guard let checkinDate = dateFormatter.date(from: dateComponents[0]) else {
                        Logger.shared.error("Failed to parse date: \(dateComponents[0])")
                        return
                    }

                    let now = Date()
                    let daysAgo = Calendar.current.date(byAdding: .day, value: -config.daysRange, to: now)!

                    if checkinDate >= daysAgo {
                        result = true
                    } else {
                        Logger.shared.warning("Failed Checkin, lastdate=\(mdate)")
                        Logger.shared.info("Today's date=\(dateFormatter.string(from: now))")
                    }
                }
            } catch {
                Logger.shared.error("Failed to parse JSON: \(error.localizedDescription)")
            }
        }

        task.resume()
        semaphore.wait()

        return result
    }

    func validAgentHash(config: LazarusConfig) -> Bool {
        // If hash is not defined in config, skip the check
        guard let expectedHash = config.mpHash else {
            return true
        }

        let agentPath = Constants.Paths.agentBinary

        guard FileManager.default.fileExists(atPath: agentPath),
              let data = FileManager.default.contents(atPath: agentPath) else {
            Logger.shared.error("Failed to read agent file")
            return false
        }

        let hash = data.sha256Hash()

        if hash.lowercased() == expectedHash.lowercased() {
            return true
        } else {
            Logger.shared.warning("Failed Agent Hash Check: expected=\(expectedHash), found=\(hash)")
            return false
        }
    }

    // MARK: - Private Methods

    private func createSession(config: LazarusConfig) -> URLSession {
        if config.ignoreSSL {
            let delegate = SSLDelegate()
            return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            return URLSession.shared
        }
    }
}
