//
//  MPFirmware.m
//  MPAgent
//
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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

#import "MPFirmware.h"

@interface MPFirmware ()

@property (nonatomic, assign, readwrite) int state;
@property (nonatomic, strong, readwrite) NSString *mode;
@property (nonatomic, strong, readwrite) NSString *options;
@property (nonatomic, strong, readwrite) NSString *status;
@property (nonatomic, strong, readwrite) NSError *error;

- (int)queryFirmwarePasswordState;
- (void)queryFirmwarePasswordMode;

@end

@implementation MPFirmware

@synthesize mode    = _mode;
@synthesize options = _options;
@synthesize status  = _status;
@synthesize error   = _error;

- (id)init
{
    self = [super init];
    if (self)
    {
        _error = nil;
        
        [self setState:-1];
        [self setStatus:@"na"];
        [self setMode:@"na"];
        [self setOptions:@"na"];
        
        [self refresh];
    }
    return self;
}

- (void)refresh
{
    if (floor(NSAppKitVersionNumber) < 1343) {
        /* earlier than 10.8 system */
        NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
        [errorDetail setValue:@"Firmware Password Inventory Requires 10.10 and higher." forKey:NSLocalizedDescriptionKey];
        _error = [NSError errorWithDomain:@"myDomain" code:200 userInfo:errorDetail];
        [self setStatus:@"Firmware Password Inventory Requires 10.10 and higher."];
        return;
    }
    
    [self setState:[self queryFirmwarePasswordState]];
    [self queryFirmwarePasswordMode];
}

- (int)queryFirmwarePasswordState
{
    NSTask *task = [NSTask new];
    NSPipe *pipe = [NSPipe new];
    
    [task setStandardOutput:pipe];
    [task setLaunchPath:@"/usr/sbin/firmwarepasswd"];
    [task setArguments:@[@"-check"]];
    [task launch];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    
    if ([task terminationStatus] != 0) {
        return -1;
    }
    
    if (data == nil) {
        return -1;
    }
    
    NSString *results = [[NSString alloc] initWithData:data encoding: NSUTF8StringEncoding];
    if ([results.lowercaseString isEqualToString:[@"Password Enabled: No" lowercaseString]]) {
        return 0;
    }
    if ([results.lowercaseString isEqualToString:[@"Password Enabled: Yes" lowercaseString]]) {
        return 1;
    }
    
    return -1;
}

- (void)queryFirmwarePasswordMode
{
    NSTask *task = [NSTask new];
    NSPipe *pipe = [NSPipe new];
    
    [task setStandardOutput:pipe];
    [task setLaunchPath:@"/usr/sbin/firmwarepasswd"];
    [task setArguments:@[@"-mode"]];
    [task launch];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    
    if ([task terminationStatus] != 0) {
        return;
    }
    
    if (data == nil) {
        return;
    }
    
    NSString *results = [[NSString alloc] initWithData:data encoding: NSUTF8StringEncoding];
    NSString *trimStr0 = [[results componentsSeparatedByString: @"\n"] objectAtIndex:0];
    NSString *trimStr1 = [[results componentsSeparatedByString: @"\n"] objectAtIndex:1];
    NSString *result = [trimStr0 stringByReplacingOccurrencesOfString:@"Mode: " withString:@""];
    [self setMode:result];
    [self setOptions:trimStr1];
    return;
}

@end
