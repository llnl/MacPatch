//
//  MPSWInstaller.m
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

#import "MPSWInstaller.h"
#import "MPCrypto.h"
#import "MPAgentController.h"

enum {
    kMPInstallStatus = 0,
    kMPProcessStatus = 1
};
typedef NSUInteger MPPostDataType;

@interface NSFileHandle (MPNSFileHandleAdditions)
- (NSData *)availableDataOrError:(NSException **)returnError;
@end

@implementation NSFileHandle (MPNSFileHandleAdditions)
- (NSData *)availableDataOrError:(NSException **)returnError
{
    for(;;)
	{
        @try
		{
            return [self availableData];
        }
		@catch (NSException *e)
		{
			if ([[e name] isEqualToString:NSFileHandleOperationException]) {
				if ([[e reason] isEqualToString:@"*** -[NSConcreteFileHandle availableData]: Interrupted system call"]) {
					continue;
				}
				if (returnError) {
					*returnError = e;
				}
				return nil;
			}
			@throw;
        }
    }
}
@end

@interface MPSWInstaller (Private)

#pragma mark - MPSWInstaller (Private)

// DMG
- (int)copyAppFromDMG:(NSString *)pkgID;
- (int)installPkgFromDMG:(NSString *)pkgID environment:(NSString *)aEnv;
- (void)installerOutput:(NSString *)output;

- (int)mountDMG:(NSString *)aDMG packageID:(NSString *)pkgID;
- (int)unmountDMG:(NSString *)aDMG packageID:(NSString *)pkgID;

// ZIP
- (int)installPkgFromZIP:(NSString *)pkgID environment:(NSString *)aEnv;

// Script
- (BOOL)runInstallScript:(NSDictionary *)aSWDict type:(int)aScriptType;
- (int)runScript:(NSString *)aDir;

// Misc
- (int)copyAppFrom:(NSString *)aDir action:(int)action;

- (void)postDataToClient:(id)data type:(MPPostDataType)dataType;
- (void)taskTimeoutThread;
- (void)taskTimeout:(NSNotification *)aNotification;

- (int)runTask:(NSString *)aBinPath binArgs:(NSArray *)aBinArgs environment:(NSString *)env;

- (NSString *)downloadedSWPath:(NSDictionary *)dict;
- (BOOL)verifyFileHash:(NSString *)aPath knownHash:(NSString *)kHash type:(NSString *)hashType;

#pragma mark - MPWorker (Private) - Patching

- (NSString *)getSizeFromDescription:(NSString *)aDesc;
- (NSString *)getRecommendedFromDescription:(NSString *)aDesc;

- (void)scanForNotification:(NSNotification *)notification;

- (void)runInstallPkgTask:(NSString *)pkg target:(NSString *)target env:(NSString *)aEnv;
// Noteifations
- (void)taskDataAvailable:(NSNotification *)aNotification;
- (void)taskCompleted:(NSNotification *)aNotification;

@end

@implementation MPSWInstaller

@synthesize _timeoutTimer;
@synthesize taskTimeoutValue;
@synthesize taskTimedOut;
@synthesize taskIsRunning;
@synthesize installtaskResult;
@synthesize mp_SOFTWARE_DATA_DIR;

- (id)init
{
    if (self = [super init])
    {
		[self setTaskTimeoutValue:300];
		[self setTaskIsRunning:NO];
        [self setTaskTimedOut:NO];
        fm = [NSFileManager defaultManager];
        // Set Data Directory
        NSURL *appSupportDir = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
        NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch"];
        [self setMp_SOFTWARE_DATA_DIR:[appSupportMPDir URLByAppendingPathComponent:@"SW_Data"]];
        if ([fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path]] == NO) {
            NSError *err = nil;
            NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
            [fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:&err];
            if (err) {
                logit(lcl_vError,@"%@",[err description]);
            }
        }
    }
    
    return self;
}

- (int)installSoftware:(NSDictionary *)aSWDict
{
    return [self installSoftware:aSWDict error:NULL];
}

