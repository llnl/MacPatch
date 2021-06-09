//
//  NSTask+KillBy.m
//  MPLibrary
//
//  Created by Charles Heizer on 3/26/21.
//

#import "NSTask+KillBy.h"

@implementation NSTask (KillBy)

- (void)endTaskOnTimeoutInterval:(NSTimeInterval)timeOut
{
    NSDate *killDate = [NSDate dateWithTimeIntervalSinceNow:timeOut];
    @autoreleasepool {
        [self performSelectorInBackground:@selector(killMyTaskBy:) withObject:killDate];
    }
}

- (void)killMyTaskBy:(NSDate *)killBy
{
    qlinfo(@"Kill task at %@",killBy);
    while ([self isRunning]) {
        qlinfo(@"Task is running.");
        if ([[NSDate date] laterDate:killBy] != killBy) {
            qlerror(@"Error, task has reached its timeout. Killing task.");
            [self terminate];
        }
        [NSThread sleepForTimeInterval:1.0];
    }
}

@end
