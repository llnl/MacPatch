//
//  PreferencesWindowController.swift
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

class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    
    private var toolbarConfigured = false
    
    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.center()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidBecomeKey(_ notification: Notification) {
        if !toolbarConfigured {
            configureToolbar()
        }
    }
    
    func windowDidUpdate(_ notification: Notification) {
        if !toolbarConfigured {
            configureToolbar()
        }
    }
    
    private func configureToolbar() {
        guard let toolbar = window?.toolbar else { return }
        guard !toolbarConfigured else { return }
        
        // Set ourselves as the delegate to control the toolbar
        toolbar.delegate = self
        
        toolbarConfigured = true
    }
    
    // MARK: - NSToolbarDelegate
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Get the current items (which includes the tab view controller's segmented control)
        let currentIdentifiers = toolbar.items.map { $0.itemIdentifier }
        
        // Add flexible space after the first item to push everything else to the right
        // This leaves the tab selector on the left
        var identifiers: [NSToolbarItem.Identifier] = []
        
        if let firstIdentifier = currentIdentifiers.first {
            identifiers.append(firstIdentifier)
            identifiers.append(.flexibleSpace)
        }
        
        // Add any remaining identifiers
        identifiers.append(contentsOf: currentIdentifiers.dropFirst())
        
        return identifiers
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers = toolbar.items.map { $0.itemIdentifier }
        
        if !identifiers.contains(.flexibleSpace) {
            identifiers.append(.flexibleSpace)
        }
        
        return identifiers
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        // Return nil to use default items, or create custom items here
        return nil
    }
}
