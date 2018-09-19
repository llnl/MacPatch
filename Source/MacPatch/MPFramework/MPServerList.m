//
//  MPServerList.m
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import "MPServerList.h"

@interface MPServerList ()

@end

@implementation MPServerList

#pragma mark - Init

- (id)init
{
    self = [super init];
    if (self) {
        fm = [NSFileManager defaultManager];
    }
    return self;
}

#pragma mark - Class Methods

- (NSDictionary *)readServerPlistFromHost
{
    if ([fm fileExistsAtPath:AGENT_SERVERS_PLIST])
    {
        NSDictionary *_curFile = [NSDictionary dictionaryWithContentsOfFile:AGENT_SERVERS_PLIST];
        return _curFile;
    }
    return nil;
}

- (NSArray *)getLocalServerArray
{
    NSDictionary *_dict = [self readServerPlistFromHost];
    NSArray *servers = [NSArray array];
    if ([_dict objectForKey:@"servers"]) {
        if ([[_dict objectForKey:@"servers"] count] >= 1) {
            servers = [[_dict objectForKey:@"servers"] copy];
        }
    }
    return servers;
}
                     
- (NSArray *)randomizeArray:(NSArray *)arrayToRandomize
{
    NSMutableArray *_newArray = [[NSMutableArray alloc] initWithArray:arrayToRandomize];
    NSUInteger count = [_newArray count];
    for (NSUInteger i = 0; i < count; ++i) {
        // Select a random element between i and end of array to swap with.
        NSInteger nElements = count - i;
        NSInteger n = (arc4random() % nElements) + i;
        [_newArray exchangeObjectAtIndex:i withObjectAtIndex:n];
    }
    
    return (NSArray *)_newArray;
}

@end
