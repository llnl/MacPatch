//
//  InstallPackage.m
//  MPLoginAgent
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

#import "InstallPackage.h"
#import "MacPatch.h"

#undef  ql_component
#define ql_component lcl_cMain

@interface InstallPackage ()

@property (nonatomic,strong)             NSThread *timeoutThread;
@property (nonatomic, assign)            int       taskTimeoutValue;
@property (nonatomic, assign)            int       taskTimeoutCount;
@property (nonatomic, assign, readwrite) BOOL      taskTimedOut;

- (void)startTaskTimeoutThread;
- (void)taskTimeoutThread;
- (void)requestTaskTermination;

@end

@implementation InstallPackage

@synthesize task;
@synthesize timeoutThread;
@synthesize taskTimeoutValue;
@synthesize taskTimeoutCount;
@synthesize taskTimedOut;
@synthesize installtaskResult;

- (id)init
{
    if (self = [super init])
    {
        [self setTaskTimeoutValue:600];
        [self setTaskTimedOut:NO];
    }
    
    return self;
}

- (int)installPkgToRoot:(NSString *)pkgPath
{
    return [self installPkg:pkgPath target:@"/" env:nil];
}

- (int)installPkgToRoot:(NSString *)pkgPath env:(NSString *)aEnv;
{
    return [self installPkg:pkgPath target:@"/" env:aEnv];
}

- (int)installPkg:(NSString *)pkgPath target:(NSString *)aTarget env:(NSString *)aEnv
{
    // ---------------------------------------------
    // Default Installer Env Variables
    // ---------------------------------------------
    NSDictionary *defaultEnv = [[NSProcessInfo processInfo] environment];
    NSMutableDictionary *env = [[NSMutableDictionary alloc] initWithDictionary:defaultEnv];
    [env setObject:@"YES" forKey:@"NSUnbufferedIO"];
    [env setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
    
    // ---------------------------------------------
    // Process Installe Env string from patch
    // ---------------------------------------------
    if (aEnv)
    {
        if ([aEnv isEqualToString:@"NA"] == NO && [[aEnv trim] length] > 0) {
            NSArray *l_envArray;
            NSArray *l_envItems;
            l_envArray = [aEnv componentsSeparatedByString:@","];
            for (id item in l_envArray) {
                l_envItems = nil;
                l_envItems = [item componentsSeparatedByString:@"="];
                if ([l_envItems count] == 2) {
                    logit(lcl_vDebug,@"Setting env variable(%@=%@).",[l_envItems objectAtIndex:0],[l_envItems objectAtIndex:1]);
                    [env setObject:[l_envItems objectAtIndex:1] forKey:[l_envItems objectAtIndex:0]];
                } else {
                    logit(lcl_vError,@"Unable to set env variable. Variable not well formed %@",item);
                }
            }
        }
    }
    
    // ---------------------------------------------
    // Installer Args
    // ---------------------------------------------
    NSArray *appArgs = @[@"-verboseR", @"-allowUntrusted", @"-pkg", pkgPath, @"-target", aTarget];
    logit(lcl_vInfo,@"Pkg Install Args: %@",appArgs);
    
    GCDTask *gTask = [[GCDTask alloc] init];
    [gTask setArguments:appArgs];
    [gTask setLaunchPath:INSTALLER_BIN_PATH];
    [gTask setEnvironment:env];
    gcdTask = gTask;
    
    // ---------------------------------------------
    // Start Install
    // ---------------------------------------------
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block int exitCode = 0;
    [gTask launchWithOutputBlock:^(NSData *stdOutData) {
        NSString *output = [[NSString alloc] initWithData:stdOutData encoding:NSUTF8StringEncoding];
        logit(lcl_vInfo,@"%@",output);
        
    } andErrorBlock:^(NSData *stdErrData) {
        NSString *output = [[NSString alloc] initWithData:stdErrData encoding:NSUTF8StringEncoding];
        logit(lcl_vError,@"[stdErr]: %@",output);
        
    } onLaunch:^{
        logit(lcl_vInfo,@"Installer task has started running.");
        [self startTaskTimeoutThread];
        
    } onExit:^(int exitStatus) {
        if (exitStatus == 0) {
            logit(lcl_vInfo,@"Installer task has now exited. Exit status %d",exitStatus);
        } else {
            logit(lcl_vError,@"Installer task has now exited. Exit status %d",exitStatus);
        }
        exitCode = exitStatus;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    [self setInstalltaskResult:exitCode];
    return exitCode;
}

#pragma mark - Timeout

- (void)startTaskTimeoutThread
{
    logit(lcl_vInfo,@"Start timeout thread");
    timeoutThread = [[NSThread alloc] initWithTarget:self selector:@selector(taskTimeoutThread) object:nil];
    [timeoutThread start];
}

- (void)taskTimeoutThread
{
    @autoreleasepool
    {
        while (self.taskTimeoutValue > self.taskTimeoutCount)
        {
            [NSThread sleepForTimeInterval:1.0];
            taskTimeoutCount++;
        }
        [self requestTaskTermination]; // Task timed out
        [self setTaskTimedOut:YES];
    }
}

- (void)requestTaskTermination
{
    logit(lcl_vError,@"Task timedout, killing task.");
    [gcdTask RequestTermination];
}

@end
