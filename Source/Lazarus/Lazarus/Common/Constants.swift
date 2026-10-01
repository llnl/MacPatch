//
//  Constants.swift
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

enum Constants {

    // MARK: - Paths

    enum Paths {
        /// MacPatch client installation directory
        static let macpatchClientDir = "/Library/MacPatch/Client"

        /// MacPatch agent binary path
        static let agentBinary = "\(macpatchClientDir)/MPAgent"

        /// MacPatch version plist path
        static let versionPlist = "\(macpatchClientDir)/.mpVersion.plist"

        /// Lazarus configuration file path
        static let configPlist = "/Library/Application Support/.MacPatch/gov.llnl.mp.lazarus.plist"

        /// Main log file path (includes application logs, stdout, and stderr)
        static let mainLog = "/Library/Logs/mp_lazarus.log"

        /// Temporary directory for downloads
        static let tmpDir = "/private/tmp"

        /// System installer binary
        static let installerBinary = "/usr/sbin/installer"

        /// Root target for package installation
        static let installTarget = "/"

        /// MacPatch uninstall script
        static let uninstallScript = "\(macpatchClientDir)/Tools/MPUninstaller.command"
    }

    // MARK: - URLs

    enum URLs {
        /// Lazarus content path on server
        static let lazarusPath = "/mp-content/lazarus"

        /// Package subdirectory path
        static let packagePath = "/pkg"

        /// Package info plist filename
        static let packageInfoPlistName = "gov.llnl.lazarus.plist"

        /// Constructs base URL for Lazarus package distribution
        static func lazarusBase(server: String) -> String {
            return "https://\(server)\(lazarusPath)"
        }

        /// Constructs package information plist URL
        static func packageInfoPlist(server: String) -> String {
            return "\(lazarusBase(server: server))/\(packageInfoPlistName)"
        }

        /// Constructs full package download URL
        static func packageURL(server: String, packageName: String) -> String {
            return "\(lazarusBase(server: server))\(packagePath)/\(packageName)"
        }

        /// Constructs API URL for client check-in info
        static func checkinURL(server: String, clientID: String) -> String {
            return "https://\(server)/api/v1/client/checkin/info/\(clientID)"
        }
    }

    // MARK: - Defaults

    enum Defaults {
        /// Default minimum agent version
        static let minAgentVersion = "4.2.2.0"

        /// Default days range for check-in validation
        static let daysRange = 15

        /// Default server hostname
        static let server = "localhost"

        /// Default SSL validation behavior (secure by default)
        static let ignoreSSL = false

        /// Default beta flag
        static let isBeta = false
    }

    // MARK: - Timeouts

    enum Timeouts {
        /// Network request timeout in seconds
        static let networkRequest: TimeInterval = 30

        /// Package download timeout in seconds
        static let packageDownload: TimeInterval = 300

        /// Plist download timeout in seconds
        static let plistDownload: TimeInterval = 60

        /// Health check interval in seconds (1 hour)
        static let healthCheckInterval: UInt32 = 3600
    }

    // MARK: - Configuration Keys

    enum ConfigKeys {
        /// Configuration plist key for minimum version
        static let minVersionKey = "minversion"

        /// Configuration plist key for days range
        static let daysRangeKey = "daysrange"

        /// Configuration plist key for server
        static let serverKey = "mpserver"

        /// Configuration plist key for SSL ignore
        static let ignoreSSLKey = "ignoressl"

        /// Configuration plist key for agent hash
        static let hashKey = "mphash"
    }

    // MARK: - Agent Version Plist Keys

    enum AgentVersionKeys {
        /// Agent version plist key for version string
        static let version = "version"

        /// Agent version plist key for build string
        static let build = "build"
    }

    // MARK: - Package Info Plist Keys

    enum PackageInfoKeys {
        /// Package array key
        static let packageArray = "Package"

        /// Package name key (inside Package array)
        static let name = "MacPatch"

        /// Package version key (inside Package array)
        static let version = "Version"

        /// Minimum agent version key (inside Package array) - optional, overrides local config
        static let minVersion = "MinVersion"

        /// Package SHA-256 hash key (inside Package array)
        static let hash = "PkgHash"
    }

    // MARK: - API Response Keys

    enum APIKeys {
        /// API result key
        static let result = "result"

        /// Last modified date key
        static let mdate = "mdate2"
    }

    // MARK: - Date Formats

    enum DateFormats {
        /// Log timestamp format
        static let logTimestamp = "yyyy-MM-dd HH:mm:ss"

        /// API date format
        static let apiDate = "MM/dd/yyyy"
    }

    // MARK: - IOKit

    enum IOKit {
        /// IOKit service name for platform expert
        static let platformExpertDevice = "IOPlatformExpertDevice"

        /// IOKit property name for platform UUID
        static let platformUUID = "IOPlatformUUID"
    }
}
