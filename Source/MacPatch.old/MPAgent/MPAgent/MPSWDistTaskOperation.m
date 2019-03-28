//
//  MPSWDiskTaskOperation.m
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

#import "MPSWDistTaskOperation.h"
#import "MPSWTasks.h"
#import "MPSWInstaller.h"
#import "MPSettings.h"

#define K_INSTALLED_FILE    @".installed.plist"

@implementation MPSWDistTaskOperation

@synthesize isExecuting;
@synthesize isFinished;
@synthesize _fileHash;
@synthesize _timerInterval;
@synthesize l_queue;
@synthesize _swDiskTaskListHash;
@synthesize sw_dir;

- (id) init 
{
    self = [super init];
    if (self)
    {
        settings        = [MPSettings sharedInstance];
        fm              = [NSFileManager defaultManager];
        isExecuting     = NO;
        isFinished      = NO;
        
        [self set_fileHash:NULL];
        
        mpc     = [[MPCrypto alloc] init];
        l_queue = [[NSOperationQueue alloc] init];
        [l_queue setMaxConcurrentOperationCount:1]; // Only do one install at a time
        sw_dir = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"sw"];
        // Set Data Directory
        if ([fm fileExistsAtPath:SOFTWARE_DATA_DIR] == NO)
        {
            NSError *err = nil;
            NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
            [fm createDirectoryAtPath:SOFTWARE_DATA_DIR withIntermediateDirectories:YES attributes:attributes error:&err];
            if (err) {
                logit(lcl_vError,@"%@",[err description]);
            }
        }
        if ([fm fileExistsAtPath:sw_dir] == NO)
        {
            NSError *err = nil;
            NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
            [fm createDirectoryAtPath:sw_dir withIntermediateDirectories:YES attributes:attributes error:&err];
            if (err) {
                logit(lcl_vError,@"%@",[err description]);
            }
            NSURL *furl = [NSURL URLWithString:sw_dir];
            [furl setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsHiddenKey error:NULL];
        }
    }
    return self;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (void)cancel
{
    [self finish];
}

