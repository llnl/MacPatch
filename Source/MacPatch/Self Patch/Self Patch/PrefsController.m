//
//  PrefsController.m
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

#import "PrefsController.h"
#import "MPWorkerProtocol.h"

@implementation PrefsController

- (id)init
{
    self = [super initWithWindowNibName:@"Preferences"];
	if (!self)
		return nil;

	return self;	
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[scanOnLaunchCheckBox setState:[self scanOnLaunch]];
    [preStageRebootPatchesBox setState:[self preStageRebootPatches]];
	[enableDebugLogCheckBox setState:[self debugLogging]];
    [allowInstallRebootPatchesCheckBox setState:[self allowInstallRebootPatches]];
	[stateColumnCheckBox setState:[self colStateOnLaunch]];
	[sizeColumnCheckBox setState:[self colSizeOnLaunch]];
	[baselineColumnCheckBox setState:[self colBaselineOnLaunch]];
}

- (IBAction)doNothing:(id)sender;
{
	return;	
}

- (IBAction)changeScanOnLaunch:(id)sender
{
	int state = (int)[scanOnLaunchCheckBox state];
	logit(lcl_vInfo,@"Scan on launch state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"enableScanOnLaunch"];
}

- (IBAction)changePreStageRebootPatches:(id)sender
{
    int state = (int)[preStageRebootPatchesBox state];
    logit(lcl_vInfo,@"Pre stage reboot patches state changed %d",state);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:state forKey:@"preStageRebootPatches"];
}

- (IBAction)changeAllowInstallOfRebootPatches:(id)sender
{
    int state = (int)[allowInstallRebootPatchesCheckBox state];
    logit(lcl_vInfo,@"Allow Reboot Patch Installs state changed %d",state);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:state forKey:@"allowRebootPatchInstalls"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AllowInstallRebootPatches" object:self];
}

- (IBAction)changeEnableDebugLog:(id)sender
{
	int state = (int)[enableDebugLogCheckBox state];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"enableDebugLogging"];
	[self setLoggingState:[d boolForKey:@"enableDebugLogging"]];
	
	if ([self debugLogging]) {
		lcl_configure_by_name("*", lcl_vDebug);
		logit(lcl_vDebug,@"Log level set to debug.");
	} else {
		lcl_configure_by_name("*", lcl_vInfo);
		logit(lcl_vInfo,@"Log level set to info.");
	}
}

- (IBAction)showHideSelectColumn:(id)sender 
{
	int state = (int)[stateColumnCheckBox state];
	logit(lcl_vInfo,@"Show \"State\" column changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"colStateOnLaunch"];	
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc postNotificationName:@"MPSelfPatchColStateToggle" object:self];
}

- (IBAction)showHideSizeColumn:(id)sender 
{
	int state = (int)[sizeColumnCheckBox state];
	logit(lcl_vInfo,@"Show \"Size\" column changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"colSizeOnLaunch"];	
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc postNotificationName:@"MPSelfPatchColSizeToggle" object:self];
}

- (IBAction)showHideBselineColumn:(id)sender 
{
	int state = (int)[baselineColumnCheckBox state];
	logit(lcl_vInfo,@"Show \"Baseline\" column changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"colBaselineOnLaunch"];	
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc postNotificationName:@"MPSelfPatchColBaselineToggle" object:self];
}

- (BOOL)scanOnLaunch
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"enableScanOnLaunch"];
}

- (BOOL)preStageRebootPatches
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d boolForKey:@"preStageRebootPatches"];
}

- (BOOL)debugLogging
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"enableDebugLogging"];
}

- (BOOL)allowInstallRebootPatches
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d boolForKey:@"allowRebootPatchInstalls"];
}

- (BOOL)colStateOnLaunch;
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"colStateOnLaunch"];
}

- (BOOL)colSizeOnLaunch;
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"colSizeOnLaunch"];
}

- (BOOL)colBaselineOnLaunch;
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"colBaselineOnLaunch"];
}

// Helper
- (void) connect {
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
	
} // connect

- (void) cleanup {
    NSConnection *connection = [proxy connectionForProxy];
	
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [connection invalidate];
    proxy = nil;
	
} // cleanup

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
} // connectionDown


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app 
{
    [[proxy connectionForProxy] invalidate];
    [self cleanup];
	
    return (NSTerminateNow);
} // applicationShouldTerminate

@end
