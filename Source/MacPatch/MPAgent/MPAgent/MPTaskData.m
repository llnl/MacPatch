//
//  MPTaskData.m
//  MPAgent
//
//  Created by Charles Heizer on 2/7/23.
//  Copyright © 2023 LLNL. All rights reserved.
//

#import "MPTaskData.h"

@implementation MPTaskData

- (void)printAgentTasks
{
    NSString *currentTasksFile = @"/Library/Application Support/MacPatch/CurrentTasks.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:currentTasksFile]) {
        NSArray *currentTasks = [NSArray arrayWithContentsOfFile:currentTasksFile];
        printf("\n\nCurrent MacPatch Tasks\n");
        printf("------------------------------------------------\n");
        for (NSDictionary *task in currentTasks) {
            printf("Task: %s \n",[task[@"description"] UTF8String]);
            printf("Task Interval: %s \n",[task[@"interval"] UTF8String]);
            
            NSDate *d = [NSDate dateWithTimeIntervalSince1970:[task[@"nextrun"] doubleValue]];
            NSString *nextRunDateString = [d descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S %z" timeZone:[NSTimeZone localTimeZone] locale:nil];
            printf("Task Next Run: %s \n",[nextRunDateString UTF8String]);
            printf("------------------------------------------------\n");
            
        }
    } else {
        printf("Tasks have not been registered yet.\n");
        printf("Once agent is running tasks will get outputed.\n");
        return;
    }
}

@end