- (int)installSoftware:(NSDictionary *)aSWDict error:(NSError **)error
{
    int result = 0;
    NSString *pkgType = [[aSWDict valueForKeyPath:@"Software.sw_type"] uppercaseString];
    NSError *err = nil;
    MPCrypto *mpCrypto = [[MPCrypto alloc] init];
    NSString *fHash;
    MPAsus *mpa = [[MPAsus alloc] init];
    
    if ([pkgType isEqualToString:@"SCRIPTZIP"]) {
        
        NSString *zipFile = [NSString pathWithComponents:[NSArray arrayWithObjects:[mp_SOFTWARE_DATA_DIR path],@"sw",[aSWDict objectForKey:@"id"],[[aSWDict valueForKeyPath:@"Software.sw_url"] lastPathComponent], nil]];
        logit(lcl_vInfo,@"Verify %@ (%@)",[aSWDict objectForKey:@"name"],[[aSWDict valueForKeyPath:@"Software.sw_url"] lastPathComponent]);
        fHash = [mpCrypto md5HashForFile:zipFile];
        logit(lcl_vInfo,@"%@: %@",zipFile,fHash);
        logit(lcl_vInfo,@"== %@",[aSWDict valueForKeyPath:@"Software.sw_hash"]);
        if (![[fHash uppercaseString] isEqualToString:[aSWDict valueForKeyPath:@"Software.sw_hash"]]) {
            logit(lcl_vError,@"Error unable to verify software hash for file %@.",[zipFile lastPathComponent]);
            return 1;
        }
        
        logit(lcl_vInfo,@"Unzipping file %@.",zipFile);
        [mpa unzip:zipFile error:&err];
        if (err) {
            logit(lcl_vError,@"Error unzipping file %@. %@",zipFile,[err description]);
            return 1;
        }
        
        // Run Pre Install Script
        if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:0] == NO) {
            result = 1;
            return result;
        }
        
        // Copy App To Applications
        NSString *mountPoint = NULL;
        NSString *mountPointBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
        mountPoint = [mountPointBase stringByAppendingPathComponent:[aSWDict objectForKey:@"id"]];
        result = [self runScript:mountPoint];
        
        // Run Post Install Script, if copy was good
        if (result == 0)
        {
            if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:1] == NO) {
                logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
            }
        }
        
    } else if ([pkgType isEqualToString:@"PACKAGEZIP"]) {
        
        NSString *zipFile = [NSString pathWithComponents:[NSArray arrayWithObjects:[mp_SOFTWARE_DATA_DIR path],@"sw",[aSWDict objectForKey:@"id"],[[aSWDict valueForKeyPath:@"Software.sw_url"] lastPathComponent], nil]];
        fHash = [mpCrypto md5HashForFile:zipFile];
        if (![[fHash uppercaseString] isEqualToString:[aSWDict valueForKeyPath:@"Software.sw_hash"]]) {
            logit(lcl_vError,@"Error unable to verify software hash for file %@.",[zipFile lastPathComponent]);
            return 1;
        }
        
        logit(lcl_vInfo,@"Unzipping file %@.",zipFile);
        [mpa unzip:zipFile error:&err];
        if (err) {
            logit(lcl_vError,@"Error unzipping file %@. %@",zipFile,[err description]);
            return 1;
        }
        // Run Pre Install Script
        if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:0] == NO) {
            result = 1;
            return result;
        }
        
        result = [self installPkgFromZIP:[aSWDict objectForKey:@"id"] environment:[aSWDict objectForKey:@"pkgEnv"]];
        
        // Run Post Install Script, if copy was good
        if (result == 0)
        {
            if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:1] == NO) {
                logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
            }
        }
        
    } else if ([pkgType isEqualToString:@"APPZIP"]) {
        
        NSString *zipFile = [NSString pathWithComponents:[NSArray arrayWithObjects:[mp_SOFTWARE_DATA_DIR path],@"sw",[aSWDict objectForKey:@"id"],[[aSWDict valueForKeyPath:@"Software.sw_url"] lastPathComponent], nil]];
        fHash = [mpCrypto md5HashForFile:zipFile];
        if (![[fHash uppercaseString] isEqualToString:[aSWDict valueForKeyPath:@"Software.sw_hash"]]) {
            logit(lcl_vError,@"Error unable to verify software hash for file %@.",[zipFile lastPathComponent]);
            return 1;
        }
        
        logit(lcl_vInfo,@"Unzipping file %@.",zipFile);
        [mpa unzip:zipFile error:&err];
        if (err) {
            logit(lcl_vError,@"Error unzipping file %@. %@",zipFile,[err description]);
            return 1;
        }
        
        // Run Pre Install Script
        if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:0] == NO) {
            result = 1;
            return result;
        }
        
        // Copy App To Applications
        NSString *mountPoint = NULL;
        NSString *mountPointBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
        mountPoint = [mountPointBase stringByAppendingPathComponent:[aSWDict objectForKey:@"id"]];
        result = [self copyAppFrom:mountPoint action:1];
        
        // Run Post Install Script, if copy was good
        if (result == 0)
        {
            if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:1] == NO) {
                logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
            }
        }
        
    } else if ([pkgType isEqualToString:@"PACKAGEDMG"]) {
        NSString *dmgFile = [self downloadedSWPath:aSWDict];
        fHash = [mpCrypto md5HashForFile:dmgFile];
        logit(lcl_vInfo,@"%@: %@",dmgFile,fHash);
        logit(lcl_vInfo,@"== %@",[aSWDict valueForKeyPath:@"Software.sw_hash"]);
        if (![[fHash uppercaseString] isEqualToString:[aSWDict valueForKeyPath:@"Software.sw_hash"]]) {
            logit(lcl_vError,@"Error unable to verify software hash for file %@.",[dmgFile lastPathComponent]);
            return 1;
        }
        
        int m = -1;
        m = [self mountDMG:[aSWDict valueForKeyPath:@"Software.sw_url"] packageID:[aSWDict objectForKey:@"id"]];
        if (m == 0) {
            // Run Pre Install Script
            if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:0] == NO) {
                result = 1;
                return result;
            }
            
            // Run PKG Installs
            result = [self installPkgFromDMG:[aSWDict objectForKey:@"id"] environment:[aSWDict valueForKeyPath:@"Software.sw_env_var"]];
            
            // Run Post Install Script, if copy was good
            if (result == 0)
            {
                if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:1] == NO) {
                    logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
                }
            }
        }
        
    } else if ([pkgType isEqualToString:@"APPDMG"]) {
        NSString *dmgFile = [self downloadedSWPath:aSWDict];
        fHash = [mpCrypto md5HashForFile:dmgFile];
        
        if (![[fHash uppercaseString] isEqualToString:[aSWDict valueForKeyPath:@"Software.sw_hash"]]) {
            logit(lcl_vError,@"Error unable to verify software hash for file %@.",[dmgFile lastPathComponent]);
            logit(lcl_vError,@"%@: %@ (%@)",dmgFile,fHash,[aSWDict valueForKeyPath:@"Software.sw_hash"]);
            return 1;
        }
        
        int m = -1;
        m = [self mountDMG:[aSWDict valueForKeyPath:@"Software.sw_url"] packageID:[aSWDict objectForKey:@"id"]];
        if (m == 0) {
            // Run Pre Install Script
            if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:0] == NO) {
                result = 1;
                return result;
            }
            
            // Copy App To Applications
            result = [self copyAppFromDMG:[aSWDict objectForKey:@"id"]];
            
            // Run Post Install Script, if copy was good
            if (result == 0)
            {
                if ([self runInstallScript:[aSWDict objectForKey:@"Software"] type:1] == NO) {
                    logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
                }
            }
        }
        
    } else {
        // Install Type Not Supported
        result = 2;
    }
    
    if (result == 0) {
        if ([[aSWDict valueForKeyPath:@"Software.auto_patch"] intValue] == 1) {
            err = nil;
            [self postDataToClient:[NSString stringWithFormat:@"Patching enabled for %@",[aSWDict objectForKey:@"name"]] type:kMPProcessStatus];
            // Install Pathes If Enabled
            sleep(2);
        }
    }
    return result;
}

