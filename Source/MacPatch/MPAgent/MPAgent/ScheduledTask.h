//
//  ScheduledTask.h
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

typedef NS_ENUM(NSInteger, TaskType) {
    TaskTypeInterval,
    TaskTypeDaily,
    TaskTypeWeekly
};

NS_ASSUME_NONNULL_BEGIN

@interface ScheduledTask : NSObject

@property (nonatomic, copy) NSString *taskName;
@property (nonatomic, assign) TaskType taskType;
@property (nonatomic, copy) void(^taskBlock)(void);
@property (nonatomic, strong) dispatch_source_t timer;
@property (nonatomic, assign) uint64_t interval;
@property (nonatomic, assign) NSInteger hour;
@property (nonatomic, assign) NSInteger minute;
@property (nonatomic, assign) NSInteger weekday;
@property (nonatomic, assign) NSInteger week;
@property (nonatomic, assign) NSArray *weekDays;
@property (nonatomic, assign) BOOL isRandom;
@property (nonatomic, assign) BOOL isRunning;

@end

NS_ASSUME_NONNULL_END
