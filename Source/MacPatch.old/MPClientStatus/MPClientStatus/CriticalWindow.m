//
//  CriticalWindow.m
//  MPClientStatus
//
//  Created by Charles Heizer on 4/24/18.
//  Copyright © 2018 LLNL. All rights reserved.
//

#import "CriticalWindow.h"



@implementation CriticalWindow

- (BOOL) canBecomeKeyWindow { return YES; }
- (BOOL) canBecomeMainWindow { return YES; }
- (BOOL) acceptsFirstResponder { return YES; }
- (BOOL) becomeFirstResponder { return YES; }
- (BOOL) resignFirstResponder { return YES; }

@end
