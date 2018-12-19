//
//  MPClientInfo.m
//  MPLibrary
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

#import "MPClientInfo.h"
#import "MPSettings.h"

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
		NSDictionary *activeNetData = [MPSystemInfo activeInterfaceData];
        
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
        [agentDict setObject:[hostNameDict objectForKey:@"localHostName"] forKey:@"hostname"];
        [agentDict setObject:[hostNameDict objectForKey:@"localComputerName"] forKey:@"computername"];
        [agentDict setObject:[consoleUserDict objectForKey:@"consoleUser"] forKey:@"consoleuser"];
		[agentDict setObject:activeNetData[@"ipAddr"] forKey:@"ipaddr"];
		[agentDict setObject:activeNetData[@"macAddr"] forKey:@"macaddr"];
        [agentDict setObject:[settings osver] forKey:@"osver"];
        [agentDict setObject:[settings ostype] forKey:@"ostype"];
        [agentDict setObject:@"0" forKey:@"agent_version"];
        [agentDict setObject:[agentVer objectForKey:@"build"] forKey:@"agent_build"];
        NSString *aVer = [NSString stringWithFormat:@"%@.%@.%@",[agentVer objectForKey:@"major"],[agentVer objectForKey:@"minor"],[agentVer objectForKey:@"bug"]];
		NSString *cVer = [NSString stringWithFormat:@"%@.%@.%@.%@",[agentVer objectForKey:@"major"],[agentVer objectForKey:@"minor"],[agentVer objectForKey:@"bug"],[agentVer objectForKey:@"build"]];
        [agentDict setObject:aVer forKey:@"agent_version"];
		[agentDict setObject:cVer forKey:@"client_version"];
        [agentDict setObject:@"false" forKey:@"needsreboot"];
		[agentDict setObject:[self fileVaultStatus] forKey:@"fileVaultStatus"];
		[agentDict setObject:[self firmwareStatus] forKey:@"firmwareStatus"];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHRUN_FILE])
		{
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
		
		return [string trim];
	}
}

- (NSString *)firmwareStatus
{
	@autoreleasepool
	{
		if (NSAppKitVersionNumber <= NSAppKitVersionNumber10_10)
		{
			// We are not running on Yosemite
			return @"Password Enabled: OS Not Supported";
			
		} else {
			
			NSTask *task = [[NSTask alloc] init];
			[task setLaunchPath:@"/usr/sbin/firmwarepasswd"];
			[task setArguments:[NSArray arrayWithObjects:@"-check", nil]];
			
			NSPipe *pipe = [NSPipe pipe];
			[task setStandardOutput: pipe];
			
			NSFileHandle *file = [pipe fileHandleForReading];
			[task launch];
			
			NSData *data = [file readDataToEndOfFile];
			NSString *string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
			logit(lcl_vDebug, @"[firmwarepasswd][check]: %@",string);
			
			if ([[string trim].lowercaseString isEqualToString:[@"Password Enabled: No" lowercaseString]]) {
				return [string trim];
			} else if ([[string trim].lowercaseString isEqualToString:[@"Password Enabled: Yes" lowercaseString]]) {
				return [string trim];
			} else {
				return @"Error: Collection failed.";
			}
		}
	}
}

@end
