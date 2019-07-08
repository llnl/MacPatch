//
//  PrefsGeneralViewController.h
//  MacPatch
//
//  Created by Heizer, Charles on 12/17/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"

@interface PrefsGeneralViewController : NSViewController <RHPreferencesViewControllerProtocol>

@property (nonatomic, readonly, retain) NSString *windowTitle;
@property (nonatomic, retain) IBOutlet NSButton *enableDebugLogCheckBox;

@end
