//
//  TaskScheduler.h
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

#import <Foundation/Foundation.h>
#import "ScheduledTask.h"

NS_ASSUME_NONNULL_BEGIN

@interface TaskScheduler : NSObject

+ (instancetype)sharedScheduler;
+ (void)setSharedScheduler:(TaskScheduler *)scheduler; 

@property (nonatomic, strong) NSMutableDictionary<NSString *, ScheduledTask *> *tasks;
@property (nonatomic, strong) dispatch_queue_t schedulerQueue;
@property (nonatomic, strong) NSString *configFilePath;

- (instancetype)initWithConfigFile:(NSString *)configPath;
- (BOOL)loadConfigFromFile;

// Task management
- (void)addIntervalTask:(NSString *)name
               interval:(uint64_t)seconds
              taskBlock:(void(^)(void))taskBlock;

- (void)addDailyTask:(NSString *)name
                hour:(NSInteger)hour
              minute:(NSInteger)minute
           taskBlock:(void(^)(void))taskBlock;

- (void)addWeeklyTask:(NSString *)name
              weekday:(NSInteger)weekday
                 hour:(NSInteger)hour
               minute:(NSInteger)minute
            taskBlock:(void(^)(void))taskBlock;

// Control methods
- (void)stopAllTasks;
- (void)stopTask:(NSString *)name;
- (void)startTask:(NSString *)name;
- (void)reloadAllTasks;
- (void)reloadTasksFromConfig;
- (BOOL)saveConfigToFile;
- (void)listAllTasks;

@end

NS_ASSUME_NONNULL_END