- (void)finish
{
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    isExecuting = NO;
    isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (void)start
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        isFinished = YES;
        [self didChangeValueForKey:@"isFinished"];
    } else {
        [self willChangeValueForKey:@"isExecuting"];
        [self performSelectorOnMainThread:@selector(main) 
                               withObject:nil 
                            waitUntilDone:NO];
        isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)main
{
    logit(lcl_vInfo,@"Run Mandatory Software Installs");
    @try {
		[self checkAndInstallMandatoryApplications];
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

#pragma mark - SW Dist Methods

- (void)checkAndInstallMandatoryApplications
{
    MPSWTasks   *sw     = [[MPSWTasks alloc] init];
    NSError     *err    = nil;
    NSArray     *_tasks = [sw getSoftwareTasksForGroup:&err];
    NSArray     *mandatoryInstllTasks;
    if (err) {
        logit(lcl_vError,@"%@",[[err userInfo] objectForKey:@"NSLocalizedDescription"]);
        return;
    }
    mandatoryInstllTasks = [self filterMandatorySoftwareContent:_tasks];
    
    // Check to see if there is anything to install
    if (mandatoryInstllTasks == nil || [mandatoryInstllTasks count] <= 0)
    {
        logit(lcl_vInfo,@"No mandatory software tasks to install.");
        return;
    }
    
    MPSWInstaller  *mpCatalogD;
    MPDiskUtil *mpd = [[MPDiskUtil alloc] init];
    
    // Install the mandatory software 
    for (NSDictionary *d in mandatoryInstllTasks) 
    {
        logit(lcl_vInfo,@"Installing %@ (%@).",[d objectForKey:@"name"],[d objectForKey:@"id"]);
        logit(lcl_vInfo,@"INFO: %@",[d valueForKeyPath:@"Software.sw_type"]);
        
        // Create Path to download software to
        NSString *swLoc = NULL;
        swLoc = [sw_dir stringByAppendingPathComponent:d[@"id"]];
        
        // Verify Disk space requirements before downloading and installing
        NSScanner *scanner = [NSScanner scannerWithString:[d valueForKeyPath:@"Software.sw_size"]];
        long long stringToLong;
        if(![scanner scanLongLong:&stringToLong])
        {
            logit(lcl_vError,@"Unable to convert size %@",[d valueForKeyPath:@"Software.sw_size"]);
            continue;
        }
        
        if ([mpd diskHasEnoughSpaceForPackage:stringToLong] == NO) 
        {
            logit(lcl_vError,@"This system does not have enough free disk space to install the following software %@",d[@"name"]);
            continue;
        }
        
        // Create Download URL Path
        NSString *_url = [NSString stringWithFormat:@"/mp-content%@",[d valueForKeyPath:@"Software.sw_url"]];
        logit(lcl_vInfo,@"Download software from: %@",_url);
        
        BOOL isDir;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        if ([fm fileExistsAtPath:swLoc isDirectory:&isDir] == NO)
        {
            [fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:attributes error:NULL];
        }
        else
        {
            if (isDir == NO)
            {
                // Item is not a directory so we need to remove it and create our dir structure
                [fm removeItemAtPath:swLoc error:NULL];
                [fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:attributes error:NULL];
            }
        }
        
        // Download the software
        NSError *error = nil;
        NSString *file = [self downloadFile:swLoc error:&error];
        if (error)
        {
            file = nil;
            continue;
        }
        
        // Install the software
        logit(lcl_vDebug,@"Begin install for (%@).",[d objectForKey:@"name"]);
        int result = -1;
        int pResult = -1;
        
        mpCatalogD = [[MPSWInstaller alloc] init];
        result = [mpCatalogD installSoftware:d];
        if (result == 0) 
        {
            if ([[d valueForKeyPath:@"Software.auto_patch"] isEqualTo:@"1"]) 
            {
                logit(lcl_vDebug,@"Auto Patching is enabled, begin patching...");
                pResult = [mpCatalogD patchSoftware:d];
                if (pResult == 0) {
                    logit(lcl_vDebug,@"Auto Patching is complete...");
                }
                sleep(5); // Dont remeber why I'm doing this :-P
            }
            // Register Installed Item for Catalog
            [self softwareItemInstalled:d];
            [self postInstallResults:result resultText:@"" task:d];
        }
        mpCatalogD = nil;

    }
}

- (NSString *)downloadFile:(NSString *)urlPath error:(NSError **)err
{
    MPHTTPRequest *req;
    NSString *dlResult;
    NSError *dlerr = nil;
    
    req = [[MPHTTPRequest alloc] init];
    dlResult = [req runSyncFileDownload:urlPath downloadDirectory:@"/tmp" error:&dlerr];
    if (dlerr) {
        if (err != NULL) *err = dlerr;
        logit(lcl_vError,@"Error downloading %@",urlPath.lastPathComponent);
        logit(lcl_vError,@"%@",dlerr.localizedDescription);
    }
    
    return dlResult;
}

#pragma mark Helpers Methods

- (BOOL)softwareItemInstalled:(NSDictionary *)dict
{
    NSString *installFile = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:K_INSTALLED_FILE];
    NSMutableDictionary *installData = [[NSMutableDictionary alloc] init];
    [installData setObject:[NSDate date] forKey:@"installDate"];
    [installData setObject:[dict objectForKey:@"id"] forKey:@"id"];
    [installData setObject:[dict objectForKey:@"name"] forKey:@"name"];
    if ([dict objectForKey:@"sw_uninstall"]) {
        [installData setObject:[dict objectForKey:@"sw_uninstall"] forKey:@"sw_uninstall"];    
    } else {
        [installData setObject:@"" forKey:@"sw_uninstall"];
    }
    NSMutableArray *_data;
    if ([fm fileExistsAtPath:installFile]) {
        _data = [NSMutableArray arrayWithContentsOfFile:installFile];
    } else {
        if (![fm fileExistsAtPath:sw_dir]) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
            [fm createDirectoryAtPath:sw_dir withIntermediateDirectories:YES attributes:attributes error:NULL];
        }
        _data = [NSMutableArray array];
    }
    [_data addObject:installData];
    [_data writeToFile:installFile atomically:YES];
    return YES;
}

