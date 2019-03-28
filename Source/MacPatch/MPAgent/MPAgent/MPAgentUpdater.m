//
//  MPAgentUpdater.m
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

#import "MPAgentUpdater.h"
#import "MacPatch.h"

@interface MPAgentUpdater ()
{
    NSFileManager *fm;
    MPSettings *settings;
}

@property (nonatomic,readwrite) NSString *agentUpdaterPath;
@property (nonatomic) NSDictionary *agentUpdateData;

- (NSDictionary *)getAgentUpdaterInfo;

@end

@implementation MPAgentUpdater

@synthesize agentUpdaterPath;
@synthesize agentUpdateData;

- (id)init
{
    self = [super init];
    if (self) {
        self.agentUpdaterPath = [MP_ROOT stringByAppendingPathComponent:@"Updater/MPAgentUp2Date"];
        fm = [NSFileManager defaultManager];
        settings = [MPSettings sharedInstance];
    }
    return self;
}

- (BOOL)scanForAgentUpdater
{
    BOOL result = NO;
    
    logit(lcl_vInfo,@"Begin checking for agent updates.");
    NSDictionary *updateDataRaw = [self getAgentUpdaterInfo];
    
    if (!updateDataRaw) {
        logit(lcl_vError,@"Unable to get update data needed.");
        return result;
    }
    
    // Check to make sure the object is the right type
    // This needs to be fixed in the next version.
    if (![updateDataRaw isKindOfClass:[NSDictionary class]])
    {
        logit(lcl_vError,@"Agent updater info is not available.");
        return result;
    }
    
    // Check if update needed
    if (![updateDataRaw objectForKey:@"updateAvailable"] || [[updateDataRaw objectForKey:@"updateAvailable"] boolValue] == NO) {
        logit(lcl_vInfo,@"No update needed.");
        return result;
    } else {
        logit(lcl_vInfo,@"Update needed.");
        result = YES;
    }
    
    if (!updateDataRaw) {
        logit(lcl_vError,@"No update data found.");
        result = NO;
    } else {
        [self setAgentUpdateData:updateDataRaw];
    }
    
    return result;
}

