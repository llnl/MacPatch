//
//  PrefsSoftwareVC.h
//  MacPatch
//
//  Created by Charles Heizer on 2/27/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"

@interface PrefsSoftwareVC : NSViewController <RHPreferencesViewControllerProtocol>

@property (nonatomic, readonly, retain) NSString *windowTitle;

@end
