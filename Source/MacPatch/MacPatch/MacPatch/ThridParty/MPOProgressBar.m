//
//  MPOProgressBar.m
//  MPOProgressBar
//
//  Created by 吴天 on 19/12/17.
//  Copyright © 2017年 wutian. All rights reserved.
//

#import "MPOProgressBar.h"

@interface MPOProgressBar ()

@property (nonatomic, strong) CALayer * determinateFillLayer;
@property (nonatomic, strong) CALayer * primaryIndeterminateFillLayer;
@property (nonatomic, strong) CALayer * secondaryIndeterminateFillLayer;

@property (nonatomic, assign) BOOL animating;

@end

@implementation MPOProgressBar

- (void)dealloc
{
    self.fillColor = NULL;
}

- (instancetype)init
{
    if (self = [super init]) {
        
        [self setMasksToBounds:YES];
        
        [self addSublayer:self.determinateFillLayer];
        [self addSublayer:self.primaryIndeterminateFillLayer];
        [self addSublayer:self.secondaryIndeterminateFillLayer];
        
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        if (space) {
            {
                CGColorRef color = CGColorCreate(space, (CGFloat[4]){180.0/255, 207.0/255, 240.0/255, 1.0});
                if (color) {
                    self.backgroundColor = color;
                    CGColorRelease(color);
                }
            }
            
            {
                CGColorRef color = CGColorCreate(space, (CGFloat[4]){66.0/255, 139.0/255, 237.0/255, 1.0});
                if (color) {
                    self.fillColor = color;
                    CGColorRelease(color);
                }
            }
            CGColorSpaceRelease(space);
        }
    }
    return self;
}

- (void)layoutSublayers
{
    [super layoutSublayers];
    
    CGRect b = self.bounds;
    _determinateFillLayer.frame = CGRectMake(0, 0, b.size.width * _progress, b.size.height);

    [self _layoutIndeterminateLayers];
}

- (CALayer *)determinateFillLayer
{
    if (!_determinateFillLayer) {
        _determinateFillLayer = [CALayer layer];
    }
    return _determinateFillLayer;
}

- (CALayer *)primaryIndeterminateFillLayer
{
    if (!_primaryIndeterminateFillLayer) {
        _primaryIndeterminateFillLayer = [CALayer layer];
        _primaryIndeterminateFillLayer.opacity = 0.0;
    }
    return _primaryIndeterminateFillLayer;
}

- (CALayer *)secondaryIndeterminateFillLayer
{
    if (!_secondaryIndeterminateFillLayer) {
        _secondaryIndeterminateFillLayer = [CALayer layer];
        _secondaryIndeterminateFillLayer.opacity = 0.0;
    }
    return _secondaryIndeterminateFillLayer;
}

- (void)setFillColor:(CGColorRef)fillColor
{
    _determinateFillLayer.backgroundColor = fillColor;
    _primaryIndeterminateFillLayer.backgroundColor = fillColor;
    _secondaryIndeterminateFillLayer.backgroundColor = fillColor;
}

- (CGColorRef)fillColor
{
    return _determinateFillLayer.backgroundColor;
}

- (void)setProgress:(double)progress
{
    progress = MAX(0, MIN(progress, 1));
    if (_progress != progress) {
        _progress = progress;
        
        [self setNeedsLayout];
    }
}

- (void)setProgressMode:(MPOProgressBarMode)progressMode
{
    if (_progressMode != progressMode) {
        _progressMode = progressMode;
        
        if (progressMode != MPOProgressBarModeIndeterminate) {
            [self stopAnimation];
        }
        
        _determinateFillLayer.opacity = (progressMode == MPOProgressBarModeDeterminate) ? 1.0 : 0.0;
    }
}

- (void)startAnimation
{
    if (_progressMode != MPOProgressBarModeIndeterminate) {
        return;
    }
    
    if (self.animating) {
        return;
    }
    
    _primaryIndeterminateFillLayer.opacity = 1.0;
    _secondaryIndeterminateFillLayer.opacity = _primaryIndeterminateFillLayer.opacity;
    
    [self _layoutIndeterminateLayers];
    
    self.animating = YES;
    
    [_primaryIndeterminateFillLayer addAnimation:[self _primaryIndeterminateTranslateAnimation] forKey:@"translate"];
    [_primaryIndeterminateFillLayer addAnimation:[self _primaryIndeterminateScaleAnimation] forKey:@"scale"];
    [_secondaryIndeterminateFillLayer addAnimation:[self _secondaryIndeterminateTranslateAnimation] forKey:@"translate"];
    [_secondaryIndeterminateFillLayer addAnimation:[self _secondaryIndeterminateScaleAnimation] forKey:@"scale"];
}

