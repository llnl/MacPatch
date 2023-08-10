//
//  PrefsAdvancedVC.m
/*
Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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
#import "PrefsAdvancedVC.h"

@interface PrefsAdvancedVC ()
@property (nonatomic, readwrite, retain) NSString *windowTitle;
@end

@implementation PrefsAdvancedVC

@synthesize pausePatchingCheckBox;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
	self.windowTitle = @"Fool";
	
	[pausePatchingCheckBox setState:[self pausePatching]];
}

#pragma mark - RHPreferencesViewControllerProtocol

-(NSString*)identifier
{
	return NSStringFromClass(self.class);
}

-(NSImage*)toolbarItemImage
{
	return [NSImage imageNamed:@"NSActionTemplate"];
}

-(NSString*)toolbarItemLabel
{
	return NSLocalizedString(@"Advanced", @"AdvancedToolbarItemLabel");
}

-(NSView*)initialKeyView
{
	return self.view;
}

- (IBAction)changePausePatching:(id)sender
{
	int state = (int)[pausePatchingCheckBox state];
	qlinfo(@"Pause patching state changed %d",state);
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setBool:state forKey:@"pausePatching"];
	[d synchronize];
}

- (BOOL)pausePatching
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	return [d boolForKey:@"pausePatching"];
}

@end
