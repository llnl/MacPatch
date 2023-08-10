//
//  MPNSTask.m
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

#import "MPNSTask.h"
#import "MacPatch.h"

#undef  ql_component
#define ql_component lcl_cMPNSTask

@interface MPNSTask ()
{
    NSTask *task;
    NSTimer *taskTimer;
    NSFileManager *fm;
}

@property (nonatomic, assign, readwrite) int         taskTerminationStatus;
@property (nonatomic, strong)            NSMutableArray *taskObserverArray;

@property (strong)                       NSTimer     *taskTimeoutTimer;
@property (nonatomic, assign, readwrite) BOOL        taskTimedOut;
@property (nonatomic, assign, readwrite) BOOL        taskIsRunning;

@property (nonatomic, strong) NSData *taskData;
@property (nonatomic, weak) NSString *taskDataLastLine;

@end

@implementation MPNSTask

@synthesize taskTerminationStatus;
@synthesize taskTimeoutTimer;
@synthesize taskTimeoutValue;
@synthesize taskTimedOut;
@synthesize taskIsRunning;

- (id)init
{
    self = [super init];
	if (self)
	{
        fm = [NSFileManager defaultManager];
        [self setTaskTimeoutValue:900];
        [self setTaskIsRunning:NO];
        [self setTaskTimedOut:NO];
        [self setTaskTerminationStatus:-99];
    }
	
    return self;
}

- (NSString *)runTask:(NSString *)binPath binArgs:(NSArray *)args error:(NSError **)err
{
    return [self runTaskWithBinPath:binPath args:args environment:nil error:err];
}

- (NSString *)runTask:(NSString *)binPath binArgs:(NSArray *)args environment:(NSDictionary *)env error:(NSError **)err
{
    return [self runTaskWithBinPath:binPath args:args environment:env error:err];
}

- (NSString *)runTaskWithBinPath:(NSString *)binPath args:(NSArray *)args error:(NSError **)error
{
    return [self runTaskWithBinPath:binPath args:args environment:nil error:error];
}

- (NSString *)runTaskWithBinPath:(NSString *)binPath args:(NSArray *)args environment:(NSDictionary *)env error:(NSError **)error
{
    NSError *err = nil;
    NSMutableArray *tmpResults = [NSMutableArray new];
    int taskResult = -99;
    [self setTaskTerminationStatus:taskResult];
    
    if (![fm fileExistsAtPath:binPath]) {
        if (error != NULL) {
            err = [NSError errorWithDomain:@"gov.llnl.mptask" code:taskResult userInfo:@{NSLocalizedDescriptionKey:@"Task failed, bin path was not found."}];
            *error = err;
        } else {
            qlerror(@"Task failed, bin path was not found.");
        }
        return @"ERR";
    }
    
    BOOL useTimeOutTimer = NO;
    if (taskTimeoutValue != 0) useTimeOutTimer = YES;
    
    taskIsRunning = YES;
    taskTimedOut = NO;
    
    task = [[NSTask alloc] init];
    task.launchPath = binPath;
    if (args) task.arguments = args;
    if (env) task.environment = env;

    NSPipe *stdoutPipe = [NSPipe pipe];
    task.standardInput = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stdoutPipe;
    

    NSFileHandle *stdoutHandle = [stdoutPipe fileHandleForReading];
    [stdoutHandle waitForDataInBackgroundAndNotify];
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSFileHandleDataAvailableNotification
                                                                    object:stdoutHandle
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note)
    {
        // This block is called when output from the task is available.
        NSData *dataRead = [stdoutHandle availableData];
        NSString *stringRead = [[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding];
        NSArray *parsedString;
        if ([[stringRead trim] length] != 0)
        {
            if (useTimeOutTimer) [self resetTimer];
            if (![self.taskDataLastLine isEqualToString:[stringRead trim]])
            {
                parsedString = [self parseTaskStdout:stringRead];
                for (NSString *line in parsedString) {
                    NSString *lineT = [line trim];
                    if ([lineT length] != 0) {
                        if ([lineT containsString:@"PackageKit: Missing bundle path"] == NO) {
                            [self postStatusToDelegate:lineT];
                            [tmpResults addObject:lineT];
                            qlinfo(@"task stdout: %@", lineT);
                        }
                    }
                    lineT = nil;
                }
                
                [self setTaskDataLastLine:[stringRead trim]];
            }
        }
        [stdoutHandle waitForDataInBackgroundAndNotify];
    }];
    // If there is a task timeout timer
    if (useTimeOutTimer) {
        if (!taskTimer) {
            [self resetTimer];
        }
    }
    
    [task launch];          // Start the task
    [task waitUntilExit];   // Wait for the task to complete
    
    taskResult = task.terminationStatus;
    [self setTaskTerminationStatus:taskResult];
    
    if (taskResult == 0) {
        qlinfo(@"Task succeeded: %d",taskResult);
    } else {
        // Post Failure data to web service
        [self postFailurToWebService:binPath args:args statusCode:taskResult stdOut:[tmpResults componentsJoinedByString:@"\n"]];
        
        qlerror(@"Task failed: %d",taskResult);
        err = [NSError errorWithDomain:@"gov.llnl.mptask" code:taskResult userInfo:@{NSLocalizedDescriptionKey:@"Task failed."}];
        if (error != NULL) *error = err;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    if (!taskTimer) {
        [taskTimer invalidate];
        taskTimer = nil;
    }

    return [tmpResults componentsJoinedByString:@"\n"];
}

#pragma mark - Private

- (NSArray *)parseTaskStdout:(NSString *)stdoutStr
{
    NSArray *res = [NSArray new];
    NSCharacterSet *separator = [NSCharacterSet newlineCharacterSet];
    res = [stdoutStr componentsSeparatedByCharactersInSet:separator];
    return res;
}

- (void)resetTimer
{
    if (taskTimer) {
        [taskTimer invalidate];
    }

    taskTimer = [NSTimer scheduledTimerWithTimeInterval:taskTimeoutValue
                                                   target:self selector:@selector(taskTimerExceeded)
                                                 userInfo:nil repeats:NO];
}

- (void)taskTimerExceeded
{
    qlinfo(@"taskTimerExceeded");
    taskTimedOut = YES;
    [task terminate];
}

- (void)postFailurToWebService:(NSString *)binPath args:(NSArray *)args statusCode:(int)status stdOut:(NSString *)stdOut
{
    MPSettings *s = [MPSettings sharedInstance];
    NSDictionary *d = @{@"cuuid":s.ccuid, @"binPath":binPath, @"binArgs":args, @"statusCode":@(status), @"stdOut":stdOut};
    qlinfo(@"postFailurToWebService ---");
    qlinfo(@"%@",d);
}

#pragma mark - Delegate Helper

- (void)postStatusToDelegate:(NSString *)str, ...
{
    va_list va;
    va_start(va, str);
    NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
    va_end(va);
    
    [self.delegate taskStatus:self status:string];
}
@end