- (void)stopAnimation
{
    if (self.animating) {
        self.animating = NO;
        
        [self.primaryIndeterminateFillLayer removeAllAnimations];
        [self.secondaryIndeterminateFillLayer removeAllAnimations];
        
        _primaryIndeterminateFillLayer.opacity = 0.0;
        _secondaryIndeterminateFillLayer.opacity = _primaryIndeterminateFillLayer.opacity;
    }
}

// Code below ported from:
// https://github.com/material-components/material-components-web/blob/master/packages/mdc-linear-progress/_keyframes.scss
// https://github.com/material-components/material-components-web/blob/master/packages/mdc-linear-progress/mdc-linear-progress.scss

- (void)_layoutIndeterminateLayers
{
    if (self.animating) {
        return;
    }
    
    CGRect b = self.bounds;
    CGFloat width = b.size.width;
    CGFloat height = b.size.height;
    
    _primaryIndeterminateFillLayer.frame = CGRectMake(-1.45166611 * width, 0, width, height);
    _secondaryIndeterminateFillLayer.frame = CGRectMake(-0.54888891 * width, 0, width, height);
}

typedef struct __attribute__((objc_boxable)) CGAffineTransform CGAffineTransform;

- (CAAnimation *)_primaryIndeterminateTranslateAnimation
{
    CGFloat width = self.bounds.size.width;
    
    CAKeyframeAnimation * animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    
    animation.keyTimes = @[@0, @0.2, @0.5915, @1];
    
    animation.values = @[@0, @0, @(width * 0.8367142), @(width * 2.00611057)];
    
    animation.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
                                  [CAMediaTimingFunction functionWithControlPoints:0.5 :0.0 :0.701732 :0.495819],
                                  [CAMediaTimingFunction functionWithControlPoints:0.302435 :0.381352 :0.55 :0.956352]];
    
    animation.duration = 2.0;
    animation.repeatCount = CGFLOAT_MAX;
    
    return animation;
}

- (CAAnimation *)_primaryIndeterminateScaleAnimation
{
    CAKeyframeAnimation * animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    
    animation.keyTimes = @[@0, @0.3665, @0.6915, @1];
    
    animation.values = @[@0.08, @0.08, @0.661479, @0.08];
    
    animation.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
                                  [CAMediaTimingFunction functionWithControlPoints:0.334731 :0.12482 :0.785844 :1],
                                  [CAMediaTimingFunction functionWithControlPoints:0.06 :0.11 :0.6 :1]];
    
    animation.duration = 2.0;
    animation.repeatCount = CGFLOAT_MAX;

    return animation;
}

- (CAAnimation *)_secondaryIndeterminateTranslateAnimation
{
    CGFloat width = self.bounds.size.width;
    
    CAKeyframeAnimation * animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    
    animation.keyTimes = @[@0, @0.25, @0.4835, @1];
    
    animation.values = @[@0, @(width * 0.37651913), @(width * 0.84386165), @(width * 1.60277782)];
    
    animation.timingFunctions = @[[CAMediaTimingFunction functionWithControlPoints:0.15 :0.0 :0.515058 :0.409685],
                                  [CAMediaTimingFunction functionWithControlPoints:0.31033 :0.284058 :0.8 :0.733712],
                                  [CAMediaTimingFunction functionWithControlPoints:0.4 :0.627035 :0.6 :0.902026]];
    
    animation.duration = 2.0;
    animation.repeatCount = CGFLOAT_MAX;
    
    return animation;
}

- (CAAnimation *)_secondaryIndeterminateScaleAnimation
{
    CAKeyframeAnimation * animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    
    animation.keyTimes = @[@0, @0.1915, @0.4415, @1];
    
    animation.values = @[@0.08, @0.457104, @0.72796, @0.08];
    
    animation.timingFunctions = @[[CAMediaTimingFunction functionWithControlPoints:0.205028 :0.057051 :0.57661 :0.453971],
                                  [CAMediaTimingFunction functionWithControlPoints:0.152313 :0.196432 :0.648374 :1.004315],
                                  [CAMediaTimingFunction functionWithControlPoints:0.257759 :-0.003163 :0.211762 :1.38179]];
    
    animation.duration = 2.0;
    animation.repeatCount = CGFLOAT_MAX;
    
    return animation;
}

@end
