//
//  PrefsAdvancedVC.h
//  MacPatch
//
//  Created by Charles Heizer on 11/4/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"

@interface PrefsAdvancedVC : NSViewController <RHPreferencesViewControllerProtocol>

@property (nonatomic, readonly, retain) NSString *windowTitle;
@property (nonatomic, retain) IBOutlet NSButton *pausePatchingCheckBox;

@end

