//
//  MPSoftware.m
//  MPLibrary
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


#import "MPSoftware.h"
#import "MPCrypto.h"
#import "MPScript.h"
#import "MPFileUtils.h"

#undef  ql_component
#define ql_component lcl_cMPSoftware

@interface MPSoftware ()
{
	NSFileManager *fm;
}

@property (nonatomic, strong) NSURL *SW_DATA_DIR_URL;
@property (nonatomic, strong) NSString *SW_DATA_DIR_PATH;

@end

@implementation MPSoftware

@synthesize SW_DATA_DIR_URL;
@synthesize SW_DATA_DIR_PATH;
- (id)init
{
	if (self = [super init])
	{
		fm = [NSFileManager defaultManager];
		
		// Set Data Directory
		[self createAndSetSoftwareDataDirectory];
	}
	
	return self;
}

- (int)installSoftwareTask:(NSDictionary *)swTask
{
	int result = 0;
	NSString *pkgType = [[swTask valueForKeyPath:@"Software.sw_type"] uppercaseString];
	NSError *err = nil;
	MPCrypto *mpCrypto = [[MPCrypto alloc] init];
	NSString *fHash;
	MPFileUtils *fUtils;
	
	NSString *fileName = [[swTask valueForKeyPath:@"Software.sw_url"] lastPathComponent];
	NSString *dlSoftwareFile = [NSString pathWithComponents:@[SW_DATA_DIR_PATH,@"sw",swTask[@"id"],fileName]];
	
	if ([pkgType isEqualToString:@"SCRIPTZIP"])
	{
		if (![fm fileExistsAtPath:dlSoftwareFile]) {
			qlinfo(@"Need to download software task %@",swTask[@"id"]);
			[self downloadSoftware:[swTask copy] toDestination:[dlSoftwareFile stringByDeletingLastPathComponent]];
		}
		
		qlinfo(@"Verify %@ (%@)",swTask[@"name"],fileName);
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		qlinfo(@"%@: %@",dlSoftwareFile,fHash);
		qlinfo(@"== %@",[swTask valueForKeyPath:@"Software.sw_hash"]);
		if (![[fHash uppercaseString] isEqualToString:[swTask valueForKeyPath:@"Software.sw_hash"]])
		{
			qlerror(@"Error unable to verify software hash for file %@.",[dlSoftwareFile lastPathComponent]);
			return 1;
		}

		[self postStatusToDelegate:@"Unzipping file %@.",[dlSoftwareFile lastPathComponent]];
		qlinfo(@"Unzipping file %@.",dlSoftwareFile);
		fUtils = [MPFileUtils new];
		[fUtils unzip:dlSoftwareFile error:&err];
		if (err)
		{
			qlerror(@"Error unzipping file %@. %@",dlSoftwareFile,[err description]);
			return 1;
		}
		
		// Run Pre Install Script
		if ([self runInstallScript:[swTask objectForKey:@"Software"] type:0] == NO) {
			result = 1;
			return result;
		}
		
		[self postStatusToDelegate:@"Running script..."];
		NSString *mountPoint = NULL;
		NSString *mountPointBase = [SW_DATA_DIR_PATH stringByAppendingPathComponent:@"sw"];
		mountPoint = [mountPointBase stringByAppendingPathComponent:swTask[@"id"]];
		MPScript *mpScript = [MPScript new];
		
		// Run Post Install Script, if copy was good
		if ([mpScript runScriptsFromDirectory:mountPoint])
		{
			if ([self runInstallScript:swTask[@"Software"] type:1] == NO)
			{
				qlerror(@"Error running post install script. Just log it as the install was good.");
			}
		}
		else
		{
			result = 1;
		}
		
	}
	else if ([pkgType isEqualToString:@"PACKAGEZIP"])
	{
		if (![fm fileExistsAtPath:dlSoftwareFile]) {
			qlinfo(@"Need to download software task %@",swTask[@"id"]);
			[self downloadSoftware:[swTask copy] toDestination:[dlSoftwareFile stringByDeletingLastPathComponent]];
		}
		
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		qlinfo(@"Check file: %@.",[dlSoftwareFile lastPathComponent]);
		qlinfo(@"Check Hash: %@ = %@.",[fHash uppercaseString],[swTask valueForKeyPath:@"Software.sw_hash"]);
		if (![[fHash uppercaseString] isEqualToString:[swTask valueForKeyPath:@"Software.sw_hash"]])
		{
			qlerror(@"Error unable to verify software hash for file %@.",[dlSoftwareFile lastPathComponent]);
			return 1;
		}
		
		[self postStatusToDelegate:@"Unzipping file %@.",fileName];
		qlinfo(@"Unzipping file %@.",dlSoftwareFile);
		fUtils = [MPFileUtils new];
		[fUtils unzip:dlSoftwareFile error:&err];
		if (err) {
			qlerror(@"Error unzipping file %@. %@",dlSoftwareFile,[err description]);
			return 1;
		}
		// Run Pre Install Script
		if ([self runInstallScript:[swTask objectForKey:@"Software"] type:0] == NO) {
			result = 1;
			return result;
		}
		
		MPInstaller *installer = [MPInstaller new];
		result = [installer installPkgFromPath:[dlSoftwareFile stringByDeletingLastPathComponent] environment:swTask[@"pkgEnv"]];
		// Run Post Install Script, if copy was good
		if (result == 0)
		{
			if ([self runInstallScript:[swTask objectForKey:@"Software"] type:1] == NO) {
				qlerror(@"Error running post install script. Just log it as the install was good.");
			}
		}
		
	}
	else if ([pkgType isEqualToString:@"APPZIP"])
	{
		if (![fm fileExistsAtPath:dlSoftwareFile]) {
			qlinfo(@"Need to download software task %@",swTask[@"id"]);
			[self downloadSoftware:[swTask copy] toDestination:[dlSoftwareFile stringByDeletingLastPathComponent]];
		}
		
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		if (![[fHash uppercaseString] isEqualToString:[swTask valueForKeyPath:@"Software.sw_hash"]])
		{
			qlerror(@"Error unable to verify software hash for file %@.",fileName);
			return 1;
		}
		
		[self postStatusToDelegate:@"Unzipping file %@.",fileName];
		qlinfo(@"Unzipping file %@.",dlSoftwareFile);
		fUtils = [MPFileUtils new];
		[fUtils unzip:dlSoftwareFile error:&err];
		if (err)
		{
			qlerror(@"Error unzipping file %@. %@",dlSoftwareFile, err.localizedDescription);
			return 1;
		}
		
		// Run Pre Install Script
		if ([self runInstallScript:swTask[@"Software"] type:0] == NO)
		{
			result = 1;
			return result;
		}
		
		// Copy App To Applications
		[self postStatusToDelegate:@"Installing app to Applications..."];
		NSString *mountPoint = NULL;
		NSString *mountPointBase = [SW_DATA_DIR_PATH stringByAppendingPathComponent:@"sw"];
		mountPoint = [mountPointBase stringByAppendingPathComponent:swTask[@"id"]];
		MPInstaller *installer = [MPInstaller new];
		result = [installer installDotAppFrom:mountPoint action:kAppCopyTo];
		// Run Post Install Script, if copy was good
		if (result == 0)
		{
			if ([self runInstallScript:swTask[@"Software"] type:1] == NO)
			{
				qlwarning(@"Error running post install script. Just log it as the install was good.");
			}
		}
		
	}
	else if ([pkgType isEqualToString:@"PACKAGEDMG"])
	{
		if (![fm fileExistsAtPath:dlSoftwareFile]) {
			qlinfo(@"Need to download software task %@",swTask[@"id"]);
			[self downloadSoftware:[swTask copy] toDestination:[dlSoftwareFile stringByDeletingLastPathComponent]];
		}
		
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		qldebug(@"(DL File Hash)%@: %@",dlSoftwareFile,fHash);
		qlinfo(@"(Known File Hash) %@",[swTask valueForKeyPath:@"Software.sw_hash"]);
		if (![[fHash uppercaseString] isEqualToString:[swTask valueForKeyPath:@"Software.sw_hash"]]) {
			qlerror(@"Error unable to verify software hash for file %@.",fileName);
			return 1;
		}
		
		// Run Pre Install Script
		if ([self runInstallScript:swTask[@"Software"] type:0] == NO)
		{
			qlerror(@"Error running pre install script.");
			result = 1;
			return result;
		}
		
		MPInstaller *installer = [MPInstaller new];
		result = [installer installPkgFromDMG:dlSoftwareFile environment:[swTask valueForKeyPath:@"Software.sw_env_var"]];
		
		// Run Post Install Script
		if (result == 0)
		{
			if ([self runInstallScript:swTask[@"Software"] type:1] == NO) {
				qlwarning(@"Error running post install script. Just log it as the install was good.");
			}
		}
		
	}
	else if ([pkgType isEqualToString:@"APPDMG"])
	{
		if (![fm fileExistsAtPath:dlSoftwareFile]) {
			qlinfo(@"Need to download software task %@",swTask[@"id"]);
			[self downloadSoftware:[swTask copy] toDestination:[dlSoftwareFile stringByDeletingLastPathComponent]];
		}
		
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		
		if (![[fHash uppercaseString] isEqualToString:[swTask valueForKeyPath:@"Software.sw_hash"]])
		{
			qlerror(@"Error unable to verify software hash for file %@.",[dlSoftwareFile lastPathComponent]);
			qlerror(@"%@: %@ (%@)",dlSoftwareFile,fHash,[swTask valueForKeyPath:@"Software.sw_hash"]);
			return 1;
		}
		
		// Run Pre Install Script
		if ([self runInstallScript:swTask[@"Software"] type:0] == NO)
		{
			qlerror(@"Error running pre install script.");
			result = 1;
			return result;
		}
		
		MPInstaller *installer = [MPInstaller new];
		result = [installer installDotAppFromDMG:dlSoftwareFile];
		
		// Run Post Install Script
		if (result == 0)
		{
			if ([self runInstallScript:swTask[@"Software"] type:1] == NO) {
				qlwarning(@"Error running post install script. Just log it as the install was good.");
			}
		}
		
	}
	else
	{
		// Install Type Not Supported
		qlerror(@"Install type (%@) is not supported",pkgType);
		result = 2;
	}
	
	if (result == 0)
	{
		if ([[swTask valueForKeyPath:@"Software.auto_patch"] intValue] == 1)
		{
			err = nil;
			[self postStatusToDelegate:@"Patching enabled for %@",swTask[@"name"]];
			// Install Patches If Enabled
            
            NSString *bundle_id = [swTask valueForKeyPath:@"Software.patch_bundle_id"];
            if (bundle_id.length >= 2) {
                [self scanAndUpdateUsingBundleID:bundle_id];
            }
		}
	}
    
    NSDictionary *wsRes = @{@"tuuid":swTask[@"id"],
                            @"suuid":[swTask valueForKeyPath:@"Software.sid"],
                            @"action":@"i",
                            @"result":[NSString stringWithFormat:@"%d",result],
                            @"resultString":@""};
    MPRESTfull *mpr = [MPRESTfull new];
    err = nil;
    [mpr postSoftwareInstallResults:wsRes error:&err];
    if (err) {
        qlerror(@"Error posting software install results.");
        qlerror(@"%@",err.localizedDescription);
    }
    
	return result;
}