- (int)patchSoftware:(NSDictionary *)aSWDict
{
    return [self patchSoftware:aSWDict error:NULL];
}

- (int)patchSoftware:(NSDictionary *)aSWDict error:(NSError **)error
{
    int result = 0;
    MPAgentController *ma = [[MPAgentController alloc] initForBundleUpdate];
    [ma scanAndUpdateCustomWithPatchBundleID:[aSWDict valueForKeyPath:@"Software.patch_bundle_id"]];
    result = [ma errorCode];
    return result;
}

#pragma mark - Private Methods
- (int)mountDMG:(NSString *)aDMG packageID:(NSString *)pkgID
{
    [self postDataToClient:@"Mounting DMG" type:kMPProcessStatus];
    
    NSString *swLoc = NULL;
    NSString *swLocBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
    swLoc = [NSString pathWithComponents:[NSArray arrayWithObjects:swLocBase,pkgID,[aDMG lastPathComponent], nil]];
    
    NSString *mountPoint = NULL;
    NSString *mountPointBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"dmg"];
    mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
    
    NSError *err = nil;
    if (![fm fileExistsAtPath:mountPoint]) {
        [fm createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
    } else {
        [self unmountDMG:aDMG packageID:pkgID];
        [fm createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
    }
    
    if ([fm fileExistsAtPath:swLoc] == NO) {
        logit(lcl_vError,@"File \"%@\" does not exist.",swLoc);
        return 1;
    }
    
    NSArray *args = [NSArray arrayWithObjects:@"attach", @"-mountpoint", mountPoint, swLoc, @"-nobrowse", nil];
    NSTask  *aTask = [[NSTask alloc] init];
    NSPipe  *pipe = [NSPipe pipe];
    
    [aTask setLaunchPath:@"/usr/bin/hdiutil"];
    [aTask setArguments:args];
    [aTask setStandardInput:pipe];
    [aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
    [aTask launch];
    //[[pipe fileHandleForWriting] writeData:[@"password" dataUsingEncoding:NSUTF8StringEncoding]];
    //[[pipe fileHandleForWriting] closeFile];
    [aTask waitUntilExit];
    int result = [aTask terminationStatus];
    if (result == 0) {
        [self postDataToClient:@"DMG Mounted..." type:kMPProcessStatus];
    }
    return result;
}

- (int)unmountDMG:(NSString *)aDMG packageID:(NSString *)pkgID
{
    [self postDataToClient:@"Un-Mounting DMG..." type:kMPProcessStatus];
    
    NSString *mountPoint = NULL;
    NSString *mountPointBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"dmg"];
    mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
    
    NSArray       *args  = [NSArray arrayWithObjects:@"detach", mountPoint, @"-force", nil];
    NSTask        *aTask = [[NSTask alloc] init];
    NSPipe        *pipe  = [NSPipe pipe];
    
    [aTask setLaunchPath:@"/usr/bin/hdiutil"];
    [aTask setArguments:args];
    [aTask setStandardInput:pipe];
    [aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
    [aTask launch];
    [aTask waitUntilExit];
    
    int result = [aTask terminationStatus];
    if (result == 0) {
        [self postDataToClient:@"DMG Un-Mounted..." type:kMPProcessStatus];
    }
    return result;
}

- (int)copyAppFromDMG:(NSString *)pkgID
{
    int result = 0;
    NSString *mountPoint = NULL;
    NSString *mountPointBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"dmg"];
    mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
    
    result = [self copyAppFrom:mountPoint action:0];
    
    [self unmountDMG:mountPoint packageID:pkgID];
    return result;
}

- (int)installPkgFromDMG:(NSString *)pkgID environment:(NSString *)aEnv
{
    int result = 0;
    NSString *mountPoint = NULL;
    NSString *mountPointBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"dmg"];
    mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
    
    NSArray *dirContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
    NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
    NSArray *onlyPkgs = [dirContents filteredArrayUsingPredicate:fltr];
    
    int pkgInstallResult = -1;
    NSArray *installArgs;
    for (NSString *pkg in onlyPkgs)
    {
        [self postDataToClient:[NSString stringWithFormat:@"Begin installing %@",pkg] type:kMPProcessStatus];
        installArgs = [NSArray arrayWithObjects:@"-verboseR", @"-pkg", [mountPoint stringByAppendingPathComponent:pkg], @"-target", @"/", nil];
        pkgInstallResult = [self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:aEnv];
        if (pkgInstallResult != 0) {
            result++;
        }
    }
    
    [self unmountDMG:mountPoint packageID:pkgID];
    return result;
}

