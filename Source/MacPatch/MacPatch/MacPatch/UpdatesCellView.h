//
//  UpdatesCellView.h
//  MacPatch
//
//  Created by Charles Heizer on 11/15/18.
//  Copyright © 2018 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UpdatesCellView : NSTableCellView

@property (nonatomic, strong) IBOutlet NSDictionary     	*rowData;
@property (nonatomic, strong) IBOutlet NSTextField			*patchStatus;
@property (nonatomic, weak)   IBOutlet NSProgressIndicator	*patchProgressBar;


@property (nonatomic, assign) IBOutlet NSImageView		*icon;
@property (nonatomic, assign) IBOutlet NSImageView		*patchTypeIcon;
@property (nonatomic, assign) IBOutlet NSImageView		*patchCompletionIcon;


@property (nonatomic, strong) IBOutlet NSTextField 		*patchName;
@property (nonatomic, strong) IBOutlet NSTextField		*patchVersion;
@property (nonatomic, strong) IBOutlet NSTextField		*patchSize;
@property (nonatomic, strong) IBOutlet NSTextField		*patchDate;
@property (nonatomic, strong) IBOutlet NSTextField		*patchDescription;
@property (nonatomic, strong) IBOutlet NSTextField		*patchRestart;

@property (nonatomic, assign) IBOutlet NSButton         *updateButton;

- (IBAction)runInstall:(NSButton *)sender;
- (IBAction)runInstallAlt:(NSButton *)sender;

@end

NS_ASSUME_NONNULL_END