- (void)scanAndUpdateUsingBundleID:(NSString *)aBundleID
{
    NSDictionary *patchDict;
    MPPatching *mpp = [MPPatching new];
    NSArray *res = [mpp scanForPatchUsingBundleID:aBundleID];
    if (res.count == 1) {
        NSDictionary *customPatch = [res objectAtIndex:0];
        if ([customPatch[@"bundleID"] isEqualTo:aBundleID])
        {
            logit(lcl_vInfo,@"Patch %@ approved for update.",customPatch[@"patch"]);
            patchDict = [customPatch copy];
        }
    }
    
    NSDictionary *patchRes = [mpp installPatchUsingTypeFilter:patchDict typeFilter:kCustomPatches];
    qldebug(@"Patch Result; %@",patchRes);
}

#pragma mark - Private

- (BOOL)downloadSoftware:(NSDictionary *)swTask toDestination:(NSString *)toPath
{
	NSString *_url = [NSString stringWithFormat:@"/mp-content%@",[swTask valueForKeyPath:@"Software.sw_url"]];
	NSError *dlErr = nil;
	MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
	NSString *dlPath = [req runSyncFileDownload:_url downloadDirectory:toPath error:&dlErr];
	qldebug(@"Downloaded software to %@",dlPath);
	return YES;
}