- (int)installPkgFromZIP:(NSString *)pkgID environment:(NSString *)aEnv
{
    int result = 0;
    NSString *mountPoint = NULL;
    mountPoint = [NSString pathWithComponents:[NSArray arrayWithObjects:[mp_SOFTWARE_DATA_DIR path],@"sw",pkgID, nil]];
    
    NSArray *dirContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
    NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
    NSArray *onlyPkgs = [dirContents filteredArrayUsingPredicate:fltr];
    
    int pkgInstallResult = -1;
    NSArray *installArgs;
    for (NSString *pkg in onlyPkgs)
    {
        [self postDataToClient:[NSString stringWithFormat:@"Begin installing %@",pkg] type:kMPProcessStatus];
        installArgs = [NSArray arrayWithObjects:@"-verboseR", @"-pkg", [NSString pathWithComponents:[NSArray arrayWithObjects:[mp_SOFTWARE_DATA_DIR path],@"sw",pkgID, pkg, nil]], @"-target", @"/", nil];
        pkgInstallResult = [self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:aEnv];
        if (pkgInstallResult != 0) {
            result++;
        }
    }
    
    return result;
}

- (BOOL)runInstallScript:(NSDictionary *)aSWDict type:(int)aScriptType
{
    MPScript *mps = [[MPScript alloc] init];
    NSString *_script;
    if (aScriptType == 0) {
        if ([aSWDict hasKey:@"sw_pre_install"]) {
            if ([[aSWDict objectForKey:@"sw_pre_install"] isEqualToString:@""] == NO)
            {
                [self postDataToClient:@"Running pre-install script..." type:kMPProcessStatus];
                @try
                {
                    _script = [[aSWDict objectForKey:@"sw_pre_install"] decodeBase64AsString];
                    if (![mps runScript:_script]) {
                        logit(lcl_vError,@"Error running pre install script. No install will occure.");
                        return NO;
                    } else {
                        return YES;
                    }
                }
                @catch (NSException *exception) {
                    logit(lcl_vError,@"Exception Error running pre install script. No install will occure.");
                    logit(lcl_vError,@"%@",exception);
                    return NO;
                }
            } else {
                return YES;
            }
        } else {
            return YES;
        }
    } else if (aScriptType == 1) {
        if ([aSWDict hasKey:@"sw_post_install"]) {
            if ([[aSWDict objectForKey:@"sw_post_install"] isEqualToString:@""] == NO)
            {
                [self postDataToClient:@"Running post-install script..." type:kMPProcessStatus];
                @try
                {
                    _script = [[aSWDict objectForKey:@"sw_post_install"] decodeBase64AsString];
                    if (![mps runScript:_script]) {
                        logit(lcl_vError,@"Error running post install script.");
                        return NO;
                    } else {
                        return YES;
                    }
                }
                @catch (NSException *exception) {
                    logit(lcl_vError,@"Exception Error running post install script.");
                    logit(lcl_vError,@"%@",exception);
                    return NO;
                }
            } else {
                return YES;
            }
        } else {
            return YES;
        }
    } else {
        return NO;
    }
}

- (int)runScript:(NSString *)aDir
{
    int result = 0;
    NSArray *dirContents = [fm contentsOfDirectoryAtPath:aDir error:nil];
    NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.sh') OR (SELF like [cd] '*.rb') OR (SELF like [cd] '*.py')"];
    NSArray *onlyScripts = [dirContents filteredArrayUsingPredicate:fltr];
    
    NSError *err = nil;
    NSString *scriptText = nil;
    MPScript *mps = nil;
    for (NSString *scpt in onlyScripts)
    {
        err = nil;
        scriptText = [NSString stringWithContentsOfFile:[aDir stringByAppendingPathComponent:scpt] encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            logit(lcl_vError,@"Error reading script string: %@",[err description]);
            logit(lcl_vError,@"%@",[err description]);
            result = 3;
            break;
        }
        mps = [[MPScript alloc] init];
        [self postDataToClient:[NSString stringWithFormat:@"Running script %@",scpt] type:kMPProcessStatus];
        if ([mps runScript:scriptText]) {
            result = 0;
        } else {
            result = 1;
            break;
        }
        mps = nil;
    }
    
    return result;
}

