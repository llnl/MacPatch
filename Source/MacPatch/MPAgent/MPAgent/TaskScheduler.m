//
//  TaskScheduler.m
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

#import "TaskScheduler.h"
#import "NSDate+Helper.h"
#import "NSDate+MPHelper.h"
#import "TaskCommands.h"
#import "MPTaskValidate.h"
#import "MacPatch.h"

@implementation TaskScheduler

static TaskScheduler *_shared = nil;

+ (instancetype)sharedScheduler {
    @synchronized (self) {
        return _shared;
    }
}

+ (void)setSharedScheduler:(nonnull TaskScheduler *)scheduler {
    _shared = scheduler;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _tasks = [NSMutableDictionary dictionary];
        _schedulerQueue = dispatch_queue_create("gov.llnl.mpagent.daemon.scheduler", DISPATCH_QUEUE_CONCURRENT);
        _configFilePath = MP_AGENT_SETTINGS;
    }
    return self;
}

- (instancetype)initWithConfigFile:(NSString *)configPath {
    self = [super init];
    if (self) {
        _tasks = [NSMutableDictionary dictionary];
        _schedulerQueue = dispatch_queue_create("gov.llnl.mpagent.daemon.scheduler", DISPATCH_QUEUE_CONCURRENT);
        _configFilePath = configPath;
    }
    return self;
}

- (void)stopAllTasks
{
    LogInfo(@"=== Stopping all tasks ===");
    
    for (ScheduledTask *task in self.tasks.allValues) {
        if (task.timer && task.isRunning) {
            dispatch_source_cancel(task.timer);
            task.timer = nil;
            task.isRunning = NO;
            LogInfo(@"Stopped task: %@", task.taskName);
        }
    }
    
    LogInfo(@"All tasks stopped. Total: %lu", (unsigned long)self.tasks.count);
}

- (void)stopTask:(NSString *)name
{
    ScheduledTask *task = self.tasks[name];
    if (task && task.timer && task.isRunning) {
        dispatch_source_cancel(task.timer);
        task.timer = nil;
        task.isRunning = NO;
        LogInfo(@"Stopped task: %@", name);
    } else {
        LogInfo(@"Task not found or not running: %@", name);
    }
}

- (void)startTask:(NSString *)name
{
    ScheduledTask *task = self.tasks[name];
    if (!task) {
        LogInfo(@"Task not found: %@", name);
        return;
    }
    
    if (task.isRunning) {
        LogInfo(@"Task already running: %@", name);
        return;
    }
    
    // Restart the task based on its type
    switch (task.taskType) {
        case TaskTypeInterval:
            [self startIntervalTask:task];
            break;
        case TaskTypeDaily:
            [self scheduleDailyTask:task];
            break;
        case TaskTypeWeekly:
            [self scheduleWeeklyTask:task];
            break;
    }
    
    NSLog(@"Started task: %@", name);
}

- (void)reloadAllTasks
{
    LogInfo(@"=== Reloading all tasks ===");
    
    // Stop all running tasks
    [self stopAllTasks];
    
    // Small delay to ensure cleanup
    [NSThread sleepForTimeInterval:0.5];
    
    // Restart all tasks
    for (ScheduledTask *task in self.tasks.allValues) {
        [self startTask:task.taskName];
    }
    
    LogInfo(@"All tasks reloaded. Total: %lu", (unsigned long)self.tasks.count);
}

- (void)reloadTasksFromConfig
{
    LogInfo(@"=== Reloading tasks from config file ===");
    
    // Stop all existing tasks
    [self stopAllTasks];
    
    // Clear task dictionary
    [self.tasks removeAllObjects];
    
    // Load configuration from file
    if (![self loadConfigFromFile]) {
        LogError(@"Failed to load config file, keeping existing tasks");
        return;
    }
    
    LogInfo(@"Tasks reloaded from config. Total: %lu", (unsigned long)self.tasks.count);
}

