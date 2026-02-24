//
//  TasksDaemon.m
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

#import "TasksDaemon.h"
#import <Foundation/Foundation.h>
#import "ScheduledTask.h"
#import "TaskScheduler.h"
#import "MacPatch.h"

@implementation TasksDaemon

- (void)runAsDaemon
{
    //NSString *configFile = @"/Library/Application Support/MacPatch/CurrentTasks.plist";
    //TaskScheduler *scheduler = [[TaskScheduler alloc] initWithConfigFile:configFile];
    TaskScheduler *scheduler = [[TaskScheduler alloc] init];

    // Register as shared after successful init (if available)
    if ([TaskScheduler respondsToSelector:@selector(setSharedScheduler:)]) {
        [TaskScheduler setSharedScheduler:scheduler];
    }
    
    // Try to load from config, otherwise add default tasks
    BOOL res = [scheduler loadConfigFromFile];
    
    // Show loaded tasks
    [scheduler listAllTasks];
    
    // Signal handling via GCD dispatch sources (blocks are allowed here)
    __block TaskScheduler *blockScheduler = scheduler;

    // Helper to create a signal source
    void (^setupSignal)(int, void (^)(void)) = ^(int signum, void (^handler)(void)) {
        signal(signum, SIG_IGN); // ensure default handling is disabled so GCD receives it
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, signum, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{
            handler();
        });
        dispatch_resume(source);
    };

    // SIGTERM - graceful shutdown
    setupSignal(SIGTERM, ^{
        NSLog(@"Received SIGTERM, shutting down gracefully...");
        [blockScheduler stopAllTasks];
        exit(0);
    });

    // SIGINT - graceful shutdown
    setupSignal(SIGINT, ^{
        NSLog(@"Received SIGINT, shutting down gracefully...");
        [blockScheduler stopAllTasks];
        exit(0);
    });

    // SIGHUP - reload configuration
    setupSignal(SIGHUP, ^{
        NSLog(@"Received SIGHUP, reloading configuration...");
        [blockScheduler reloadTasksFromConfig];
        [blockScheduler listAllTasks];
    });

    // SIGUSR1 - reload all tasks (restart without config change)
    setupSignal(SIGUSR1, ^{
        NSLog(@"Received SIGUSR1, reloading all tasks...");
        [blockScheduler reloadAllTasks];
        [blockScheduler listAllTasks];
    });

    // SIGUSR2 - list all tasks
    setupSignal(SIGUSR2, ^{
        [blockScheduler listAllTasks];
    });
    
    LogInfo(@"Daemon started.");
    /*
    NSLog(@"Daemon started. Send signals to control:");
    NSLog(@"  kill -HUP <pid>   : Reload from config file");
    NSLog(@"  kill -USR1 <pid>  : Reload all tasks");
    NSLog(@"  kill -USR2 <pid>  : List all tasks");
    NSLog(@"  kill -TERM <pid>  : Graceful shutdown");
    */
    // Keep running
    [[NSRunLoop currentRunLoop] run];
    
}

@end
