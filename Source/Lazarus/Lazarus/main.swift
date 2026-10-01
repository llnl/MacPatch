//
//  main.swift
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

// MARK: - Main Entry Point

func performHealthChecks(dryRun: Bool = false, packageInfo: PackageInfo? = nil) -> Bool {
    Logger.shared.info("Running MacPatch Lazarus checks")

    var config = LazarusConfig.load()
    let healthChecker = HealthChecker()
    let packageManager = PackageManager()
    var failedChecks = 0
    var failureReasons: [String] = []

    // Override minimum version if server provides one
    if let serverMin = packageInfo?.minVersion {
        Logger.shared.info("Using server-provided minimum version: \(serverMin) (overriding local: \(config.minAgentVersion))")
        config.minAgentVersion = serverMin
    }

    // Agent existence check
    if !healthChecker.hasAgent() {
        Logger.shared.warning("Failed Agent Check")
        failedChecks += 1
        failureReasons.append("Agent binary not found at \(Constants.Paths.agentBinary)")
    }

    // Minimum version check
    if !healthChecker.hasMinVersion(config: config) {
        Logger.shared.warning("Failed Min Version")
        failedChecks += 1
        failureReasons.append("Agent version below minimum required (\(config.minAgentVersion))")
    }

    // Check-in status
    if let clientID = healthChecker.getClientID() {
        if !healthChecker.hasCheckedIn(clientID: clientID, config: config) {
            Logger.shared.warning("Failed Checkin")
            failedChecks += 1
            failureReasons.append("Agent hasn't checked in within \(config.daysRange) days")
        }
    } else {
        Logger.shared.error("Failed to get client ID")
        failedChecks += 1
        failureReasons.append("Unable to retrieve hardware UUID")
    }

    // Agent hash validation (only if hash is configured)
    if !healthChecker.validAgentHash(config: config) {
        Logger.shared.warning("Failed Agent Hash Check")
        failedChecks += 1
        if let expectedHash = config.mpHash {
            failureReasons.append("Agent binary hash mismatch (expected: \(expectedHash))")
        } else {
            failureReasons.append("Agent binary hash validation failed")
        }
    }

    if failedChecks > 0 {
        if dryRun {
            Logger.shared.info("DRY RUN: Checks failed (\(failedChecks)). Would download and install latest agent.")
            print("❌ Health checks FAILED (\(failedChecks) issue\(failedChecks > 1 ? "s" : ""))")
            print("")
            print("Failed checks:")
            for (index, reason) in failureReasons.enumerated() {
                print("  \(index + 1). \(reason)")
            }
            print("")
            print("Action: Installation WOULD be triggered")
            print("        Package would be downloaded from: https://\(config.mpServer)/mp-content/lazarus/")
        } else {
            Logger.shared.error("Checks failed (\(failedChecks)), downloading and installing latest agent")

            if packageManager.downloadAndInstallLatestAgent(config: config, packageInfo: packageInfo) {
                Logger.shared.info("Agent update completed successfully")
            } else {
                Logger.shared.error("Agent update failed")
            }
        }
    } else {
        if dryRun {
            Logger.shared.info("DRY RUN: All checks passed. No update needed.")
            print("✅ Health checks PASSED")
            print("")
            print("All checks:")
            print("  ✓ Agent binary exists")
            print("  ✓ Agent version meets minimum requirement")
            print("  ✓ Agent has checked in recently")
            if config.mpHash != nil {
                print("  ✓ Agent binary hash is valid")
            }
            print("")
            print("Action: No installation needed")
        } else {
            Logger.shared.info("All checks passed. No update needed.")
        }
    }

    return failedChecks == 0
}

func main() {
    let args = CommandLineArgs.parse()

    // Handle help
    if args.showHelp {
        CommandLineArgs.printHelp()
        exit(0)
    }

    // Handle version
    if args.showVersion {
        CommandLineArgs.printVersion()
        exit(0)
    }

    // Log startup mode
    if args.isDryRun {
        Logger.shared.info("Lazarus started in DRY RUN mode")
        print("🔍 Lazarus - Dry Run Mode")
        print("   No changes will be made\n")
    } else {
        Logger.shared.info("Lazarus daemon started")
    }

    // Fetch package info from server before running checks
    let config = LazarusConfig.load()
    let packageManager = PackageManager()
    let packageInfo = packageManager.fetchPackageInfo(config: config)

    if let minVer = packageInfo?.minVersion {
        Logger.shared.info("Server-provided minimum version will be used: \(minVer)")
        if args.isDryRun {
            print("ℹ️  Using server minimum version: \(minVer)")
        }
    }

    // Run once or continuously
    if args.isOnce {
        // Single check
        let passed = performHealthChecks(dryRun: args.isDryRun, packageInfo: packageInfo)
        exit(passed ? 0 : 1)
    } else {
        // Run indefinitely, performing checks every hour
        while true {
            // Fetch fresh package info each iteration
            let freshPackageInfo = packageManager.fetchPackageInfo(config: config)
            performHealthChecks(dryRun: args.isDryRun, packageInfo: freshPackageInfo)

            // Sleep for configured interval
            Logger.shared.info("Next check in 1 hour")
            sleep(Constants.Timeouts.healthCheckInterval)
        }
    }
}

main()