- (NSArray *)filterMandatorySoftwareContent:(NSArray *)content
{
    NSArray *_a;
    int c = 0;
    NSMutableDictionary *d;
    NSDictionary *_SoftwareCriteria;
    NSMutableArray *_MandatorySoftware = [[NSMutableArray alloc] init];
    
    if (content) 
    {
        /* If there is content */
        [NSKeyedArchiver archiveRootObject:content toFile:[SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"content.plist"]];
        _a = [NSKeyedUnarchiver unarchiveObjectWithFile:[SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"content.plist"]];
        for (id item in _a) 
        {
            d = [[NSMutableDictionary alloc] initWithDictionary:item];
            
            // Check for Mandatory apps
            if ([[d objectForKey:@"sw_task_type"] containsString:@"m" ignoringCase:YES] == NO) {
                continue;
            }
            
            // Check Install Date Info
            NSDate *now = [NSDate date];
            NSDate *startDate = [NSDate dateFromString:[d objectForKey:@"sw_start_datetime"]];
            NSDate *endDate = [NSDate dateFromString:[d objectForKey:@"sw_end_datetime"]];

            if ([now timeIntervalSince1970] < [startDate timeIntervalSince1970]) {
                // Software is not ready for deployment
                continue;
            }
            
            // If it's a Optional / Mandatory App then we wait for the end date
            if ([[d objectForKey:@"sw_task_type"] containsString:@"o" ignoringCase:YES]) 
            {
                if ([now timeIntervalSince1970] >= [endDate timeIntervalSince1970]) 
                {
                    logit(lcl_vDebug,@"Optional/Mandatory date has been reached for install.");
                } else {
                    continue;
                }
            }
            
            // Check Simple Requirements
            c = 0;
            MPOSCheck *mpos = [[MPOSCheck alloc] init];
            _SoftwareCriteria = [item objectForKey:@"SoftwareCriteria"];
            // OSArch
            if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
                logit(lcl_vInfo,@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
            } else {
                logit(lcl_vInfo,@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
                c++;
            }
            // OSType
            if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
                logit(lcl_vInfo,@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
            } else {
                logit(lcl_vInfo,@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
                c++;
            }
            // OSVersion
            if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
                logit(lcl_vInfo,@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
            } else {
                logit(lcl_vInfo,@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
                c++;
            }
            mpos = nil;
            // Did not pass the criteria check
            if (c >= 1) {
                continue;
            }

            // Check to see if it's installed
            if ([self softwareTaskInstalled:[d objectForKey:@"id"]] == NO) {
                // Has not been installed, and is mandatory
                logit(lcl_vInfo,@"Adding %@ to mandatory installs.",[d objectForKey:@"name"]);
                [_MandatorySoftware addObject:d];
            }

            d = nil;
        }
    }
    
    // Echo which apps are going to be installed.
    for (id x in _MandatorySoftware) {
        logit(lcl_vInfo,@"Approved Mandatory Software task: %@",[x objectForKey:@"name"]);
    }
    NSArray *results = [NSArray arrayWithArray:_MandatorySoftware];
    return results;
}

- (BOOL)softwareTaskInstalled:(NSString *)aTaskID
{
    NSString *installFile = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:K_INSTALLED_FILE];
    if ([fm fileExistsAtPath:installFile]) {
        NSArray *a = [NSArray arrayWithContentsOfFile:installFile];
        for (int i = 0; i < [a count];i++) {
            if ([[[a objectAtIndex:i] objectForKey:@"id"] isEqualTo:aTaskID]) {
                return YES; // It's installed ... no need to install
            }
        }
    }
    
    return NO;
}

- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict
{
    @autoreleasepool {
        MPSWTasks *swt = [[MPSWTasks alloc] init];
        int result = -1;
        result = [swt postInstallResults:resultNo resultText:resultString task:taskDict];
        qldebug(@"Post Install Result: %d",result);
    }
}

#pragma mark - Delegates not used
- (void)appendDownloadProgress:(double)aNumber; {}
- (void)appendDownloadProgressPercent:(NSString *)aPercent; {}
- (void)downloadStarted; {}
- (void)downloadFinished; {}
- (void)downloadError; {}

@end
