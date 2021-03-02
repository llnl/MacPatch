//
//  MPSWTasks.m
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "MPSWTasks.h"
#import "MPRESTfull.h"
#import "MPSettings.h"

@interface MPSWTasks ()
{
    MPSettings *settings;
}

@end

@implementation MPSWTasks

@synthesize groupHash;
@synthesize groupName;

- (id)init
{
    return [self initWithGroupAndHash:nil hash:@"NA"];
}

- (id)initWithGroupAndHash:(NSString *)aGroup hash:(NSString *)aHash;
{
    self = [super init];
    if (self)
    {
        settings = [MPSettings sharedInstance];
        
        if (aGroup)
        {
            [self setGroupName:aGroup];
        }
        else
        {
            [self setGroupName:settings.agent.swDistGroup];
        }    
        [self setGroupHash:aHash];
    }
    return self;
}


- (void)main 
{
    return;
}

- (NSArray *)getSoftwareTasksForGroup:(NSError **)err
{
    NSArray *result = [NSArray array];
    NSError *error = nil;
    MPRESTfull *mprest = [[MPRESTfull alloc] init];
    result = [mprest getSoftwareTasksForGroup:self.groupName error:&error];
    if (error)
    {
        if (err != NULL) {
            *err = error;
        } else {
            qlerror(@"%@",error.localizedDescription);
        }
    }
    return result;
}

- (int)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict
{
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:@"json" forKey:@"type"];
    [params setObject:[MPSystemInfo clientUUID] forKey:@"ClientID"];
    [params setObject:[taskDict objectForKey:@"id"] forKey:@"SWTaskID"];
    [params setObject:[taskDict valueForKeyPath:@"Software.sid"] forKey:@"SWDistID"];
    [params setObject:[NSNumber numberWithInt:resultNo] forKey:@"ResultNo"];
    [params setObject:[NSNumber numberWithInt:resultNo] forKey:@"result"];
    [params setObject:resultString forKey:@"ResultString"];
    [params setObject:@"i" forKey:@"Action"];

    BOOL result = NO;
    NSError *error = nil;
    MPRESTfull *mprest = [[MPRESTfull alloc] init];
    result = [mprest postSoftwareInstallResults:(NSDictionary *)params error:&error];
    if (error) {
        qlerror(@"%@",error.localizedDescription);
        return 1;
    }
    
    qldebug(@"[MPSWTasks][postUnInstallResults]: %d",(result ? 0:1));
    return (result ? 0:1);
}

- (int)postUnInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict
{
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:@"json" forKey:@"type"];
    [params setObject:[MPSystemInfo clientUUID] forKey:@"ClientID"];
    [params setObject:[taskDict objectForKey:@"id"] forKey:@"SWTaskID"];
    [params setObject:[taskDict valueForKeyPath:@"Software.sid"] forKey:@"SWDistID"];
    [params setObject:[NSNumber numberWithInt:resultNo] forKey:@"ResultNo"];
    [params setObject:[NSNumber numberWithInt:resultNo] forKey:@"result"];
    [params setObject:resultString forKey:@"ResultString"];
    [params setObject:@"u" forKey:@"Action"];


    BOOL result = NO;
    NSError *error = nil;
    MPRESTfull *mprest = [[MPRESTfull alloc] init];
    result = [mprest postSoftwareInstallResults:(NSDictionary *)params error:&error];
    if (error) {
        qlerror(@"%@",error.localizedDescription);
        return 1;
    }
    
    qldebug(@"[MPSWTasks][postUnInstallResults]: %d",(result ? 0:1));
    return (result ? 0:1);
}

@end