- (BOOL)updateAgentUpdater
{
    BOOL result = NO;
    if (!self.agentUpdateData) {
        logit(lcl_vError,@"Update can not be applied update data is nil.");
        return result;
    }
    
    NSError *err = nil;
    NSString *downloadURL;
    NSString *downloadFileLoc;
	
	
	
	
	
    // *****************************
    // First we need to download the update
    @try
	{
        logit(lcl_vInfo,@"Start download for patch from %@",[self.agentUpdateData objectForKey:@"pkg_url"]);
        //Pre Proxy Config
        downloadURL = [self.agentUpdateData objectForKey:@"pkg_url"];
        logit(lcl_vInfo,@"Download patch from: %@",downloadURL);
        err = nil;
        
		MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
		NSString *dlDir = [@"/private/tmp" stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
		downloadFileLoc = [req runSyncFileDownload:downloadURL downloadDirectory:dlDir error:&err];
        if (err) {
            logit(lcl_vError,@"Error downloading update %@. Err Message: %@",[downloadURL lastPathComponent],[err localizedDescription]);
            return result;
        }
        logit(lcl_vInfo,@"File downloaded to %@",downloadFileLoc);
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"%@", e);
        return result;
    }
    
    // *****************************
    // Validate hash, before install
    logit(lcl_vInfo,@"Validating downloaded patch.");
    MPCrypto *_crypto = [[MPCrypto alloc] init];
    NSString *fileHash = [_crypto sha1HashForFile:downloadFileLoc];
    _crypto = nil;
    logit(lcl_vInfo,@"Validating download file.");
    logit(lcl_vDebug,@"Downloaded file hash: (%@) (%@)",fileHash,[self.agentUpdateData objectForKey:@"pkg_hash"]);
    logit(lcl_vDebug,@"%@",self.agentUpdateData);
    if ([[[self.agentUpdateData objectForKey:@"pkg_hash"] uppercaseString] isEqualToString:[fileHash uppercaseString]] == NO) {
        logit(lcl_vError,@"The downloaded file did not pass the file hash validation. No install will occur.");
        return result;
    }
    
    // *****************************
    // Now we need to unzip
    logit(lcl_vInfo,@"Uncompressing patch, to begin install.");
    logit(lcl_vInfo,@"Begin decompression of file, %@",downloadFileLoc);
    err = nil;
	MPFileUtils *fu = [MPFileUtils new];
    [fu unzip:downloadFileLoc error:&err];
    if (err) {
        logit(lcl_vError,@"Error decompressing a update %@. Err Message:%@",[downloadURL lastPathComponent],[err localizedDescription]);
        return result;
    }
    logit(lcl_vInfo,@"Update has been decompressed.");
    
    // *****************************
    // Install the update
    BOOL hadErr = NO;
    @try
    {
        NSString *pkgPath;
        NSString *pkgBaseDir = [downloadFileLoc stringByDeletingLastPathComponent];
        NSPredicate *pkgPredicate = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
        NSArray *pkgList = [[fm contentsOfDirectoryAtPath:[downloadFileLoc stringByDeletingLastPathComponent] error:NULL] filteredArrayUsingPredicate:pkgPredicate];
        int installResult = -1;
        MPInstaller *mpInstaller;
        
        // Install pkg(s)
        for (int ii = 0; ii < [pkgList count]; ii++) {
            pkgPath = [NSString stringWithFormat:@"%@/%@",pkgBaseDir,[pkgList objectAtIndex:ii]];
            logit(lcl_vInfo,@"Installing %@",[pkgPath lastPathComponent]);
            logit(lcl_vInfo,@"Start install of %@",pkgPath);
            mpInstaller = [[MPInstaller alloc] init];
            installResult = [mpInstaller installPkgToRoot:pkgPath];
            if (installResult != 0) {
                logit(lcl_vError,@"Error installing package, error code %d.",installResult);
                hadErr = YES;
                break;
            } else {
                logit(lcl_vInfo,@"%@ was installed successfully.",pkgPath);
                result = YES;
            }
        } // End Loop
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"%@", e);
        logit(lcl_vError,@"Error attempting to install update %@. Err Message:%@",[downloadURL lastPathComponent],[err localizedDescription]);
    }
    
    logit(lcl_vInfo,@"Checking for agent updates completed.");
    return result;
}


- (BOOL)scanAndUpdateAgentUpdater
{
    BOOL result = NO;
    if ([self scanForAgentUpdater] == YES) {
        result = [self updateAgentUpdater];
    }
    return result;
}

- (NSDictionary *)getAgentUpdaterInfo
{
    NSError *error = nil;
    NSString *verString = @"0";
    MPNSTask *mpr = [[MPNSTask alloc] init];
    
    // If no or valid MP signature, replace and install
    NSError *err = nil;
    MPCodeSign *cs = [[MPCodeSign alloc] init];
    BOOL verifyDevBin = [cs verifyAppleDevBinary:self.agentUpdaterPath error:&err];
    if (err) {
        logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
    }
    cs = nil;
    if (verifyDevBin == YES)
    {
        verString = [mpr runTask:self.agentUpdaterPath binArgs:[NSArray arrayWithObjects:@"-v", nil] error:&error];
        if (error) {
            logit(lcl_vError,@"%@",[error description]);
            verString = @"0";
        }
    }
    
    NSDictionary *result = [self getAgentUpdateDataFromWS:verString];
    return result;
}

# pragma mark Web Service Request
- (NSDictionary *)getAgentUpdateDataFromWS:(NSString *)version
{
    NSDictionary *data;
    MPHTTPRequest *req;
    MPWSResult *result;

    req = [[MPHTTPRequest alloc] init];

    NSString *urlPath = [@"/api/v2/agent/updater" stringByAppendingFormat:@"/%@/%@",settings.ccuid, version];
    result = [req runSyncGET:urlPath];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        logit(lcl_vInfo,@"Agent Settings data, returned true.");
        data = result.result[@"data"];
    } else {
        logit(lcl_vError,@"Agent Settings data, returned false.");
        logit(lcl_vDebug,@"%@",result.toDictionary);
        return nil;
    }
    
    return data;
}

@end
