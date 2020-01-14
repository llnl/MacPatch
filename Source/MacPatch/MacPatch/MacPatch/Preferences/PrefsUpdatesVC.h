//
//  PrefsUpdatesVC.h
//  MacPatch
//
//  Created by Charles Heizer on 2/27/19.
//  Copyright © 2019 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"

@interface PrefsUpdatesVC : NSViewController <RHPreferencesViewControllerProtocol>

@property (atomic, strong, readwrite) 	NSXPCConnection *workerConnection;
@property (nonatomic, readonly, retain) NSString *windowTitle;

@property (nonatomic, retain) IBOutlet NSButton *scanOnLaunchCheckBox;
@property (nonatomic, retain) IBOutlet NSButton *preStageRebootPatchesBox;
@property (nonatomic, retain) IBOutlet NSButton *allowInstallRebootPatchesCheckBox;
@property (nonatomic, retain) IBOutlet NSButton *pausePatchingCheckBox;

@end
