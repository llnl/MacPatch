//
//  AppDelegate.swift
//  MPAgentUploder
//
//  Created by Charles Heizer on 12/7/16.
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

import Cocoa

var log = AppLogger()

//import SwiftyBeaver
//let log = SwiftyBeaver.self

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    
    let defaults = UserDefaults.standard
    
    func applicationDidFinishLaunching(_ aNotification: Notification)
	{
        log = AppLogger(
            fileURL: URL(fileURLWithPath: logPath),
            numberOfFiles: 7,
            maxFileSizeKB: 10 * 1024,
            minimumLevel: .info
        )
        
        NotificationCenter.default.post(name: Notification.Name("setLogLevel"), object: nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApplication.shared.terminate(self)
        return true
    }
    
    lazy var preferencesWindowController: PreferencesWindowController  = {
        let wcSB = NSStoryboard(name: "Preferences", bundle: Bundle.main)
        // or whichever bundle
        return wcSB.instantiateInitialController() as! PreferencesWindowController
    }()
    
    @IBAction func showPreferencesWindow(_ sender: NSObject?)
    {
        self.preferencesWindowController.showWindow(self)
    }
    
    @IBAction func showLogFileInConsole(_ sender: NSObject?)
    {
        let logFileURL = log.currentLogFileURL()
        let consoleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console")
        
        if let consoleURL = consoleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([logFileURL], withApplicationAt: consoleURL, configuration: configuration) { _, error in
                if let error = error {
                    log.error("Failed to open log file in Console: \(error.localizedDescription)")
                }
            }
        } else {
            log.error("Failed to locate Console application")
        }
    }
	
	@IBAction func resetAuthInfo(_ sender: NSObject?)
	{
		NotificationCenter.default.post(name: Notification.Name("ResetAuthToken"), object: nil)
	}
    
    @IBAction func pressed(sender: AnyObject) {
        if let window = NSApplication.shared.mainWindow {
            if let viewController = window.contentViewController as? ViewController {
                // do stuff
                viewController.displayMigrationPlistSheet()
            }
        }
    }
}

