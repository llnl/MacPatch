//
//  LongPatchWindow.h
//  TestAlert
//
//  Created by Charles Heizer on 11/20/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LongPatchWindow : NSWindowController

@property(nonatomic, strong) IBOutlet NSTextField *title;
@property(nonatomic, strong) IBOutlet NSTextField *message;
@property(nonatomic, strong, setter=setPatch:) NSDictionary *patch;


- (id)initWithWindowNibName:(NSString *)windowNibName patch:(NSDictionary *)aPatch;
- (id)initWithPatch:(NSDictionary *)aPatch;

- (void)show;

@end

NS_ASSUME_NONNULL_END
