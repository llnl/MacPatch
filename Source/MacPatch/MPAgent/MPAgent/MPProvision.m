//
//  MPProvision.m
//  MPAgent
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

#import "MPProvision.h"
#import "MacPatch.h"
#import "SoftwareController.h"

@interface MPProvision()
{
    NSFileManager *fm;
}
- (NSDictionary *)getProvisionData;

@end

@implementation MPProvision

- (id)init
{
    self = [super init];
    if (self)
    {
        fm = [NSFileManager defaultManager];
    }
    return self;
}

- (int)provisionHost
{
    int res = 0;
    
    [self writeToKeyInProvisionFile:@"startDT" data:[MPDate dateTimeStamp]];
    [self writeToKeyInProvisionFile:@"stage" data:@"getData"];
    [self writeToKeyInProvisionFile:@"completed" data:[NSNumber numberWithBool:NO]];
    
    // Get Data
    NSDictionary *provisionData = [self getProvisionData];
    if (!provisionData) {
        qlerror(@"Provisioning data from web service is nil. Now exiting.");
        res = 1;
        [self writeToKeyInProvisionFile:@"endDT" data:[MPDate dateTimeStamp]];
        [self writeToKeyInProvisionFile:@"completed" data:[NSNumber numberWithBool:YES]];
        [self writeToKeyInProvisionFile:@"failed" data:[NSNumber numberWithBool:YES]];
        return res;
    } else {
        // Write Provision Data to File
        [self writeToKeyInProvisionFile:@"data" data:provisionData];
    }
    
    // Run Pre Scripts
    [self writeToKeyInProvisionFile:@"stage" data:@"preScripts"];
    NSArray *_pre = provisionData[@"scriptsPre"];
    if (_pre) {
        if (_pre.count >= 1) {
            for (NSDictionary *s in _pre)
            {
                LogInfo(@"Pre Script: %@",s[@"name"]);
                @try {
                    MPScript *scp = [MPScript new];
                    [scp runScript:s[@"script"]];
                } @catch (NSException *exception) {
                    qlerror(@"[PreScript]: %@",exception);
                }
                
            }
        } else {
            LogInfo(@"No, pre scripts to run.");
        }
    }
    
    // Run Software Tasks
    [self writeToKeyInProvisionFile:@"stage" data:@"Software"];
    NSArray *_sw = provisionData[@"tasks"];
    if (_sw) {
        if (_sw.count >= 1) {
            for (NSDictionary *s in _sw)
            {
                LogInfo(@"Install Software Task: %@",s[@"name"]);
                @try {
                    SoftwareController *mps = [SoftwareController new];
                    [mps installSoftwareTask:s[@"tuuid"]];
                    if ([mps errorCode] != 0) {
                        [self writeToKeyInProvisionFile:@"status" data:[NSString stringWithFormat:@"Software: Failed to install %@ (%@)",s[@"name"],s[@"tuuid"]]];
                    }
                } @catch (NSException *exception) {
                    qlerror(@"[Software]: %@",exception);
                }
                
            }
        } else {
            LogInfo(@"No, software tasks to run.");
        }
    }
    
    // Run Post Scripts
    [self writeToKeyInProvisionFile:@"stage" data:@"postScripts"];
    NSArray *_post = provisionData[@"scriptsPost"];
    if (_post) {
        if (_post.count >= 1) {
            for (NSDictionary *s in _post)
            {
                LogInfo(@"Post Script: %@",s[@"name"]);
                @try {
                    MPScript *scp = [MPScript new];
                    [scp runScript:s[@"script"]];
                } @catch (NSException *exception) {
                    qlerror(@"[PostScript]: %@",exception);
                }
                
            }
        } else {
            LogInfo(@"No, post scripts to run.");
        }
    }
    
    
    return res;
}

- (int)provisionSetupAndConfig
{
    int result = 1;
    NSArray *provCriteria = [NSArray array];
    NSError *err = nil;
    
    MPRESTfull *mpr = [MPRESTfull new];
    provCriteria = [mpr getProvisioningCriteriaUsingScope:@"prod" error:&err];
    if (err) {
        qlerror(@"Error downloading provisioning criteria.");
        qlerror(@"%@",err.localizedDescription);
    } else {
        if (provCriteria.count >= 1)
        {
            MPBundle    *mpbndl;
            MPFileCheck *mpfile;
            MPScript    *mpscript;
            
            int count = 0; // Copunt must equal the array length for all to be true.
            // Loop vars
            /*
             typeQuery       = [qryArr objectAtIndex:1];
             typeQueryString = [qryArr objectAtIndex:2];
             typeResult      = [qryArr objectAtIndex:3];
             */
            
            for (NSDictionary *q in provCriteria)
            {
                LogDebug(@"Process %@",q);
                NSArray *qryArr = [[q objectForKey:@"qstr"] componentsSeparatedByString:@"@" escapeString:@"@@"];
                LogDebug(@"qryArr %@",qryArr);
                
                if ([@"BundleID" isEqualToString:[qryArr objectAtIndex:0]]) {
                    mpbndl = [[MPBundle alloc] init];
                    if ([qryArr count] != 4) {
                        qlerror(@"Error, not enough args for BundleID criteria query.");
                        continue;
                    }

                    if ([mpbndl queryBundleID:[qryArr objectAtIndex:2] action:[qryArr objectAtIndex:1] result:[qryArr objectAtIndex:3]]) {
                        LogInfo(@"BundleID=TRUE: %@",[qryArr objectAtIndex:1]);
                        count++;
                    } else {
                        LogInfo(@"BundleID=FALSE: %@",[qryArr objectAtIndex:1]);
                    }
                }
                
                if ([@"File" isEqualToString:[qryArr objectAtIndex:0]]) {
                    mpfile = [[MPFileCheck alloc] init];
                    if ([qryArr count] != 4) {
                        qlerror(@"Error, not enough args for File criteria query.");
                        continue;
                    }

                    if ([mpfile queryFile:[qryArr objectAtIndex:2] action:[qryArr objectAtIndex:1] param:[qryArr objectAtIndex:3]]) {
                        LogInfo(@"File=TRUE: %@",[qryArr objectAtIndex:1]);
                        count++;
                    } else {
                        LogInfo(@"File=FALSE: %@",[qryArr objectAtIndex:1]);
                    }
                }
                
                if ([@"Script" isEqualToString:[qryArr objectAtIndex:0]]) {
                    mpscript = [[MPScript alloc] init];
                    if ([qryArr count] > 2) {
                        qlerror(@"Error, too many args. Sript will not be run.");
                        continue;
                    }
                    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:[qryArr objectAtIndex:1] options:0];
                    NSString *decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                    LogDebug(@"Script: %@",decodedString);
                    if ([mpscript runScript:decodedString]) {
                        LogInfo(@"SCRIPT=TRUE");
                        count++;
                    } else {
                        LogInfo(@"SCRIPT=FALSE");
                    }
                }
            }
            LogDebug(@"provCriteria.count %lu == %d count",(unsigned long)provCriteria.count,count);
            if (provCriteria.count == count)
            {
                // Criteria is a pass, write .MPProvisionBegin file
                err = nil;
                [@"GO" writeToFile:MP_PROVISION_BEGIN atomically:NO encoding:NSUTF8StringEncoding error:&err];
                if (err) {
                    qlerror(@"Error writing %@ file.",MP_PROVISION_BEGIN);
                    qlerror(@"%@",err.localizedDescription);
                }
            }
        }
    }
    
    // This can be downloaded any time
    result = [self getProvisioningConfig];
    return result;
    
}

