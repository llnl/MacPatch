//
//  MPClientInfo.m
//  MPLibrary
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

#import "MPClientInfo.h"
#import "MPSettings.h"
#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/sysctl.h>

#undef  ql_component
#define ql_component lcl_cMPClientInfo

@interface MPClientInfo ()
{
    NSFileManager   *fm;
    MPSettings      *settings;
}

@end

@implementation MPClientInfo

- (id)init
{
    self = [super init];
    if (self)
    {
        fm       = [NSFileManager defaultManager];
        settings = [MPSettings sharedInstance];
    }
    return self;
}

- (NSString *)patchGroupRev
{
    fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:PATCH_GROUP_PATCHES_PLIST])
    {
        NSString *pGroup = settings.agent.patchGroup;
        NSDictionary *_dict = [NSDictionary dictionaryWithContentsOfFile:PATCH_GROUP_PATCHES_PLIST];
        NSDictionary *patchGroupDict;
        if ([_dict objectForKey:pGroup])
        {
            patchGroupDict = [_dict objectForKey:pGroup];
            if ([patchGroupDict objectForKey:@"rev"]) {
                qldebug(@"Patch Group Rev ID is %@",[patchGroupDict objectForKey:@"rev"]);
                return [patchGroupDict objectForKey:@"rev"];
            } else {
                qlerror(@"Patch Group Patches file did not contain the rev key.");
            }
        }
    }
    
    return @"-1";
}

- (NSDictionary *)agentData
{
    NSMutableDictionary *agentDict;
    @try
    {
        NSDictionary *consoleUserDict = [MPSystemInfo consoleUserData];
        NSDictionary *hostNameDict = [MPSystemInfo hostAndComputerNames];
        
        NSDictionary *agentVer = nil;
        if ([fm fileExistsAtPath:AGENT_VER_PLIST]) {
            if ([fm isReadableFileAtPath:AGENT_VER_PLIST] == NO ) {
                [fm setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0664UL] forKey:NSFilePosixPermissions]
                     ofItemAtPath:AGENT_VER_PLIST
                            error:NULL];
            }
            agentVer = [NSDictionary dictionaryWithContentsOfFile:AGENT_VER_PLIST];
        } else {
            agentVer = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"NA",@"NA",@"NA",@"NA",@"NA",@"NA",nil]
                                                   forKeys:[NSArray arrayWithObjects:@"version",@"major",@"minor",@"bug",@"build",@"framework",nil]];
        }
        
        agentDict = [[NSMutableDictionary alloc] init];
        [agentDict setObject:[settings ccuid] forKey:@"cuuid"];
        [agentDict setObject:[settings serialno] forKey:@"serialno"];
        [agentDict setObject:hostNameDict[@"localHostName"] forKey:@"hostname"];
        [agentDict setObject:hostNameDict[@"localComputerName"] forKey:@"computername"];
        [agentDict setObject:consoleUserDict[@"consoleUser"] forKey:@"consoleuser"];
        [agentDict setObject:[MPSystemInfo getIPAddress] forKey:@"ipaddr" defaultObject:@"0.0.0.0"];
		[agentDict setObject:[MPSystemInfo getMacAddressForInterface:@"en0"] forKey:@"macaddr" defaultObject:@"00:00:00:00:00:00"];
        [agentDict setObject:[settings osver] forKey:@"osver" defaultObject:@"NA"];
        [agentDict setObject:[settings ostype] forKey:@"ostype" defaultObject:@"NA"];
        [agentDict setObject:@"0" forKey:@"agent_version"];
        [agentDict setObject:agentVer[@"build"] forKey:@"agent_build"];
		[agentDict setObject:@"0" forKey:@"client_version"];
        NSString *aVer = [NSString stringWithFormat:@"%@.%@.%@",agentVer[@"major"],agentVer[@"minor"],agentVer[@"bug"]];
		NSString *cVer = [NSString stringWithFormat:@"%@.%@.%@.%@",agentVer[@"major"],agentVer[@"minor"],agentVer[@"bug"],agentVer[@"build"]];
        [agentDict setObject:aVer forKey:@"agent_version"];
		[agentDict setObject:cVer forKey:@"client_version"];
        [agentDict setObject:@"false" forKey:@"needsreboot"];
		[agentDict setObject:[self fileVaultStatus] forKey:@"fileVault"];
		[agentDict setObject:[self hwModel] forKey:@"model"];
		[agentDict setObject:[MPPatching isPatchingForHostIsPausedAsString] forKey:@"hasPausedPatching" defaultObject:@"0"];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/tmp/.MPAuthRun"]) {
            [agentDict setObject:@"true" forKey:@"needsreboot"];
        }
        
        logit(lcl_vDebug, @"Agent Data: %@",agentDict);
        return (NSDictionary *)agentDict;
    }
    @catch (NSException * e) {
        logit(lcl_vError,@"[NSException]: %@",e);
        logit(lcl_vError,@"No client checkin data will be posted.");
        return nil;
    }
}

- (NSString *)fileVaultStatus
{
	@autoreleasepool {
		NSTask *task = [[NSTask alloc] init];
		[task setLaunchPath:@"/usr/bin/fdesetup"];
		[task setArguments:[NSArray arrayWithObjects:@"status", nil]];
		
		NSPipe *pipe = [NSPipe pipe];
		[task setStandardOutput: pipe];
		
		NSFileHandle *file = [pipe fileHandleForReading];
		[task launch];
		
		NSData *data = [file readDataToEndOfFile];
		NSString *string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
		
		return string;
	}
}

- (NSString *)hwModel
{
	size_t len = 0;
	sysctlbyname("hw.model", NULL, &len, NULL, 0);
	
	if (len)
	{
		char *model = malloc(len*sizeof(char));
		sysctlbyname("hw.model", model, &len, NULL, 0);
		NSString *model_ns = [NSString stringWithUTF8String:model];
		free(model);
		return model_ns;
	}
	
	return @"Macintosh"; //incase model name can't be read
}
@end
