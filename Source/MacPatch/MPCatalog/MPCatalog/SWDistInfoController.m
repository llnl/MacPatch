//
//  SWDistInfoController.m
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

#import "SWDistInfoController.h"

@interface IntToBOOLStringValueTransformer: NSValueTransformer
{
    
}
@end

@implementation IntToBOOLStringValueTransformer

- (id)init
{
    if (self = [super init]) 
    {
        
    }
    return self;
}


+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value 
{
    return ([value intValue] ? @"True" : @"False");
}
@end

@interface TaskTypeValueTransformer: NSValueTransformer
{
    
}
@end

@implementation TaskTypeValueTransformer

- (id)init
{
    if (self = [super init]) 
    {
        
    }
    return self;
}


+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value 
{
    NSString *x = [NSString stringWithFormat:@"%@",value];
    if ([[x uppercaseString] isEqualToString:@"O"]) {
      return @"Optional";  
    }
    if ([[x uppercaseString] isEqualToString:@"M"]) {
        return @"Mandatory";  
    }
    if ([[x uppercaseString] isEqualToString:@"OM"]) {
        return @"Optional/Mandatory";  
    }
    return @"";
    //return ([value intValue] ? @"True" : @"False");
}
@end

@interface SWDistInfoController ()

- (IBAction)closeIt:(id)sender;

@end

@implementation SWDistInfoController

@synthesize swDistInfoPanelDict;

- (id)init
{
    self = [super initWithWindowNibName:@"SWDistInfoController"];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [self.window center];
}

- (IBAction)closeIt:(id)sender
{
    [self close];
}

@end
