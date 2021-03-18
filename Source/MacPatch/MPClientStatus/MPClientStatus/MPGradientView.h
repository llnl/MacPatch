//
//  MPGradientView.h
//  MPClientStatus
//
//  Created by Charles Heizer on 3/15/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPGradientView : NSView {
    NSColor *startingColor;
    NSColor *endingColor;
    int angle;
}

@property(nonatomic, retain) NSColor *startingColor;
@property(nonatomic, retain) NSColor *endingColor;
@property(assign) int angle;

@end

NS_ASSUME_NONNULL_END