#pragma mark Misc
- (int)copyAppFrom:(NSString *)aDir action:(int)action
{
    int result = 0;
    NSArray *dirContents = [fm contentsOfDirectoryAtPath:aDir error:nil];
    NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH '.app'"];
    NSArray *onlyApps = [dirContents filteredArrayUsingPredicate:fltr];
    
    NSError *err = nil;
    for (NSString *app in onlyApps) {
        if ([fm fileExistsAtPath:[@"/Applications"  stringByAppendingPathComponent:app]]) {
            logit(lcl_vInfo,@"Found, %@. Now remove it.",[@"/Applications" stringByAppendingPathComponent:app]);
            [fm removeItemAtPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
            if (err) {
                logit(lcl_vError,@"%@",[err description]);
                result = 3;
                break;
            }
        }
        err = nil;
        [self postDataToClient:[NSString stringWithFormat:@"Copy %@ to %@",app,[@"/Applications" stringByAppendingPathComponent:app]] type:kMPProcessStatus];
        if (action == 0) {
            [fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
        } else if (action == 1) {
            [fm moveItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
        } else {
            [fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
        }
        
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
            result = 2;
            break;
        }
    }
    
    return result;
}

- (void)taskTimeoutThread
{
	@autoreleasepool {
	
		logit(lcl_vDebug,@"Timeout is set to %d",taskTimeoutValue);
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:taskTimeoutValue
														  target:self
														selector:@selector(taskTimeout:)
														userInfo:nil
														 repeats:NO];
		[self set_timeoutTimer:timer];
		
		while (taskTimedOut == NO && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
	
	}
	
}

- (void)taskTimeout:(NSNotification *)aNotification
{
	logit(lcl_vInfo,@"Task timedout, killing task.");
	[_timeoutTimer invalidate];
	[self setTaskTimedOut:YES];
	[swTask terminate];
}

- (int)runTask:(NSString *)aBinPath binArgs:(NSArray *)aBinArgs environment:(NSString *)env
{
	[self setTaskIsRunning:YES];
	[self setTaskTimedOut:NO];
	
	int taskResult = -1;
    
    if (swTask) {
        swTask = nil;
    }
    swTask = [[NSTask alloc] init];
    NSPipe *aPipe = [NSPipe pipe];
    
	[swTask setStandardOutput:aPipe];
	[swTask setStandardError:aPipe];
	
    // Parse the Environment variables for the install
    NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
	[environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
	
    if ([env isEqualToString:@"NA"] == NO && [[env trim] length] > 0)
    {
        NSArray *l_envArray;
        NSArray *l_envItems;
        l_envArray = [env componentsSeparatedByString:@","];
        for (id item in l_envArray) {
            l_envItems = nil;
            l_envItems = [item componentsSeparatedByString:@"="];
            if ([l_envItems count] == 2) {
                logit(lcl_vDebug,@"Setting env variable(%@=%@).",[l_envItems objectAtIndex:0],[l_envItems objectAtIndex:1]);
                [environment setObject:[l_envItems objectAtIndex:1] forKey:[l_envItems objectAtIndex:0]];
            } else {
                logit(lcl_vError,@"Unable to set env variable. Variable not well formed %@",item);
            }
        }
    }
    
    [swTask setEnvironment:environment];
    logit(lcl_vDebug,@"[task][environment]: %@",environment);
    [swTask setLaunchPath:aBinPath];
	logit(lcl_vDebug,@"[task][setLaunchPath]: %@",aBinPath);
    [swTask setArguments:aBinArgs];
	logit(lcl_vDebug,@"[task][setArguments]: %@",aBinArgs);
	
    // Launch The NSTask
	@try {
		[swTask launch];
        // If timeout is set start it ...
        if (taskTimeoutValue != 0) {
            [NSThread detachNewThreadSelector:@selector(taskTimeoutThread) toTarget:self withObject:nil];
        }
	}
	@catch (NSException *e)
    {
		logit(lcl_vError,@"Install returned error. %@\n%@",[e reason],[e userInfo]);
		taskResult = 1;
        if(_timeoutTimer) {
            [_timeoutTimer invalidate];
        }
        [self setTaskIsRunning:NO];
        return taskResult;
	}
	
	NSString		*tmpStr;
    NSMutableData	*data = [[NSMutableData alloc] init];
    NSData			*dataChunk = nil;
    NSException		*error = nil;
    
	while(taskTimedOut == NO && ((dataChunk = [[aPipe fileHandleForReading] availableDataOrError:&error]) && [dataChunk length] && error == nil))
	{
        // If the data is not null, then post the data back to the client and log it locally
        tmpStr = [[NSString alloc] initWithData:dataChunk encoding:NSUTF8StringEncoding];
		if ([[tmpStr trim] length] != 0)
        {
            if ([tmpStr containsString:@"PackageKit: Missing bundle path"] == NO) {
                logit(lcl_vDebug,@"%@",tmpStr);
                [self postDataToClient:tmpStr type:kMPInstallStatus];
            } else {
                logit(lcl_vDebug,@"%@",tmpStr);
            }
		}
		
		[data appendData:dataChunk];
		tmpStr = nil;
	}
    
	[[aPipe fileHandleForReading] closeFile];
    
	if (taskTimedOut == YES) {
		logit(lcl_vError,@"Task was terminated due to timeout.");
		[NSThread sleepForTimeInterval:2.0];
		taskResult = 1;
		if(_timeoutTimer) {
            [_timeoutTimer invalidate];
        }
        [self setTaskIsRunning:NO];
        return taskResult;
	}
	
    if([data length] && error == nil)
    {
        if ([swTask terminationStatus] == 0) {
            taskResult = 0;
        } else {
            taskResult = 1;
        }
    } else {
		logit(lcl_vError,@"Install returned error. Code:[%d]",[swTask terminationStatus]);
		taskResult = 1;
	}

	if(_timeoutTimer) {
		[_timeoutTimer invalidate];
	}
	[self setTaskIsRunning:NO];
    return taskResult;
}

- (NSString *)downloadedSWPath:(NSDictionary *)dict
{
    NSString *swFile;
    swFile = [NSString pathWithComponents:[NSArray arrayWithObjects:[mp_SOFTWARE_DATA_DIR path],@"sw",[dict objectForKey:@"id"],[[dict valueForKeyPath:@"Software.sw_url"] lastPathComponent], nil]];
    return swFile;
}

- (BOOL)verifyFileHash:(NSString *)aPath knownHash:(NSString *)kHash type:(NSString *)hashType
{
    MPCrypto *mpCrypto = [[MPCrypto alloc] init];
    NSString *fHash = [mpCrypto getHashForFileForType:aPath type:hashType];
    
    if (![[fHash uppercaseString] isEqualToString:[kHash uppercaseString]])
    {
        logit(lcl_vError,@"Error unable to verify software hash for file %@.",[aPath lastPathComponent]);
        logit(lcl_vDebug,@"Known:%@ = %@",kHash,fHash);
        return NO;
    } else {
        return YES;
    }
    
    return NO;
}

#pragma mark SelfPatch

// Proxy Method
- (NSArray *)scanForAppleUpdatesViaHelper
{
	logit(lcl_vInfo,@"Scanning for Apple software updates.");
	
	NSArray *appleUpdates = nil;
	
	spTask = [[NSTask alloc] init];
    [spTask setLaunchPath: ASUS_BIN_PATH];
	
	if ((int)NSAppKitVersionNumber >= 1504 /* 10.12 */) {
		[spTask setArguments: [NSArray arrayWithObjects: @"-l", @"--include-config-data", nil]];
	} else {
		[spTask setArguments: [NSArray arrayWithObjects: @"-l", nil]];
	}
	
    NSPipe *pipe = [NSPipe pipe];
    [spTask setStandardOutput: pipe];
    [spTask setStandardError: pipe];
	
	NSFileHandle *file = [pipe fileHandleForReading];
	
    [spTask launch];
	logit(lcl_vInfo,@"Starting Apple software update scan.");
	[spTask waitUntilExit];
	
	int status = [spTask terminationStatus];
	if (status != 0) {
		logit(lcl_vError,@"Error: softwareupdate exit code = %d",status);
		return appleUpdates;
	} else {
		logit(lcl_vInfo,@"Apple software update scan was completed.");
	}
    
	
	NSData *data = [file readDataToEndOfFile];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
	logit(lcl_vInfo,@"Apple software update full scan results\n%@",string);
	
	if (!([string rangeOfString:@"No new"].location == NSNotFound)) {
		logit(lcl_vInfo,@"No new updates.");
		return appleUpdates;
	}
	
	// We have updates so we need to parse the results
	NSArray *strArr = [NSArray arrayWithArray:[string componentsSeparatedByString:@"\n"]];
	
	NSMutableArray *tmpAppleUpdates = [[NSMutableArray alloc] init];
	NSString *tmpStr, *line, *lineCleanStart;
	NSMutableDictionary *tmpDict;
	
	for (int i=0; i<[strArr count]; i++) {
		// Ignore empty lines
		if ([[strArr objectAtIndex:i] length] != 0) {
			
			//Clear the tmpDict object before populating it
			if (!([[strArr objectAtIndex:i] rangeOfString:@"Software Update Tool"].location == NSNotFound)) {
				continue;
			}
			if (!([[strArr objectAtIndex:i] rangeOfString:@"Copyright"].location == NSNotFound)) {
				continue;
			}
			
			// Strip the White Space and any New line data
			line = [strArr objectAtIndex:i];
			tmpStr = [[strArr objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([tmpStr hasPrefix:@"*"] || [tmpStr hasPrefix:@"!"])
			{
				@try
				{
					lineCleanStart = [self cleanLine:line];
					tmpDict = [[NSMutableDictionary alloc] init];
					[tmpDict setObject:lineCleanStart forKey:@"patch"];
					[tmpDict setObject:@"Apple" forKey:@"type"];
					[tmpDict setObject:[[lineCleanStart componentsSeparatedByString:@"-"] lastObject] forKey:@"version"];
					[tmpDict setObject:[[strArr objectAtIndex:(i+1)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:@"description"];
					[tmpDict setObject:[self getSizeFromDescription:[tmpDict objectForKey:@"description"]] forKey:@"size"];
					[tmpDict setObject:([[tmpDict objectForKey:@"description"] containsString:@"[recommended]"] ? @"Y": @"N") forKey:@"recommended"];
					[tmpDict setObject:([[tmpDict objectForKey:@"description"] containsString:@"[restart]"] ? @"Yes": @"No") forKey:@"restart"];
					
					[tmpAppleUpdates addObject:[tmpDict copy]];
					tmpDict = nil;
				}
				@catch (NSException *exception)
				{
					qlerror(@"Error create patch dict. %@",exception);
				}
			}
		} // if / empty lines
	} // for loop
	appleUpdates = [NSArray arrayWithArray:tmpAppleUpdates];
	
	logit(lcl_vDebug,@"Apple Updates Found, %@",appleUpdates);
	return appleUpdates;
}

- (NSString *)cleanLine:(NSString *)line
{
	// Removes the beginning of the line
	NSString *component = @"*";
	NSString *_lineTrimed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([_lineTrimed hasPrefix:@"*"])
	{
		component = @"* ";
	}
	else if ([_lineTrimed hasPrefix:@"!"])
	{
		component = @"! ";
	}
	
	NSMutableArray *items = [[line componentsSeparatedByString:component] mutableCopy];
	[items removeObjectAtIndex:0];
	// With first item removed put it all back together
	return  [items componentsJoinedByString:component];
}

// Proxy Method
- (NSArray *)scanForCustomUpdatesViaHelper
{
    logit(lcl_vInfo,@"Scanning for custom software updates.");
	[[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(scanForNotification:)
                                                            name: @"ScanForNotification"
                                                          object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scanForNotification:)
                                                 name:@"ScanForNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScanForNotification"
                                                        object:nil
                                                      userInfo:nil];

	NSArray *result = nil;
	MPPatchScan *patchScanObj = [[MPPatchScan alloc] init];
    [patchScanObj setUseDistributedNotification:YES];
	result = [NSArray arrayWithArray:[patchScanObj scanForPatches]];
	return result;
}

- (void)scanForNotification:(NSNotification *)notification
{
    NSDictionary *tmpDict = [notification userInfo];
    
	if(notification)
	{
		logit(lcl_vDebug,@"[scanForNotification]: %@",tmpDict);
	}
}
// Proxy Method
- (int)installAppleSoftwareUpdateViaHelper:(in bycopy NSString *)approvedUpdate
{
    [self setTaskIsRunning:YES];
	[self setTaskTimedOut:NO];
	
	int taskResult = -1;
    
    if (swTask) {
        swTask = nil;
    }
    swTask = [[NSTask alloc] init];
    NSPipe *aPipe = [NSPipe pipe];
    
	[swTask setStandardOutput:aPipe];
	[swTask setStandardError:aPipe];
	
    NSArray *appArgs;
    // Parse the Environment variables for the install
    if ((int)NSAppKitVersionNumber >= 1187 /* 10.8 */) {
        appArgs = [NSArray arrayWithObjects:@"-i", approvedUpdate, nil];
    } else {
        appArgs = [NSArray arrayWithObjects:@"-i", approvedUpdate, nil];
    }
    
    NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
	[environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
    
    [swTask setEnvironment:environment];
    [swTask setLaunchPath:ASUS_BIN_PATH];
    [swTask setArguments:appArgs];
	
    // Launch The NSTask
	@try {
		[swTask launch];
        // If timeout is set start it ...
        if (taskTimeoutValue != 0) {
            [NSThread detachNewThreadSelector:@selector(taskTimeoutThread) toTarget:self withObject:nil];
        }
	}
	@catch (NSException *e)
    {
		logit(lcl_vError,@"Install returned error. %@\n%@",[e reason],[e userInfo]);
		taskResult = 1;
        if(_timeoutTimer) {
            [_timeoutTimer invalidate];
        }
        [self setTaskIsRunning:NO];
        return taskResult;
	}
	
	NSString		*tmpStr;
    NSMutableData	*data = [[NSMutableData alloc] init];
    NSData			*dataChunk = nil;
    NSException		*error = nil;
    
	while(taskTimedOut == NO && ((dataChunk = [[aPipe fileHandleForReading] availableDataOrError:&error]) && [dataChunk length] && error == nil))
	{
        // If the data is not null, then post the data back to the client and log it locally
        tmpStr = [[NSString alloc] initWithData:dataChunk encoding:NSUTF8StringEncoding];
		if ([[tmpStr trim] length] != 0)
        {
            if ([tmpStr containsString:@"PackageKit: Missing bundle path"] == NO) {
                logit(lcl_vDebug,@"%@",tmpStr);
                [self postDataToClient:tmpStr type:kMPInstallStatus];
                // Older Post Back
                NSMutableDictionary *notificationInfo = [NSMutableDictionary dictionary];
                [notificationInfo setObject:tmpStr forKey:@"iData"];
                [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"MPDataAvailableNotification" object:nil userInfo:(NSDictionary *)notificationInfo deliverImmediately:YES];
            } else {
                logit(lcl_vDebug,@"%@",tmpStr);
            }
		}
		
		[data appendData:dataChunk];
		tmpStr = nil;
	}
    
	[[aPipe fileHandleForReading] closeFile];
    
	if (taskTimedOut == YES) {
		logit(lcl_vError,@"Task was terminated due to timeout.");
		[NSThread sleepForTimeInterval:2.0];
		taskResult = 1;
		if(_timeoutTimer) {
            [_timeoutTimer invalidate];
        }
        [self setTaskIsRunning:NO];
        return taskResult;
	}
	
    if([data length] && error == nil)
    {
        if ([swTask terminationStatus] == 0) {
            taskResult = 0;
        } else {
            taskResult = 1;
        }
    } else {
		logit(lcl_vError,@"Install returned error. Code:[%d]",[swTask terminationStatus]);
		taskResult = 1;
	}

	if(_timeoutTimer) {
		[_timeoutTimer invalidate];
	}
	[self setTaskIsRunning:NO];
    return taskResult;
}
// Proxy Method
- (int)installPkgToRootViaHelper:(in bycopy NSString *)pkgPath
{
	return [self installPkgViaHelper:pkgPath target:@"/" env:nil];
}
// Proxy Method
- (int)installPkgToRootViaHelper:(in bycopy NSString *)pkgPath env:(in bycopy NSString *)aEnv;
{
	return [self installPkgViaHelper:pkgPath target:@"/" env:aEnv];
}
// Proxy Method
- (int)installPkgViaHelper:(in bycopy NSString *)pkgPath target:(in bycopy NSString *)aTarget env:(in bycopy NSString *)aEnv
{
	[self setTaskIsRunning:NO];
	[self setInstalltaskResult:99];
	
	[self runInstallPkgTask:pkgPath target:aTarget env:aEnv];
	
	while (taskIsRunning && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
	return self.installtaskResult;
}

-(void)runInstallPkgTask:(NSString *)pkg target:(NSString *)target env:(NSString *)aEnv
{
    
	NSArray *appArgs = [NSArray arrayWithObjects:@"-verboseR", @"-pkg", pkg, @"-target", target, nil];
	logit(lcl_vInfo,@"Pkg Install Args: %@",appArgs);
	
	swTask = [[NSTask alloc] init];
    [swTask setLaunchPath: INSTALLER_BIN_PATH];
    [swTask setArguments: appArgs];
	
	NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
	[environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
	
	if (aEnv) {
		if ([aEnv isEqualToString:@"NA"] == NO && [[aEnv trim] length] > 0) {
			NSArray *l_envArray;
			NSArray *l_envItems;
			l_envArray = [aEnv componentsSeparatedByString:@","];
			for (id item in l_envArray) {
				l_envItems = nil;
				l_envItems = [item componentsSeparatedByString:@"="];
				if ([l_envItems count] == 2) {
					logit(lcl_vDebug,@"Setting env variable(%@=%@).",[l_envItems objectAtIndex:0],[l_envItems objectAtIndex:1]);
					[environment setObject:[l_envItems objectAtIndex:1] forKey:[l_envItems objectAtIndex:0]];
				} else {
					logit(lcl_vError,@"Unable to set env variable. Variable not well formed %@",item);
				}
			}
		}
	}
	
	[swTask setEnvironment:environment];
	
    pipe_task = [NSPipe pipe];
    [swTask setStandardOutput: pipe_task];
    [swTask setStandardError: pipe_task];
	
    fh_task = [pipe_task fileHandleForReading];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(taskCompleted:)
												 name:NSTaskDidTerminateNotification
											   object:swTask];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(taskDataAvailable:)
												 name: NSFileHandleReadCompletionNotification
											   object: fh_task];
	
	[self setTaskIsRunning:YES];
	[swTask launch];
	[fh_task readInBackgroundAndNotify];
}

// Notifications for runInstallPkgTask
- (void)taskDataAvailable:(NSNotification *)aNotification
{
    NSData *incomingData = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if (incomingData && [incomingData length])
    {
        NSString *incomingText = [[NSString alloc] initWithData:incomingData encoding:NSASCIIStringEncoding];
        logit(lcl_vDebug,@"%@",incomingText);
		
        [fh_task readInBackgroundAndNotify];
        return;
    }
}

- (void)taskCompleted:(NSNotification *)aNotification
{
	[self setTaskIsRunning:NO];
    int exitCode = [[aNotification object] terminationStatus];
	[self setInstalltaskResult:exitCode];
}

// Proxy Method
- (int)runScriptViaHelper:(in bycopy NSString *)scriptText
{
	logit(lcl_vDebug,@"Running script\n%@",scriptText);
	int retCode = 1;
	BOOL result = NO;
	MPScript *mps = [[MPScript alloc] init];
	result = [mps runScript:scriptText];
	if (result == YES) {
		retCode = 0;
	}
	return retCode;
}
// Proxy Method
- (void)setLogoutHookViaHelper
{
	// MP 2.2.0 & Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
    NSString *_atFile = @"/private/tmp/.MPAuthRun";
    NSString *_rbFile = @"/private/tmp/.MPRebootRun.plist";
    NSString *_rbText = @"reboot";
    // Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
    NSDictionary *rebootPlist = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"reboot"];
    [rebootPlist writeToFile:_rbFile atomically:YES];
    [_rbText writeToFile:_atFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *_fileAttr =  [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:0777],@"NSFilePosixPermissions",nil];
    [[NSFileManager defaultManager] setAttributes:_fileAttr ofItemAtPath:_rbFile error:NULL];
    [[NSFileManager defaultManager] setAttributes:_fileAttr ofItemAtPath:_atFile error:NULL];
}
// Proxy Method
- (int)setPermissionsForFileViaHelper:(in bycopy NSString *)aFile posixPerms:(unsigned long)posixPermissions
{
    //0664UL
	NSError *err = nil;
	[fm setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:posixPermissions] forKey:NSFilePosixPermissions]
		 ofItemAtPath:aFile
				error:&err];
	
	if (err) {
		logit(lcl_vError,@"%@",[err description]);
		return 1;
	}
    
	return 0;
}
// Proxy Method
- (int)createDirAtPathWithIntermediateDirectoriesViaHelper:(in bycopy NSString *)path intermediateDirectories:(BOOL)withDirs
{
    NSError *err = nil;
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDir];
    if (exists) {
        /* file exists */
        if (isDir) {
            /* file is a directory */
            return 0;
        }  else {
            logit(lcl_vError,@"Directory at path(%@) already exists, but is not a directory.",path);
            return 1;
        }
    } else {
        [fm createDirectoryAtPath:path withIntermediateDirectories:withDirs attributes:nil error:&err];
        if (err) {
            logit(lcl_vError,@"Error creating directory at path(%@). %@",path,[err description]);
            return 1;
        }
    }
    
    return 0;
}
// Proxy Method
- (int)writeDataToFileViaHelper:(id)data toFile:(NSString *)aFile
{
    NSError *err = nil;
    [data writeToFile:aFile atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        logit(lcl_vError,@"Error writing data to file(%@). %@",aFile,[err description]);
        return 1;
    }
    return 0;
}
// Proxy Method
- (void)setDebugLogging:(BOOL)aState
{
    if (aState == YES) {
		lcl_configure_by_name("*", lcl_vDebug);
		logit(lcl_vDebug,@"Debug log level is now enabled.");
	} else {
		lcl_configure_by_name("*", lcl_vInfo);
		logit(lcl_vInfo,@"Info log level is now enabled.");
	}
}

#pragma mark SelfPatch Misc
- (NSString *)getSizeFromDescription:(NSString *)aDesc
{
	NSArray *tmpArr1 = [aDesc componentsSeparatedByString:@","];
	NSArray *tmpArr2 = [[[tmpArr1 objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@" "];
	return [[tmpArr2 objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)getRecommendedFromDescription:(NSString *)aDesc
{
	NSRange textRange;
	textRange =[aDesc rangeOfString:@"recommended"];
	
	if(textRange.location != NSNotFound) {
		return @"Y";
	} else {
		return @"N";
	}
	
	return @"N";
}
@end
