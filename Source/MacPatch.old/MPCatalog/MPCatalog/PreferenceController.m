//
//  PreferenceController.m
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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

#import "PreferenceController.h"
#import "MPWorkerProtocol.h"

@interface PreferenceController (Private)

- (NSInteger)installOnLaunch;
- (BOOL)debugLogging;

// Helper
- (void)cleanup;
- (void)connect;
- (void)connectionDown:(NSNotification *)notification;
- (void)setLoggingState:(BOOL)aState;

@end

@implementation PreferenceController

- (id)init
{
    self = [super initWithWindowNibName:@"Preferences"];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:@"enableInstallOnLaunch"]) {
        [enableInstallOnLaunchCheckBox setState:[d integerForKey:@"enableInstallOnLaunch"]];
    } else {
        [enableInstallOnLaunchCheckBox setState:1];
    }
    if ([d objectForKey:@"enableRemoveSoftware"]) {
        [enableRemoveSoftwareCheckBox setState:[d integerForKey:@"enableRemoveSoftware"]];
    } else {
        [enableRemoveSoftwareCheckBox setState:1];
    }
    //[enableInstallOnLaunchCheckBox display];
    
    if ([d objectForKey:@"enableDebugLogging"]) {
        [enableDebugLogCheckBox setState:[d integerForKey:@"enableDebugLogging"]];
    } else {
        [enableDebugLogCheckBox setState:NO];
    }
}

- (NSInteger)installOnLaunch
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return ([d integerForKey:@"enableInstallOnLaunch"] ? 0 : 1);
}

- (BOOL)debugLogging
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return ([d boolForKey:@"enableDebugLogging"] ? NO : YES);
}

- (IBAction)changeInstallOnLaunch:(id)sender
{
	NSInteger state = (int)[enableInstallOnLaunchCheckBox state];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setInteger:state forKey:@"enableInstallOnLaunch"];
    [d synchronize];
    logit(lcl_vInfo,@"Changing install mandatory software on launch to %@.",([d integerForKey:@"enableInstallOnLaunch"] ? @"True" : @"False"));
}

- (IBAction)changeEnableDebugLog:(id)sender
{
	int state = (int)[enableDebugLogCheckBox state];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"enableDebugLogging"];
    [d synchronize];
    
	[self setLoggingState:[d boolForKey:@"enableDebugLogging"]];
	
	if ([enableDebugLogCheckBox state] == NSOnState) {
		lcl_configure_by_name("*", lcl_vDebug);
		logit(lcl_vDebug,@"Log level set to debug.");
	} else {
		lcl_configure_by_name("*", lcl_vInfo);
		logit(lcl_vInfo,@"Log level set to info.");
	}
}

- (IBAction)changeRemoveSoftware:(id)sender
{
    int state = (int)[enableRemoveSoftwareCheckBox state];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:state forKey:@"enableRemoveSoftware"];
    [d synchronize];
    
    if ([enableRemoveSoftwareCheckBox state] == NSOnState) {
        logit(lcl_vDebug,@"Remove Software Set to True");
    } else {
        logit(lcl_vInfo,@"Remove Software Set to False");
    }
}

#pragma mark -
#pragma mark Helper Setup

- (void) connect 
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
	
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
	
    @try {
        proxy = [connection rootProxy];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(connectionDown:)
													 name:NSConnectionDidDieNotification
												   object:connection];
		
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
	
}

- (void) cleanup 
{
    NSConnection *connection = [proxy connectionForProxy];
	
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [connection invalidate];
    proxy = nil;
	
}

#pragma mark Helper Methods

- (void)setLoggingState:(BOOL)aState
{
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try 
	{
		[proxy setDebugLogging:aState];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to set the logging level, %@", e);
    }
	
done:	
	[self cleanup];
	return;
}

// The system, is down.
- (void)connectionDown:(NSNotification *)notification 
{
    logit(lcl_vInfo,@"helperd connection down");
    [self cleanup];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app 
{
    [[proxy connectionForProxy] invalidate];
    [self cleanup];
	
    return (NSTerminateNow);
}

@end
