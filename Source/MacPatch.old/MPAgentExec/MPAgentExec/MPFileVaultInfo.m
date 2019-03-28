//
//  MPFileVaultInfo.m
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
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

#import "MPFileVaultInfo.h"
#include <unistd.h>

@interface MPFileVaultInfo ()

@property (nonatomic, assign, readwrite) int state;
@property (nonatomic, strong, readwrite) NSString *status;
@property (nonatomic, strong, readwrite) NSString *users;
@property (nonatomic, strong, readwrite) NSError *error;

- (int)currentUserID;
- (void)runFDESetupCommand:(NSString *)argument;
- (void)parseUsersOutput:(NSString *)aString;
@end

@implementation MPFileVaultInfo

@synthesize status = _status;
@synthesize users = _users;
@synthesize error = _error;

- (id)init
{
    self = [super init];
    if (self)
    {
        //[self setError:nil];
        _error = nil;

        [self setUsers:@"na"];
        [self setState:-1];
        [self setStatus:@"na"];

        [self refresh];
    }
    return self;
}

- (void)refresh
{
    if (floor(NSAppKitVersionNumber) < 1162) {
        /* earlier than 10.8 system */
        NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
        [errorDetail setValue:@"FileVault Inventory Requires 10.8 and higher." forKey:NSLocalizedDescriptionKey];
        //[self setError:[NSError errorWithDomain:@"myDomain" code:200 userInfo:errorDetail]];
        _error = [NSError errorWithDomain:@"myDomain" code:200 userInfo:errorDetail];
        [self setStatus:@"FileVault Inventory Requires 10.8 and higher."];
        return;
    }
    
    if ([self currentUserID] == 0) {
        [self runFDESetupCommand:@"isactive"];
        [self runFDESetupCommand:@"status"];
        [self runFDESetupCommand:@"list"];
    } else {
        NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
        [errorDetail setValue:@"FileVault Inventory Requires Root Access." forKey:NSLocalizedDescriptionKey];
        //[self setError:[NSError errorWithDomain:@"myDomain" code:100 userInfo:errorDetail]];
        _error = [NSError errorWithDomain:@"myDomain" code:100 userInfo:errorDetail];
        return;
    }
}

- (int)currentUserID
{
    uid_t uid;
    uid = getuid();
    return (int)uid;
}

- (void)runFDESetupCommand:(NSString *)argument
{
    NSTask *task = [NSTask new];
    NSPipe *pipe = [NSPipe new];
    
    [task setStandardOutput:pipe];
    [task setLaunchPath:@"/usr/bin/fdesetup"];
    [task setArguments:[NSArray arrayWithObject:argument]];
    [task launch];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    
    if ([task terminationStatus] == 0) {
        if ([argument isEqualToString:@"isactive"]) {
            [self setState:1];
            return;
        }
    } else {
        if ([argument isEqualToString:@"isactive"]) {
            [self setState:0];
            return;
        }
    }

    if (data == nil) {
        return;
    }

    NSString *results = [[NSString alloc] initWithData:data encoding: NSUTF8StringEncoding];
    if ([argument isEqualToString:@"status"]) {
        [self setStatus:results];
        return;
    }
    if ([argument isEqualToString:@"list"]) {
        [self parseUsersOutput:results];
        return;
    }
    
}

- (void)parseUsersOutput:(NSString *)aString;
{
    //smith1,286A5B18-32C0-4C1B-B69D-2C4D6B5FD110
    //local,94188C0B-5535-4195-B534-372ABB1E0CAB
    @try {
        NSMutableArray *newData = [NSMutableArray array];
        NSMutableArray *data = (NSMutableArray *)[aString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (int i = 0; i < [data count]; i++)
        {
            qldebug(@"Parsing %@",[data objectAtIndex:i]);
            [newData addObject:[[[data objectAtIndex:i] componentsSeparatedByString: @","] objectAtIndex:0]];
        }
        
        [self setUsers:[newData componentsJoinedByString:@","]];
    }
    @catch (NSException *exception) {
        qlerror(@"%@",exception);
    }
}


@end
