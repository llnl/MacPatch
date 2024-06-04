//
//  MPTaskData.m
//  MPAgent
//
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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
