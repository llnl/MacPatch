//
//  PrefsUpdatesVC.m
//  MacPatch
//
//  Created by Charles Heizer on 2/27/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

#import "PrefsUpdatesVC.h"

@interface PrefsUpdatesVC ()

@property (nonatomic, readwrite, retain) NSString *windowTitle;

@end

@implementation PrefsUpdatesVC

@synthesize scanOnLaunchCheckBox;
@synthesize preStageRebootPatchesBox;
@synthesize allowInstallRebootPatchesCheckBox;

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.windowTitle = @"Fool";
	
	[scanOnLaunchCheckBox setState:[self scanOnLaunch]];
	[preStageRebootPatchesBox setState:[self preStageRebootPatches]];
	[allowInstallRebootPatchesCheckBox setState:[self allowInstallRebootPatches]];
}

#pragma mark - RHPreferencesViewControllerProtocol

-(NSString*)identifier
{
	return NSStringFromClass(self.class);
}

-(NSImage*)toolbarItemImage
{
	return [NSImage imageNamed:@"UpdatesTemplate"];
}

-(NSString*)toolbarItemLabel
{
	return NSLocalizedString(@"Updates", @"UpdatesToolbarItemLabel");
}

-(NSView*)initialKeyView
{
	//return self.usernameTextField;
	return self.view;
}

- (IBAction)changeScanOnLaunch:(id)sender
{
	int state = (int)[scanOnLaunchCheckBox state];
	qlinfo(@"Scan on launch state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"enableScanOnLaunch"];
	[d synchronize];
}

- (IBAction)changePreStageRebootPatches:(id)sender
{
	int state = (int)[preStageRebootPatchesBox state];
	qlinfo(@"Pre stage reboot patches state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"preStageRebootPatches"];
	[d synchronize];
}

- (IBAction)changeAllowInstallOfRebootPatches:(id)sender
{
	int state = (int)[allowInstallRebootPatchesCheckBox state];
	qlinfo(@"Allow Reboot Patch Installs state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"allowRebootPatchInstalls"];
	[d synchronize];
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


@end
