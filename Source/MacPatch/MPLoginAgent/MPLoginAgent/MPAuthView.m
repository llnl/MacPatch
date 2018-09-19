//
//  MPAuthView.m
//  MPAuthPlugin
//
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.

 This file is part of MacPatch, a program for installing and patching
 software.

 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.

 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.

 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#import "MPAuthView.h"

@implementation MPAuthView

- (BOOL) canBecomeKeyWindow { return YES; }
- (BOOL) canBecomeMainWindow { return YES; }
- (BOOL) acceptsFirstResponder { return YES; }
- (BOOL) becomeFirstResponder { return YES; }
- (BOOL) resignFirstResponder { return YES; }

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        // self.wantsLayer = YES;
        // self.layer.frame = self.frame;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Round the Corners
    //self.layer.cornerRadius = 10.0;
    //self.layer.masksToBounds = YES;

    // Draw the Gradient
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor gridColor] endingColor:[NSColor blackColor]];
    [gradient drawFromPoint: NSMakePoint(0,0)
                    toPoint: NSMakePoint(0,560)
                    options: NSGradientDrawsAfterEndingLocation
     ];
}

@end
