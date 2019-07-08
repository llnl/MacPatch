//
//  PrefsSoftwareVC.m
//  MacPatch
//
//  Created by Charles Heizer on 2/27/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

#import "PrefsSoftwareVC.h"

@interface PrefsSoftwareVC ()

@property (nonatomic, readwrite, retain) NSString *windowTitle;

@end

@implementation PrefsSoftwareVC

- (void)viewDidLoad
{
	[super viewDidLoad];
	// Do view setup here.
	self.windowTitle = @"Fool";
	//self.title = @"Foo";
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