#pragma mark - Delegate Methods

- (void)downloadProgress:(NSString *)progressStr
{
	// [self postStatus:progressStr];
}

/**
 Create Software Data Directory
 */

- (void)createAndSetSoftwareDataDirectory
{
	// Set Data Directory
	NSError *err = nil;
	NSURL *appSupportDir = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
	NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch"];
	NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
	[self setSW_DATA_DIR_URL:[appSupportMPDir URLByAppendingPathComponent:@"SW_Data"]];
	[self setSW_DATA_DIR_PATH:[SW_DATA_DIR_URL path]];
	
	if ([fm fileExistsAtPath:SW_DATA_DIR_PATH] == NO)
	{
		// Create dir if it does not exist
		[fm createDirectoryAtPath:SW_DATA_DIR_PATH withIntermediateDirectories:YES attributes:attributes error:&err];
		if (err) {
			qlinfo(@"%@",[err description]);
		}
	}
	else
	{
		// Set directory attributes, permissions etc.
		[fm setAttributes:attributes ofItemAtPath:SW_DATA_DIR_PATH error:&err];
		if (err) {
			qlerror(@"%@",err.localizedDescription);
		}
		
		// Set attributes for file in directory
		NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:SW_DATA_DIR_PATH];
		NSString *file;
		while (file = [dirEnum nextObject])
		{
			err = nil;
			[fm setAttributes:attributes ofItemAtPath:[SW_DATA_DIR_PATH stringByAppendingPathComponent:file] error:&err];
			if (err) {
				qlerror(@"%@",err.localizedDescription);
			}
		}
	}
}