// Loads from MacPatch CurrentTasks.plist
- (BOOL)loadConfigFromFile
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.configFilePath]) {
        LogError(@"Config file not found: %@", self.configFilePath);
        return NO;
    }
    
    NSArray *tasksArray;
    NSDictionary *settingsFile = [NSDictionary dictionaryWithContentsOfFile:self.configFilePath];
    if (!settingsFile) {
        LogError(@"[loadConfigFromFile]: Failed to read config file");
        return NO;
    }
    id tasks = [settingsFile valueForKeyPath:@"settings.tasks.data"];
    if (tasks && tasks != [NSNull null]) {
        tasksArray = [tasks copy];
    } else {
        LogError(@"[loadConfigFromFile]: Failed to get tasks data from config file.");
        return NO;
    }
    
    int taskValidation = 99;
    MPTaskValidate *taskValidator = [[MPTaskValidate alloc] init];
    NSDate *currentDate = [NSDate date];
    for (NSDictionary *task in tasksArray)
    {
        // Make Sure the task is a dictionary
        if (![task isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        
        // Check if active key exists
        if (![task objectForKey:@"active"]) continue;
        
        id activeValue = task[@"active"];
        // Treat missing or non-string active as active; skip if explicitly "0"
        if ([activeValue isKindOfClass:[NSString class]] && [(NSString *)activeValue isEqualToString:@"0"]) {
            continue;
        }
        
        taskValidation = [taskValidator validateTask:task];
        if (taskValidation != 0) {
            LogError(@"There was an error (%d) validating the task, %@", taskValidation, task[@"name"]);
            continue;
        }
        
        NSString *name = task[@"name"];
        NSDate *startDate = [NSDate shortDateFromString:task[@"startdate"]];
        NSDate *endDate = [NSDate shortDateFromString:task[@"enddate"]];
        
        // Check if currentDate is between startDate and endDate (inclusive)
        if ([currentDate compare:startDate] != NSOrderedAscending && [currentDate compare:endDate] != NSOrderedDescending) {
            LogDebug(@"[%@]: Date is between start and end.",name);
        } else {
            LogWarning(@"[%@]: Current Date %@ is outside the start and end date range.", name, currentDate);
            continue;
        }
        
        NSArray *intervals = [[task objectForKey:@"interval"] componentsSeparatedByString:@"@"];
        NSString *type = [[intervals firstObject] lowercaseString];

        // Parse interval string: "Once@Time", "Recurring@Daily,Weekly,Monthly@Time", "Every@seconds", "EVERYRAND@seconds"
        // Treating Everyrand like every for right now.
        if ([type isEqualToString:@"every"] || [type isEqualToString:@"everyrand"])
        {
            if ([intervals count] != 2) {
                LogInfo(@"Skipping interval task '%@': missing interval value after 'every@'", name);
                continue;
            }

            NSString *intervalString = [intervals[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            unsigned long long secondsValue = 0;
            if ([intervalString length] > 0) {
                NSScanner *scanner = [NSScanner scannerWithString:intervalString];
                long long scanned = 0;
                if ([scanner scanLongLong:&scanned] && scanner.isAtEnd && scanned >= 0) {
                    secondsValue = (unsigned long long)scanned;
                }
            }

            if (secondsValue == 0) {
                LogInfo(@"Skipping interval task '%@': invalid interval '%@'", name, intervalString);
                continue;
            }
            
            // Add the task
            [self addIntervalTask:name interval:secondsValue taskBlock:[self taskBlockForName:task[@"cmd"]]];
        }
        else if ([type isEqualToString:@"recurring"])
        {
            // Check to make sure the recurring interval count matches
            if ([intervals count] < 3) {
                LogInfo(@"Skipping interval task '%@': interval syntax %@ is malformed.", name, [task objectForKey:@"interval"]);
                continue;
            }
            
            NSString *recurringType = [[intervals[1] lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            if ([recurringType isEqualToString:@"daily"])
            {
                NSString *timeStr = [intervals[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSDateComponents *time = [NSDate timeComponentsFromString:timeStr];
                
                NSInteger hour = time.hour;
                NSInteger minute = time.minute;
                if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
                    LogInfo(@"Skipping daily task '%@': invalid time %ld:%ld", name, (long)hour, (long)minute);
                    continue;
                }
                
                // Add The Task to the scheduler
                [self addDailyTask:name hour:hour minute:minute taskBlock:[self taskBlockForName:task[@"cmd"]]];
                
            }
            else if ([type isEqualToString:@"weekly"])
            {
                
                NSString *timeStr = [intervals[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSDateComponents *time = [NSDate timeComponentsFromString:timeStr];
                
                NSInteger weekday = [NSDate weekdayUnitFromCurrentDate];
                NSInteger hour = time.hour;
                NSInteger minute = time.minute;
                
                // Add The Task to the scheduler
                [self addWeeklyTask:name weekday:weekday hour:hour minute:minute taskBlock:[self taskBlockForName:name]];
            
            }
            else if ([type isEqualToString:@"weekday"])
            {
                // RECURRING@WeekDay@2@12:00:00 = Run every Monday at Noon
                NSString *weekdayStr = [intervals[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString *timeStr = [intervals[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSDateComponents *time = [NSDate timeComponentsFromString:timeStr];
                
                
                NSInteger weekday = [weekdayStr integerValue];
                NSInteger hour = time.hour;
                NSInteger minute = time.minute;
                
                // Add The Task to the scheduler
                [self addWeeklyTask:name weekday:weekday hour:hour minute:minute taskBlock:[self taskBlockForName:name]];
            }
            else if ([type isEqualToString:@"monthly"])
            {
                // CEH Not implemented yet
                /*
                NSString *timeStr = [intervals[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSDateComponents *time = [NSDate timeComponentsFromString:timeStr];
                
                NSInteger weekday = [NSDate weekdayUnitFromCurrentDate];
                NSInteger hour = time.hour;
                NSInteger minute = time.minute;
                
                // Add The Task to the scheduler
                [self addWeeklyTask:name weekday:weekday hour:hour minute:minute taskBlock:[self taskBlockForName:name]];
                */
            }
            else
            {
                LogInfo(@"Skipping task '%@': unknown type '%@'", name, type);
            }
        }
    }
    
    return YES;
}

- (BOOL)saveConfigToFile
{
    NSMutableArray *taskConfigs = [NSMutableArray array];
    
    for (ScheduledTask *task in self.tasks.allValues) {
        NSMutableDictionary *config = [NSMutableDictionary dictionary];
        config[@"name"] = task.taskName;
        
        switch (task.taskType) {
            case TaskTypeInterval:
                config[@"type"] = @"interval";
                config[@"interval"] = @(task.interval);
                break;
                
            case TaskTypeDaily:
                config[@"type"] = @"daily";
                config[@"hour"] = @(task.hour);
                config[@"minute"] = @(task.minute);
                break;
                
            case TaskTypeWeekly:
                config[@"type"] = @"weekly";
                config[@"weekday"] = @(task.weekday);
                config[@"hour"] = @(task.hour);
                config[@"minute"] = @(task.minute);
                break;
        }
        
        [taskConfigs addObject:config];
    }
    
    NSDictionary *config = @{@"tasks": taskConfigs};
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:&error];
    
    if (error) {
        NSLog(@"Failed to serialize config: %@", error.localizedDescription);
        return NO;
    }
    
    BOOL success = [jsonData writeToFile:self.configFilePath atomically:YES];
    
    if (success) {
        LogInfo(@"Config saved to: %@", self.configFilePath);
    } else {
        LogError(@"Failed to write config file");
    }
    
    return success;
}

- (void(^)(void))taskBlockForName:(NSString *)name
{
    NSString *taskName = [name copy];
    
    return ^{
        TaskCommands *tc = [[TaskCommands alloc] init];
        LogInfo(@"[%@] Executing task", taskName);
        [tc runTaskCommand:taskName];
    };
}

- (void(^)(void))XtaskBlockForName:(NSString *)name
{
    TaskCommands *tc = [[TaskCommands alloc] init];
    __weak TaskCommands *weakTc = tc;
    NSString *taskName = [name copy];
    
    return ^{
        TaskCommands *strongTc = weakTc;
        if (strongTc) {
            LogInfo(@"[%@] Executing task", taskName);
            [strongTc runTaskCommand:taskName];
        } else {
            LogInfo(@"[%@] TaskCommands deallocated", taskName);
        }
    };
}
/*
- (void(^)(void))taskBlockForName:(NSString *)name
{
    TaskCommands *tc = [[TaskCommands alloc] init];
    return ^{
        NSLog(@"[%@] Executing task (no TaskCommands available)", name);
        [tc runTaskCommand:name];
    };
}
 */
    /*
    Class tcClass = NSClassFromString(@"TaskCommands");
    if (tcClass && [tcClass instancesRespondToSelector:@selector(runTaskCommand:)]) {
        id tc = [[tcClass alloc] init];
        return ^{
            NSLog(@"[%@] Executing task", name);
            // Suppress ARC warnings by using performSelector: since we checked the selector above.
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [tc performSelector:@selector(runTaskCommand:) withObject:name];
            #pragma clang diagnostic pop
        };
    } else {
        // Fallback if TaskCommands isn't linked or doesn't implement the selector
        return ^{
            NSLog(@"[%@] Executing task (no TaskCommands available)", name);
        };
    }
     */
//}

- (void(^)(void))taskBlockForNameOG:(NSString *)name
{
    // Map task names to actual implementations
    // In a real application, you'd have a registry or factory pattern
    if ([name isEqualToString:@"HealthCheck"]) {
        return ^{
            NSLog(@"[%@][%@] Health check: System OK", [NSDate now], name);
        };
    } else if ([name isEqualToString:@"DailyBackup"]) {
        return ^{
            NSLog(@"[%@] Starting backup...", name);
            sleep(2);
            NSLog(@"[%@] Backup completed", name);
        };
    } else if ([name isEqualToString:@"LogRotation"]) {
        return ^{
            NSLog(@"[%@] Rotating logs...", name);
            sleep(1);
            NSLog(@"[%@] Log rotation completed", name);
        };
    }
    
    // Default task block
    return ^{
        NSLog(@"[%@] Executing task", name);
    };
}

- (void)listAllTasks
{
    LogInfo(@"=== Current Tasks ===");
    LogInfo(@"Total tasks: %lu", (unsigned long)self.tasks.count);
    
    for (ScheduledTask *task in self.tasks.allValues) {
        NSString *status = task.isRunning ? @"RUNNING" : @"STOPPED";
        NSString *schedule = @"";
        
        switch (task.taskType) {
            case TaskTypeInterval:
                schedule = [NSString stringWithFormat:@"Every %llus", task.interval];
                break;
            case TaskTypeDaily:
                schedule = [NSString stringWithFormat:@"Daily at %02ld:%02ld",
                           (long)task.hour, (long)task.minute];
                break;
            case TaskTypeWeekly:
                schedule = [NSString stringWithFormat:@"Weekly (day %ld) at %02ld:%02ld",
                           (long)task.weekday, (long)task.hour, (long)task.minute];
                break;
        }
        
        LogInfo(@"  [%@] %@ - %@", status, task.taskName, schedule);
    }
    LogInfo(@"====================");
}

// Task creation methods
- (void)addIntervalTask:(NSString *)name interval:(uint64_t)seconds taskBlock:(void(^)(void))taskBlock
{
    [self addIntervalTask:name interval:seconds useRandom:NO taskBlock:taskBlock];
}

- (void)addIntervalTask:(NSString *)name interval:(uint64_t)seconds useRandom:(BOOL)useRand taskBlock:(void(^)(void))taskBlock
{
    ScheduledTask *task = [[ScheduledTask alloc] init];
    task.taskName = name;
    task.taskType = TaskTypeInterval;
    task.interval = seconds;
    task.taskBlock = taskBlock;
    task.isRandom = useRand;
    
    self.tasks[name] = task;
    [self startIntervalTask:task];
    
    // FIX: %@ expects an Objective-C object; useRand is BOOL
    LogInfo(@"Added interval task: %@ , every %llus use random %@", name, seconds, (useRand ? @"YES" : @"NO"));
}

- (void)startIntervalTask:(ScheduledTask *)task
{
    uint64_t interval = task.interval;
    if (task.isRandom) {
        interval = arc4random() % task.interval;
    }
    
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.schedulerQueue);
    dispatch_source_set_timer(timer,
                             dispatch_time(DISPATCH_TIME_NOW, 0),
                             interval * NSEC_PER_SEC,
                             1 * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(timer, ^{
        if (task.isRandom) {
            LogInfo(@"[%@] Executing interval task at interval %llu is random using interval %llu", task.taskName, task.interval, interval);
        } else {
            LogInfo(@"[%@] Executing interval task at interval %llu is not random", task.taskName, task.interval);
        }
        task.taskBlock();
    });
    
    task.timer = timer;
    task.isRunning = YES;
    dispatch_resume(timer);
}

- (void)addDailyTask:(NSString *)name hour:(NSInteger)hour minute:(NSInteger)minute taskBlock:(void(^)(void))taskBlock
{
    ScheduledTask *task = [[ScheduledTask alloc] init];
    task.taskName = name;
    task.taskType = TaskTypeDaily;
    task.hour = hour;
    task.minute = minute;
    task.taskBlock = taskBlock;
    
    self.tasks[name] = task;
    [self scheduleDailyTask:task];
    
    LogInfo(@"Added daily task: %@ (at %02ld:%02ld)", name, (long)hour, (long)minute);
}

- (void)scheduleDailyTask:(ScheduledTask *)task
{
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    
    NSDateComponents *targetComponents = [[NSDateComponents alloc] init];
    targetComponents.hour = task.hour;
    targetComponents.minute = task.minute;
    targetComponents.second = 0;
    
    NSDate *nextRun = [calendar nextDateAfterDate:now
                                   matchingComponents:targetComponents
                                              options:NSCalendarMatchNextTime];
    
    NSTimeInterval delayUntilRun = [nextRun timeIntervalSinceDate:now];
    
    LogInfo(@"[%@] Next run scheduled for: %@", task.taskName, nextRun);
    
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0, 0, self.schedulerQueue);
    
    dispatch_source_set_timer(timer,
                             dispatch_time(DISPATCH_TIME_NOW, delayUntilRun * NSEC_PER_SEC),
                             24 * 60 * 60 * NSEC_PER_SEC,
                             60 * NSEC_PER_SEC);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        LogInfo(@"[%@] Executing daily task", task.taskName);
        task.taskBlock();
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf rescheduleDailyTask:task];
        });
    });
    
    task.timer = timer;
    task.isRunning = YES;
    dispatch_resume(timer);
}

- (void)rescheduleDailyTask:(ScheduledTask *)task
{
    if (task.timer) {
        dispatch_source_cancel(task.timer);
    }
    [self scheduleDailyTask:task];
}

- (void)addWeeklyTask:(NSString *)name weekday:(NSInteger)weekday
                 hour:(NSInteger)hour minute:(NSInteger)minute taskBlock:(void(^)(void))taskBlock
{
    ScheduledTask *task = [[ScheduledTask alloc] init];
    task.taskName = name;
    task.taskType = TaskTypeWeekly;
    task.weekday = weekday;
    task.hour = hour;
    task.minute = minute;
    task.taskBlock = taskBlock;
    
    self.tasks[name] = task;
    [self scheduleWeeklyTask:task];
    
    LogInfo(@"Added weekly task: %@ (weekday %ld at %02ld:%02ld)", name, (long)weekday, (long)hour, (long)minute);
}

- (void)scheduleWeeklyTask:(ScheduledTask *)task
{
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    
    NSDateComponents *targetComponents = [[NSDateComponents alloc] init];
    targetComponents.weekday = task.weekday;
    targetComponents.hour = task.hour;
    targetComponents.minute = task.minute;
    targetComponents.second = 0;
    
    NSDate *nextRun = [calendar nextDateAfterDate:now
                                   matchingComponents:targetComponents
                                              options:NSCalendarMatchNextTime];
    
    NSTimeInterval delayUntilRun = [nextRun timeIntervalSinceDate:now];
    
    LogInfo(@"[%@] Next run scheduled for: %@", task.taskName, nextRun);
    
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0, 0, self.schedulerQueue);
    
    dispatch_source_set_timer(timer,
                             dispatch_time(DISPATCH_TIME_NOW, delayUntilRun * NSEC_PER_SEC),
                             7 * 24 * 60 * 60 * NSEC_PER_SEC,
                             60 * NSEC_PER_SEC);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        LogInfo(@"[%@] Executing weekly task", task.taskName);
        task.taskBlock();
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf rescheduleWeeklyTask:task];
        });
    });
    
    task.timer = timer;
    task.isRunning = YES;
    dispatch_resume(timer);
}

