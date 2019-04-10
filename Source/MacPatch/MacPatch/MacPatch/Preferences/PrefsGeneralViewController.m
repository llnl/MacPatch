//
//  PrefsGeneralViewController.m
//  MacPatch
//
//  Created by Heizer, Charles on 12/17/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

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
