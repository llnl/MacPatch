//
//  MPCustomPatch.m
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

#import "MPCustomPatch.h"

@implementation MPCustomPatch

@synthesize cuuid;
@synthesize patch;
@synthesize type;
@synthesize description;
@synthesize size;
@synthesize recommended;
@synthesize restart;
@synthesize version;
@synthesize patch_id;
@synthesize bundleID;

- (id)init
{
    self = [super init];
    if (self)
    {
        [self setCuuid:@""];
        [self setPatch:@""];
        [self setType:@"Third"];
        [self setDescription:@""];
        [self setSize:@"0"];
        [self setRecommended:@"Y"];
        [self setRestart:@""];
        [self setVersion:@""];
        [self setPatch_id:@""];
        [self setBundleID:@""];
    }
    return self;
}

- (NSDictionary *)patchAsDictionary
{
    // cuuid, patch, type, description, size, recommended, restart, patch_id, version, bundleID
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:self.cuuid forKey:@"cuuid"];
    [p setObject:self.patch forKey:@"patch"];
    [p setObject:self.type forKey:@"type"];
    [p setObject:self.description forKey:@"description"];
    [p setObject:self.size forKey:@"size"];
    [p setObject:self.recommended forKey:@"recommended"];
    [p setObject:self.restart forKey:@"restart"];
    [p setObject:self.version forKey:@"version"];
    [p setObject:self.patch_id forKey:@"patch_id"];
    [p setObject:self.bundleID forKey:@"bundleID"];
    return (NSDictionary *)p;
}


@end
