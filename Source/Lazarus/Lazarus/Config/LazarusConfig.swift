//
//  LazarusConfig.swift
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

struct LazarusConfig {
    var minAgentVersion = Constants.Defaults.minAgentVersion
    var daysRange = Constants.Defaults.daysRange
    var ignoreSSL = Constants.Defaults.ignoreSSL
    var isBeta = Constants.Defaults.isBeta
    var mpServer = Constants.Defaults.server
    var mpHash: String? = nil  // nil means hash check is disabled

    static func load() -> LazarusConfig {
        var config = LazarusConfig()
        let plistPath = Constants.Paths.configPlist

        if FileManager.default.fileExists(atPath: plistPath),
           let plistData = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {

            if let minVersion = plist[Constants.ConfigKeys.minVersionKey] as? String {
                config.minAgentVersion = minVersion
            }
            if let days = plist[Constants.ConfigKeys.daysRangeKey] as? Int {
                config.daysRange = days
            }
            if let server = plist[Constants.ConfigKeys.serverKey] as? String {
                config.mpServer = server
            }
            if let ignoreSSL = plist[Constants.ConfigKeys.ignoreSSLKey] as? Bool {
                config.ignoreSSL = ignoreSSL
            }
            // Only set hash if the key is defined in the plist
            if let hash = plist[Constants.ConfigKeys.hashKey] as? String {
                config.mpHash = hash
            }
        }

        return config
    }
}
