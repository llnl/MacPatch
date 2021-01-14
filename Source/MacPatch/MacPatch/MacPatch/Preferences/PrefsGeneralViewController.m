//
//  PrefsGeneralViewController.m
/*
Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import "PrefsGeneralViewController.h"

@interface PrefsGeneralViewController ()

@property (nonatomic, readwrite, retain) NSString *windowTitle;

@end

@implementation PrefsGeneralViewController

@synthesize enableDebugLogCheckBox;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
	//self.title = @"Foo";
	self.windowTitle = @"MacPatch Preferences";
	[enableDebugLogCheckBox setState:[self debugLogging]];
}

#pragma mark - RHPreferencesViewControllerProtocol

-(NSString*)identifier
{
    return NSStringFromClass(self.class);
}

-(NSImage*)toolbarItemImage
{
    return [NSImage imageNamed:@"NSPreferencesGeneral"];
}

-(NSString*)toolbarItemLabel
{
    return NSLocalizedString(@"General", @"GeneralToolbarItemLabel");
}

-(NSView*)initialKeyView
{
    //return self.usernameTextField;
    return self.view;
}

- (IBAction)changeEnableDebugLog:(id)sender
{
	int state = (int)[enableDebugLogCheckBox state];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"enableDebugLogging"];
	
	if ([self debugLogging]) {
		lcl_configure_by_name("*", lcl_vDebug);
		qldebug(@"Log level set to debug.");
	} else {
		lcl_configure_by_name("*", lcl_vInfo);
		qlinfo(@"Log level set to info.");
	}
	[d synchronize];
}

- (BOOL)debugLogging
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"enableDebugLogging"];
}
@end
