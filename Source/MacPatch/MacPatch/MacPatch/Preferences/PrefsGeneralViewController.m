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

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
	//self.title = @"Foo";
	self.windowTitle = @"MacPatch Preferences";
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

@end