- (int)getProvisioningConfig
{
    NSString *configJSON = nil;
    NSError *err = nil;
    MPRESTfull *mpr = [MPRESTfull new];
    configJSON = [mpr getProvisioningConfig:&err];
    if (err) {
        qlerror(@"Error downloading provisioning configuration.");
        qlerror(@"%@",err.localizedDescription);
        return 1;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:MP_PROVISION_DIR isDirectory:&isDir];
    if (exists) {
        /* file exists */
        if (!isDir) {
            qlerror(@"Error, %@ exists but is not a directory.",MP_PROVISION_DIR);
            qlerror(@"%@",err.localizedDescription);
            return 1;
        } else {
            // if config exists, remove so we can write a new one
            if ([fm fileExistsAtPath:MP_PROVISION_UI_FILE])
            {
                [fm removeItemAtPath:MP_PROVISION_UI_FILE error:&err]; // File exists, remove it
                if (err) {
                    qlerror(@"Error, unable to remove existsing %@ file.",[MP_PROVISION_UI_FILE lastPathComponent]);
                    qlerror(@"%@",err.localizedDescription);
                    return 1;
                }
            }
            
            // Write new config file
            [configJSON writeToFile:MP_PROVISION_UI_FILE atomically:NO encoding:NSUTF8StringEncoding error:&err];
            if (err) {
                qlerror(@"Error writing provisioning configuration to disk.");
                qlerror(@"%@",err.localizedDescription);
            }
            
            LogDebug(@"%@",configJSON);
        }
    } else {
        [fm createDirectoryRecursivelyAtPath:MP_PROVISION_DIR];
        [configJSON writeToFile:MP_PROVISION_UI_FILE atomically:NO encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            qlerror(@"Error writing provisioning configuration to disk.");
            qlerror(@"%@",err.localizedDescription);
            return 1;
        }
        LogDebug(@"%@",configJSON);
    }
    
    return 0;
}

#pragma mark Private

- (NSDictionary *)getProvisionData
{
    // Call Web Service for all data to povision
    NSDictionary *result = nil;
    NSError *err = nil;
    MPSettings *settings = [MPSettings sharedInstance];
    MPRESTfull *mprest = [[MPRESTfull alloc] init];
    NSDictionary *data = [mprest getProvisioningDataForHost:settings.ccuid error:&err];
    if (err) {
        qlerror(@"%@",err);
        return result;
    } else {
        LogDebug(@"%@",data);
        result = [data copy];
    }
    
    return result;
}

- (void)writeToKeyInProvisionFile:(NSString *)key data:(id)data
{
    NSMutableDictionary *_pFile;
    if ( [fm fileExistsAtPath:MP_PROVISION_FILE] ) {
        _pFile = [NSMutableDictionary dictionaryWithContentsOfFile:MP_PROVISION_FILE];
    } else {
        _pFile = [NSMutableDictionary new];
    }
    
    
    if ([key isEqualToString:@"status"])
    {
        NSMutableArray *_status = [NSMutableArray new];
        if (_pFile[@"status"]) {
            _status = [_pFile[@"status"] mutableCopy];
        }
        [_status addObject:data];
        _pFile[key] = _status;
    } else {
        _pFile[key] = data;
    }

    [_pFile writeToFile:MP_PROVISION_FILE atomically:NO];
}

/*
 Provision Steps
 
 1) Call MP with -L for Provisioning
 2) MPAgent installs scripts and software
    - Write Status file to /Library/LLNL/.MPProvision.plist
 
    {
        startDT: startDateTime
        endDT: endDateTime
        stage: [getData, preScripts, Software, postScripts, userInfoCollection, userSwInstall, patch]
        status: [
            logData
        ]
        userInfoData: {
            assetNum: 1
            machineName:
            oun:
            fileVault
        }
        data: {
            tasks: []
            preScripts: []
            postScripts: []
        }
        completed: bool
        failed: bool
    }
 
 
 */

@end
