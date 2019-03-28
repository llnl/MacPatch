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

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.windowTitle = @"Fool";
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

@end
