//
//  MPauthrestartVC.h
//  MacPatch
//
//  Created by Charles Heizer on 2/26/20.
//  Copyright © 2020 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPauthrestartVC : NSViewController

@property (nonatomic, weak) IBOutlet NSTextField *userName;
@property (nonatomic, weak) IBOutlet NSSecureTextField *userPass;
@property (nonatomic, retain) IBOutlet NSButton *useRecoveryKeyCheckBox;

@property (nonatomic, weak) IBOutlet NSImageView *errImage;
@property (nonatomic, weak) IBOutlet NSTextField *errMsg;


- (BOOL)clearAuthStatus;
@end

NS_ASSUME_NONNULL_END
