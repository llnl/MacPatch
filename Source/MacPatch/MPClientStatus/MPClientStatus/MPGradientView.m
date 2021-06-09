//
//  MPGradientView.m
//  MPClientStatus
//
//  Created by Charles Heizer on 3/15/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import "MPGradientView.h"

@implementation MPGradientView

@synthesize startingColor;
@synthesize endingColor;
@synthesize angle;
@synthesize xPoint;
@synthesize yPoint;
/*
- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        //[self setEndingColor:[NSColor colorWithCalibratedRed:0.941 green:0.941 blue:0.941 alpha:1]];
        [self setEndingColor:[NSColor whiteColor]];
        // [self setStartingColor:[NSColor colorWithCalibratedRed:0.701 green:0.701 blue:0.701 alpha:1]];
        [self setStartingColor:[self colorFromHex:@"abb7c7"]];
        [self setAngle:180];
    }
    return self;
}

- (void)drawRect:(NSRect)rect {
    if (endingColor == nil || [startingColor isEqual:endingColor]) {
        // Fill view with a standard background color
        [startingColor set];
        NSRectFill(rect);
    }
    else {
        // Fill view with a top-down gradient
        // from startingColor to endingColor
        NSGradient* aGradient = [[NSGradient alloc] initWithStartingColor:[NSColor whiteColor] endingColor:[self colorFromHex:@"abb7c7"]];
        [aGradient drawInRect:[self bounds] angle:angle];
    }
}
*/
- (void)drawRect:(NSRect)rect
{
    // Gradient draws from bottom up at 90 degrees
    if (startingColor == nil) {
        startingColor = [self colorFromHex:@"abb7c7"];
    }
    if (endingColor == nil) {
        endingColor = [NSColor whiteColor];
    }
    if (!angle) {
        angle = 90;
    }
    if (!xPoint) {
        xPoint = 0;
    }
    if (!yPoint) {
        yPoint = 54;
    }
    
    [super drawRect:rect];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:startingColor endingColor:endingColor];
    NSRect bounds = NSMakeRect(xPoint,yPoint, 800, 600);
    [gradient drawInRect:bounds angle:angle];
}
- (NSColor *)colorFromHex:(NSString *)inColorString
{
    NSColor* result = nil;
    unsigned colorCode = 0;
    unsigned char redByte, greenByte, blueByte;

    if (nil != inColorString)
    {
         NSScanner* scanner = [NSScanner scannerWithString:inColorString];
         (void) [scanner scanHexInt:&colorCode]; // ignore error
    }
    redByte = (unsigned char)(colorCode >> 16);
    greenByte = (unsigned char)(colorCode >> 8);
    blueByte = (unsigned char)(colorCode); // masks off high bits

    result = [NSColor
    colorWithCalibratedRed:(CGFloat)redByte / 0xff
    green:(CGFloat)greenByte / 0xff
    blue:(CGFloat)blueByte / 0xff
    alpha:1.0];
    return result;
}

@end
