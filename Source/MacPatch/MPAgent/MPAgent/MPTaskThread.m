//
//  MPTaskThread.m
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

#import "MPTaskThread.h"
#import "MPDefaultsWatcher.h"
#import "MacPatch.h"

#define CLIENT_VER_FILE		@"/Library/MacPatch/Client/.mpVersion.plist"

NSLock *lock;

@implementation MPTaskThread

+ (void)runTask:(id)param
{
    @autoreleasepool {   
    
		@try {
			NSDictionary *l_task = (NSDictionary *)param;
			NSString *l_cmd = [l_task objectForKey:@"cmd"];
			
			if ([l_cmd isEqualToString:@"kMPCheckIn"]) {
				logit(lcl_vInfo,@"Running client check in.");
				[self runCheckIn];
				logit(lcl_vInfo,@"Running client check in completed.");
				
			} else if ([l_cmd isEqualToString:@"kMPAgentCheck"]) {
				logit(lcl_vInfo,@"Running agent check.");
				[self runAgentScanAndUpdate];
				
			} else if ([l_cmd isEqualToString:@"kMPVulScan"]) {
				logit(lcl_vInfo,@"Running client vulnerability scan.");
				[self runPatchScan];
				
			} else if ([l_cmd isEqualToString:@"kMPVulUpdate"]) {
				logit(lcl_vInfo,@"Running client vulnerability update.");
				[self runPatchScanAndUpdate];
				
			} else if ([l_cmd isEqualToString:@"kMPAVCheck"]) {
				logit(lcl_vInfo,@"Running client AV scan and update.");
				[self runAVInfoScanAndDefsUpdate];

			} else if ([l_cmd isEqualToString:@"kMPCMD"]) {
				logit(lcl_vInfo,@"Running custom client command.");
				//[self ];
            
			} else if ([l_cmd isEqualToString:@"kMPProfiles"]) {
				logit(lcl_vInfo,@"Running client inventory scan.");
				//[self ];
            
            } else if ([l_cmd isEqualToString:@"kMPSrvList"]) {
                logit(lcl_vInfo,@"Running Server List scan and update.");
                //[self ];
                
            } else if ([l_cmd isEqualToString:@"kMPSUSrvList"]) {
                logit(lcl_vInfo,@"Running SU Server List scan and update.");
                //[self ];

            } else if ([l_cmd isEqualToString:@"kMPPatchCrit"]) {
                logit(lcl_vInfo,@"Running Critical Patch Scan and Update");
                //[self ];
                
			} else {
				// Do nothing, log invalid command
				logit(lcl_vWarning,@"Invalid command (%@) attempted.",l_cmd);
			}
		}
		@catch (NSException * e) {
			logit(lcl_vError,@"Error running task, %@",e);
		}	
    
    }
}

