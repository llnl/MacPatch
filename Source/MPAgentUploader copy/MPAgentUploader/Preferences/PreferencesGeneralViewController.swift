//
//  PreferencesGeneralViewController.swift
//  MPAgentUploder
//
//  Created by Charles Heizer on 12/7/16.
//
/*
 Copyright (c) 2016, Lawrence Livermore National Security, LLC.
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

class PreferencesGeneralViewController: NSViewController
{
    
    let defaults = UserDefaults.standard
    
    @IBOutlet weak var agentUploadButton: NSButton!
    @IBOutlet weak var loggingButton: NSButton!
    @IBOutlet weak var selfSignedButton: NSButton!
    
    override func viewDidAppear()
    {
        let _agentUploadState = defaults.bool(forKey: "doNotUpload") ? NSControl.StateValue.on : NSControl.StateValue.off
        let _debugState = defaults.bool(forKey: "Debug")  ? NSControl.StateValue.on : NSControl.StateValue.off
        let _selfSignedState = defaults.bool(forKey: "selfSigned")  ? NSControl.StateValue.on : NSControl.StateValue.off
        
        self.agentUploadButton.state = _agentUploadState
        self.loggingButton.state = _debugState
        self.selfSignedButton.state = _selfSignedState
    }

    @IBAction func debugOption(_ sender: AnyObject) {
        NotificationCenter.default.post(name: Notification.Name("LogLevel"), object: nil)
    }
    
    @IBAction func uploadOption(_ sender: AnyObject) {
        NotificationCenter.default.post(name: Notification.Name("AgentUpload"), object: nil)
    }
    
    @IBAction func selfSignedOption(_ sender: AnyObject) {
        NotificationCenter.default.post(name: Notification.Name("SelfSigned"), object: nil)
    }

}