/**
 Run Sofware Task script using a type

 @param software dictionary containing software data
 @param aScriptType script type (pre or post install)
 @return BOOL
 */
- (BOOL)runInstallScript:(NSDictionary *)software type:(int)scriptType
{
	MPScript *mps = [[MPScript alloc] init];
	NSString *_script;
	if (scriptType == 0)
	{
		if ([software hasKey:@"sw_pre_install"])
		{
			if ([software[@"sw_pre_install"] isEqualToString:@""] == NO)
			{
				//[self postDataToClient:@"Running pre-install script..." type:kMPProcessStatus];
				@try
				{
					_script = software[@"sw_pre_install"];
					if ([_script isBase64String]) {
						_script = [_script decodeBase64AsString];
					}
					if (![mps runScript:_script])
					{
						qlerror(@"Error running pre install script. No install will occure.");
						return NO;
					}
					else
					{
						return YES;
					}
				}
				@catch (NSException *exception)
				{
					qlerror(@"Exception Error running pre install script. No install will occure.");
					qlerror(@"%@",exception);
					return NO;
				}
			}
			else
			{
				return YES;
			}
		}
		else
		{
			return YES;
		}
	}
	else if (scriptType == 1)
	{
		if ([software hasKey:@"sw_post_install"])
		{
			if ([software[@"sw_post_install"] isEqualToString:@""] == NO)
			{
				//[self postDataToClient:@"Running post-install script..." type:kMPProcessStatus];
				@try
				{
					_script = software[@"sw_post_install"];
					if ([_script isBase64String]) {
						_script = [_script decodeBase64AsString];
					}
					if (![mps runScript:_script])
					{
						qlerror(@"Error running post install script.");
						return NO;
					} else {
						return YES;
					}
				}
				@catch (NSException *exception)
				{
					qlerror(@"Exception Error running post install script.");
					qlerror(@"%@",exception);
					return NO;
				}
			}
			else
			{
				return YES;
			}
		}
		else
		{
			return YES;
		}
	}
	else
	{
		return NO;
	}
	
	return NO;
}

#pragma mark - Delegate Helper

- (void)postStatusToDelegate:(NSString *)str, ...
{
	va_list va;
	va_start(va, str);
	NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
	va_end(va);
	
	[self.delegate softwareProgress:string];
}

@end
