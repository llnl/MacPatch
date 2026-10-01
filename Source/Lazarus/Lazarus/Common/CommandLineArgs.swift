//
//  CommandLineArgs.swift
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

struct CommandLineArgs {
    let isDryRun: Bool
    let isOnce: Bool
    let showHelp: Bool
    let showVersion: Bool

    static func parse() -> CommandLineArgs {
        let args = CommandLine.arguments

        return CommandLineArgs(
            isDryRun: args.contains("--dry-run") || args.contains("--test") || args.contains("-n"),
            isOnce: args.contains("--once"),
            showHelp: args.contains("--help") || args.contains("-h"),
            showVersion: args.contains("--version") || args.contains("-v")
        )
    }

    static func printHelp() {
        print("""
        Lazarus - MacPatch Recovery Daemon

        USAGE:
            lazarus [OPTIONS]

        OPTIONS:
            --dry-run, --test, -n    Run health checks without installing updates
                                     (shows what would be done)

            --once                   Run checks once and exit (don't loop)

            --version, -v            Show version information

            --help, -h               Show this help message

        DESCRIPTION:
            Lazarus monitors MacPatch agent health and automatically downloads
            and installs updates when issues are detected.

            By default, Lazarus runs continuously and performs health checks
            every hour. Use --once to run a single check, or --dry-run to see
            what would happen without making changes.

        EXAMPLES:
            # Run in daemon mode (default)
            lazarus

            # Test if installation is needed
            lazarus --dry-run

            # Run checks once and exit
            lazarus --once

            # Dry-run single check
            lazarus --dry-run --once

        FILES:
            Config:  /Library/Application Support/MacPatch/gov.llnl.mp.lazarus.plist
            Log:     /Library/Logs/mp_lazarus.log

        """)
    }

    static func printVersion() {
        print("Lazarus version 1.0.0")
        print("MacPatch Recovery Daemon")
    }
}
