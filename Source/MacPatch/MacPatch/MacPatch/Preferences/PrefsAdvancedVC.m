//
//  PrefsAdvancedVC.m
//  MacPatch
//
//  Created by Charles Heizer on 11/4/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

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