- (void)rescheduleWeeklyTask:(ScheduledTask *)task
{
    if (task.timer) {
        dispatch_source_cancel(task.timer);
    }
    [self scheduleWeeklyTask:task];
}

// Added methods for every 3rd Friday or Saturday scheduling
- (void)addDaysForWeekTask:(NSString *)name
                      days:(NSArray *)days
                      week:(NSInteger)week
                      hour:(NSInteger)hour
                    minute:(NSInteger)minute
                 taskBlock:(void(^)(void))taskBlock
{
    ScheduledTask *task = [[ScheduledTask alloc] init];
    task.taskName = name;
    task.taskType = TaskTypeWeekly; // reuse existing type for display purposes
    task.hour = hour;
    task.minute = minute;
    task.week = week;
    task.weekDays = days;
    task.taskBlock = taskBlock;

    self.tasks[name] = task;
    [self scheduleDaysForWeekTask:task];

    LogInfo(@"Added 3rd Fri/Sat task: %@ (at %02ld:%02ld)", name, (long)hour, (long)minute);
}

- (NSDate *)nextDaysForWeekFromDate:(NSDate *)fromDate
                               days:(NSArray *)days
                               week:(NSInteger)week
                               hour:(NSInteger)hour
                             minute:(NSInteger)minute
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *fromComps = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:fromDate];

    // Helper block to compute nth weekday in a given month
    NSDate* (^weekForDayInMonth)(NSInteger, NSInteger, NSInteger, NSInteger) = ^NSDate* (NSInteger year, NSInteger month, NSInteger week, NSInteger weekday) {
        NSDateComponents *c = [[NSDateComponents alloc] init];
        c.year = year;
        c.month = month;
        c.weekday = weekday; // 1=Sunday, 2=Monday, ..., 7=Saturday in Gregorian
        c.weekdayOrdinal = week; // e.g. 3rd occurrence in the month
        c.hour = hour;
        c.minute = minute;
        c.second = 0;
        return [calendar dateFromComponents:c];
    };

    NSInteger year = fromComps.year;
    NSInteger month = fromComps.month;

    while (true) {
        NSDate *candidate = nil;
        
        // Check all weekdays in the days array for this month
        for (NSNumber *dayNum in days) {
            NSInteger weekday = [dayNum integerValue];
            NSDate *targetDate = weekForDayInMonth(year, month, week, weekday);
            
            // Only consider dates >= fromDate
            if (targetDate && [targetDate compare:fromDate] != NSOrderedAscending) {
                if (!candidate || [targetDate compare:candidate] == NSOrderedAscending) {
                    candidate = targetDate;
                }
            }
        }
        
        if (candidate) {
            return candidate;
        }

        // Advance to next month
        month += 1;
        if (month > 12) {
            month = 1;
            year += 1;
        }
        
        // Set fromDate to the first day of the next month to avoid infinite loop
        NSDateComponents *nextComps = [[NSDateComponents alloc] init];
        nextComps.year = year;
        nextComps.month = month;
        nextComps.day = 1;
        nextComps.hour = 0;
        nextComps.minute = 0;
        nextComps.second = 0;
        fromDate = [calendar dateFromComponents:nextComps];
    }
}

- (void)scheduleDaysForWeekTask:(ScheduledTask *)task
{
    NSDate *now = [NSDate date];
    NSDate *nextRun = [self nextDaysForWeekFromDate:now
                                               days:task.weekDays
                                               week:task.week
                                               hour:task.hour
                                             minute:task.minute];
    NSTimeInterval delayUntilRun = [nextRun timeIntervalSinceDate:now];

    LogInfo(@"[%@] Next 3rd Fri/Sat run scheduled for: %@", task.taskName, nextRun);

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.schedulerQueue);

    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayUntilRun * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              60 * NSEC_PER_SEC);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        LogInfo(@"Executing %@ for week %ld on days %@ task", task.taskName, (long)task.week, task.weekDays);
        task.taskBlock();

        // After firing, reschedule for the next 3rd Friday/Saturday
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf rescheduleDaysForWeekTask:task];
        });
    });

    task.timer = timer;
    task.isRunning = YES;
    dispatch_resume(timer);
}

- (void)rescheduleDaysForWeekTask:(ScheduledTask *)task
{
    if (task.timer) {
        dispatch_source_cancel(task.timer);
    }
    [self scheduleDaysForWeekTask:task];
}


@end

// RECURRINGDAYSOFWEEK@6,7@3@14:30
