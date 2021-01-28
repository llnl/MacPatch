//
//  MPProvision.m
//  MPAgent
//
//  Created by Charles Heizer on 1/14/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

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
                qlinfo(@"Pre Script: %@",s[@"name"]);
                @try {
                    MPScript *scp = [MPScript new];
                    [scp runScript:s[@"script"]];
                } @catch (NSException *exception) {
                    qlerror(@"[PreScript]: %@",exception);
                }
                
            }
        } else {
            qlinfo(@"No, pre scripts to run.");
        }
    }
    
    // Run Software Tasks
    [self writeToKeyInProvisionFile:@"stage" data:@"Software"];
    NSArray *_sw = provisionData[@"tasks"];
    if (_sw) {
        if (_sw.count >= 1) {
            for (NSDictionary *s in _sw)
            {
                qlinfo(@"Install Software Task: %@",s[@"name"]);
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
            qlinfo(@"No, software tasks to run.");
        }
    }
    
    // Run Post Scripts
    [self writeToKeyInProvisionFile:@"stage" data:@"postScripts"];
    NSArray *_post = provisionData[@"scriptsPost"];
    if (_post) {
        if (_post.count >= 1) {
            for (NSDictionary *s in _post)
            {
                qlinfo(@"Post Script: %@",s[@"name"]);
                @try {
                    MPScript *scp = [MPScript new];
                    [scp runScript:s[@"script"]];
                } @catch (NSException *exception) {
                    qlerror(@"[PostScript]: %@",exception);
                }
                
            }
        } else {
            qlinfo(@"No, post scripts to run.");
        }
    }
    
    
    return res;
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
        qldebug(@"%@",data);
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