+ (void)runCheckIn
{
    @autoreleasepool
    {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableDictionary *agentDict;
        MPAgent *si = [MPAgent sharedInstance];
        
        @try {
            NSDictionary *consoleUserDict = [MPSystemInfo consoleUserData];
            NSDictionary *hostNameDict = [MPSystemInfo hostAndComputerNames];
            
            NSDictionary *clientVer = nil;
            if ([fm fileExistsAtPath:CLIENT_VER_FILE]) {
                if ([fm isReadableFileAtPath:CLIENT_VER_FILE] == NO ) {
                    [fm setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:0664UL] forKey:NSFilePosixPermissions] 
                         ofItemAtPath:CLIENT_VER_FILE 
                                error:NULL];
                }
                clientVer = [NSDictionary dictionaryWithContentsOfFile:CLIENT_VER_FILE];	
            } else {
                clientVer = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"NA",@"NA",@"NA",@"NA",@"NA",@"NA",nil] 
                                                        forKeys:[NSArray arrayWithObjects:@"version",@"major",@"minor",@"bug",@"build",@"framework",nil]];
            }
                                       
            agentDict = [[NSMutableDictionary alloc] init];
            [agentDict setObject:[si g_cuuid] forKey:@"cuuid"];
            [agentDict setObject:[si g_serialNo] forKey:@"serialno"];
            [agentDict setObject:[hostNameDict objectForKey:@"localHostName"] forKey:@"hostname"];
            [agentDict setObject:[hostNameDict objectForKey:@"localComputerName"] forKey:@"computername"];
            [agentDict setObject:[consoleUserDict objectForKey:@"consoleUser"] forKey:@"consoleUser"];
            [agentDict setObject:[MPSystemInfo getIPAddress] forKey:@"ipaddr"];
            [agentDict setObject:[MPSystemInfo getMacAddressForInterface:@"en0"] forKey:@"macaddr"];
            [agentDict setObject:[si g_osVer] forKey:@"osver"];
            [agentDict setObject:[si g_osType] forKey:@"ostype"];
            [agentDict setObject:[si g_agentVer] forKey:@"agent_version"];
            [agentDict setObject:[clientVer objectForKey:@"build"] forKey:@"agent_build"];
            [agentDict setObject:[clientVer objectForKey:@"version"] forKey:@"client_version"];
            [agentDict setObject:@"false" forKey:@"needsreboot"];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHRUN_FILE]) {
                [agentDict setObject:@"true" forKey:@"needsreboot"];	
            }
        }
        @catch (NSException * e) 
        {
            logit(lcl_vError,@"[NSException]: %@",e);
            logit(lcl_vError,@"No client checkin data will be posted.");
            return;
        }
        
        MPWebServices *mpws = [[MPWebServices alloc] init];
        mpws.clientKey = [[MPAgent sharedInstance] g_clientKey];
        
        NSError *err = nil;
        BOOL postResult = NO;
        NSString *uri;
        NSData *reqData;
        id postRes;
        @try {
            // Send Checkin Data
            err = nil;
            uri = [@"/api/v1/client/checkin" stringByAppendingPathComponent:[si g_cuuid]];
            reqData = [mpws postRequestWithURIforREST:uri body:agentDict error:&err];
            if (err) {
                logit(lcl_vError,@"%@",[err localizedDescription]);
            } else {
                // Parse JSON result, if error code is not 0
                err = nil;
                postRes = [mpws returnRequestWithType:reqData resultType:@"string" error:&err];
                logit(lcl_vDebug,@"%@",postRes);
                if (err) {
                    logit(lcl_vError,@"%@",[err localizedDescription]);
                } else {
                    postResult = YES;
                }
            }
            
            if (postResult) {
                logit(lcl_vInfo,@"Running client base checkin, returned true.");
            } else {
                logit(lcl_vError,@"Running client base checkin, returned false.");
            }
        }
        @catch (NSException * e) {
            logit(lcl_vError,@"[NSException]: %@",e);
        }
        
        // Read Client Plist Info, and post it...
        @try {
            MPDefaultsWatcher *mpd = [[MPDefaultsWatcher alloc] init];
            NSMutableDictionary *mpDefaults = [[NSMutableDictionary alloc] initWithDictionary:[mpd readConfigPlist]];
            [mpDefaults setObject:[si g_cuuid] forKey:@"cuuid"];
            
            logit(lcl_vDebug, @"Agent Plist: %@",mpDefaults);
            
            err = nil;
            uri = [@"/api/v1/client/checkin/plist" stringByAppendingPathComponent:[si g_cuuid]];
            reqData = [mpws postRequestWithURIforREST:uri body:mpDefaults error:&err];
            if (err) {
                logit(lcl_vError,@"%@",[err localizedDescription]);
            } else {
                // Parse JSON result, if error code is not 0
                err = nil;
                postRes = [mpws returnRequestWithType:reqData resultType:@"string" error:&err];
                logit(lcl_vDebug,@"%@",postRes);
                if (err) {
                    logit(lcl_vError,@"%@",[err localizedDescription]);
                } else {
                    postResult = YES;
                }
            }
            
            if (postResult) {
                logit(lcl_vInfo,@"Running client config checkin, returned true.");
            } else {
                logit(lcl_vError,@"Running client config checkin, returned false.");
            }
        }
        @catch (NSException * e) {
            logit(lcl_vError,@"[NSException]: %@",e);
        }
    }
}

+ (void)runPatchScan 
{
    [MPTaskThread runExecTaskUsingArgs:[NSArray arrayWithObject:@"-s"]];
    logit(lcl_vInfo,@"Vulnerability scan has been completed.");
    logit(lcl_vInfo,@"See the MPAgentExec.log file for more information.");
}

+ (void)runPatchScanAndUpdate
{
    [MPTaskThread runExecTaskUsingArgs:[NSArray arrayWithObject:@"-u"]];
    logit(lcl_vInfo,@"Vulnerability scan & update has been completed.");
    logit(lcl_vInfo,@"See the MPAgentExec.log file for more information.");
}

+ (void)runAVInfoScan
{
    [MPTaskThread runExecTaskUsingArgs:[NSArray arrayWithObject:@"-a"]];
    logit(lcl_vInfo,@"AV info collection has been completed.");
    logit(lcl_vInfo,@"See the MPAgentExec.log file for more information.");
}

+ (void)runAVInfoScanAndDefsUpdate
{
    [MPTaskThread runExecTaskUsingArgs:[NSArray arrayWithObject:@"-U"]];
    logit(lcl_vInfo,@"AV inventory and defs update has been completed.");
    logit(lcl_vInfo,@"See the MPAgentExec.log file for more information.");
}

+ (void)runAgentScanAndUpdate
{
    [MPTaskThread runExecTaskUsingArgs:[NSArray arrayWithObject:@"-G"]];
    logit(lcl_vInfo,@"Update Up2Date has been completed.");
    logit(lcl_vInfo,@"See the MPAgentExec.log file for more information.");
}

+ (void)runExecTaskUsingArgs:(NSArray *)aArgs
{
    @autoreleasepool
    {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *appPath = [MP_ROOT_CLIENT stringByAppendingPathComponent:@"MPAgentExec"];
        if (![fm fileExistsAtPath:appPath]) {
            logit(lcl_vError,@"Unable to find MPAgentExec app.");
            return;
        }

        if (![MPCodeSign checkSignature:appPath]) {
            return; // Not a valid signature, bail.
        }

        NSError *error = nil;
        NSString *result;
        MPNSTask *mpr = [[MPNSTask alloc] init];
        result = [mpr runTask:appPath binArgs:aArgs error:&error];

        if (error) {
            logit(lcl_vError,@"%@",[error description]);
        }

        logit(lcl_vDebug,@"%@",result);
    }
}

@end
