//
//  MPOProgressBar.h
//  MPOProgressBar
//
//  Created by 吴天 on 19/12/17.
//  Copyright © 2017年 wutian. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

/**
 Different operating modes for the progress bar.
 
 This component can be used as a determinate progress bar or an indeterminate progress bar.
 
 Default value is MPOProgressBarModeDeterminate.
 */
typedef NS_ENUM(NSInteger, MPOProgressBarMode) {
    /** Determinate progress bar display how long an operation will take. */
    MPOProgressBarModeDeterminate = 0,
    /** Indeterminate progress bars visualize an unspecified wait time. */
    MPOProgressBarModeIndeterminate,
};

/**
 A Material Design progress bar.
 */
@interface MPOProgressBar : CALayer

/**
 The mode of the progress bar. Default is MPOProgressBarModeDeterminate.
 */
@property (nonatomic, assign) MPOProgressBarMode progressMode;

/**
 Progress is the extent to which the progress bar fill color is drawn to completion when
 progressMode is MPOProgressBarModeDeterminate. Valid range is between [0-1]. Default is
 zero. 0.5 progress is half the width. The transitions between progress levels are animated.
 */
@property (nonatomic, assign) double progress;


@property (nonatomic, assign) CGColorRef fillColor;

/**
 Whether or not the progress bar is currently animating.
 */
@property (nonatomic, assign, readonly) BOOL animating;

/**
 Starts the animated progress bar. Does nothing if the progress bar is already animating or in MPOProgressBarModeDeterminate mode.
 */
- (void)startAnimation;

/**
 Stops the animated progress bar.
 */
- (void)stopAnimation;

@end
