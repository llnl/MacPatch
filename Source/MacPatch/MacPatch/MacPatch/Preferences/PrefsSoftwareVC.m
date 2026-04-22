//
//  PrefsSoftwareVC.m
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

#import "PrefsSoftwareVC.h"
#import "AppDelegate.h"

static NSString * const MPUserDefaultsShowSoftwareView = @"showSoftwareView";

@interface PrefsSoftwareVC ()

@property (nonatomic, readwrite, retain) NSString *windowTitle;

@end

@implementation PrefsSoftwareVC

- (void)viewDidLoad
{
	[super viewDidLoad];
    [self.showHideSoftwareCheckBox setState:[self softwareViewOnLaunch]];
}

- (BOOL)softwareViewOnLaunch
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d boolForKey:@"showSoftwareView"];
}

- (IBAction)changeSoftwareViewOnLaunch:(id)sender
{
    int state = (int)[self.showHideSoftwareCheckBox state];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:state forKey:@"showSoftwareView"];
    [d synchronize];
    
    // Update the toolbar visibility in AppDelegate
    AppDelegate *appDelegate = (AppDelegate *)[[NSApplication sharedApplication] delegate];
    [appDelegate updateToolbarVisibility];
}

#pragma mark - RHPreferencesViewControllerProtocol

-(NSString*)identifier
{
	return NSStringFromClass(self.class);
}

-(NSImage*)toolbarItemImage
{
	return [NSImage imageNamed:@"appstoreTemplate"];
}

-(NSString*)toolbarItemLabel
{
	return NSLocalizedString(@"Software", @"SoftwareToolbarItemLabel");
}

-(NSView*)initialKeyView
{
	//return self.usernameTextField;
	return self.view;
}

@end
