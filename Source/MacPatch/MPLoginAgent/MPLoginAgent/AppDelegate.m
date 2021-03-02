//
//  AppDelegate.m
//  MPLoginAgent
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "AppDelegate.h"
#import "MinScanAndPatchVC.h"

@interface AppDelegate () <NSApplicationDelegate>

@property (nonatomic, assign, readwrite) IBOutlet NSPanel *panel;

@end

@implementation AppDelegate

- (void)awakeFromNib
{
    NSString *logFile = [MP_ROOT_CLIENT stringByAppendingPathComponent:@"/Logs/MPLoginAgent.log"];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Debug"])
    {
        [MPLog setupLogging:logFile level:lcl_vDebug];
        lcl_configure_by_name("*", lcl_vDebug);
        logit(lcl_vInfo,@"***** MPLoginAgent started -- Debug Enabled *****");
    } else {
        [MPLog setupLogging:logFile level:lcl_vInfo];
        lcl_configure_by_name("*", lcl_vInfo);
        logit(lcl_vInfo,@"***** MPLoginAgent started *****");
    }
    
    [[self panel] setBackgroundColor:[NSColor darkGrayColor]];
    
	// Center the custon view controller
	[self.minScanAndPatchVC.view setFrameOrigin:NSMakePoint(
														 (NSWidth([self.panel.contentView bounds]) - NSWidth([self.minScanAndPatchVC.view frame])) / 2,
														 (NSHeight([self.panel.contentView bounds]) - NSHeight([self.minScanAndPatchVC.view frame])) / 1.6
														 )];
	self.minScanAndPatchVC.view.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
	[self.panel.contentView addSubview:self.minScanAndPatchVC.view];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    
    [[NSApplication sharedApplication] setPresentationOptions:NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock];

    NSRect windowFrame = [[self panel] frame];
    windowFrame.size.height = [[NSScreen mainScreen] frame].size.height;
    windowFrame.size.width = [[NSScreen mainScreen] frame].size.width;
    windowFrame.origin.x = (double)0;
    windowFrame.origin.y = (double)0;
    [[self panel] setFrame:windowFrame display:YES animate:NO];
    
    
    // We have to call -[NSWindow setCanBecomeVisibleWithoutLogin:] to let the
    // system know that we're not accidentally trying to display a window
    // pre-login.
    
    [self.panel setCanBecomeVisibleWithoutLogin:YES];
    
    // Our application is a UI element which never activates, so we want our
    // panel to show regardless.
    
    [self.panel setHidesOnDeactivate:NO];
    
    // Due to a problem with the relationship between the UI frameworks and the
    // window server <rdar://problem/5136400>, -[NSWindow orderFront:] is not
    // sufficient to show the window.  We have to use -[NSWindow orderFrontRegardless].
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ForceOrderFront"]) {
        // Showing window with extreme prejudice
        [self.panel orderFrontRegardless];
    } else {
        // Showing window normally
        [self.panel orderFront:self];
    }
    //[self.panel setLevel:kCGStatusWindowLevel];
    [self.panel setLevel:kCGMaximumWindowLevel];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

@end
