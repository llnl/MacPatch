//
//  MPTasks.m
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

#import "MPTasks.h"
#import "MPTaskValidate.h"
#import "Task.h"

@interface MPTasks ()

@end

@implementation MPTasks


// NEW MP 3.1
- (NSArray *)setNextRunForTasks:(NSArray *)aTasks
{
    NSMutableArray *tmpArr = [[NSMutableArray alloc] init];
    NSMutableDictionary *tmpDict;
    int i = 0;
    double sd, ed = 0;
    for (i=0;i<[aTasks count];i++)
    {
        tmpDict = [[NSMutableDictionary alloc] initWithDictionary:[aTasks objectAtIndex:i]];
        sd = [[NSDate shortDateFromString:[tmpDict objectForKey:@"startdate"]] timeIntervalSince1970];
        ed = [[NSDate shortDateFromString:[tmpDict objectForKey:@"enddate"]] timeIntervalSince1970];
        [tmpDict setObject:[NSNumber numberWithDouble:sd] forKey:@"startDateInt"];
        [tmpDict setObject:[NSNumber numberWithDouble:ed] forKey:@"endDateInt"];
        [tmpArr addObject:[self genNextRunAt:tmpDict]];
        tmpDict = nil;
    }
    return tmpArr;
}

- (NSDictionary *)genNextRunAt:(NSDictionary *)aTask
{
	NSString *_dt = nil;
	NSMutableDictionary *tmpDict = nil;
	tmpDict = [[NSMutableDictionary alloc] initWithDictionary:aTask];
	//unsigned int next_run = 0;
	double next_run = 0;
	
	/* Once@Time; Recurring@Daily,Weekly,Monthly@Time;Every@seconds */
	NSArray *intervalArray = [[tmpDict objectForKey:@"interval"] componentsSeparatedByString:@"@"];
	
	// Check length and nulls
	if ([intervalArray count] >= 2) {
		// Validate Interval Attribute, if fail set to default value
		if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPCheckIn"]) {
			if ([intervalArray count] == 2) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
					[tmpDict setObject:@"Every@300" forKey:@"interval"];
				}
			} else if ([intervalArray count] == 3) {
				[tmpDict setObject:@"Every@300" forKey:@"interval"];
			}
		} else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPAgentCheck"]) {
			if ([intervalArray count] == 2) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
					[tmpDict setObject:@"Every@3600" forKey:@"interval"];
				}
			} else if ([intervalArray count] == 3) {
				[tmpDict setObject:@"Every@3600" forKey:@"interval"];
			}
		} else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPVulScan"]) {
			if ([intervalArray count] == 3) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL || [intervalArray objectAtIndex:2] == NULL) {
					[tmpDict setObject:@"RECURRING@Daily@12:00:00" forKey:@"interval"];
				}
			} else {
				[tmpDict setObject:@"RECURRING@Daily@12:00:00" forKey:@"interval"];
			}
		} else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPVulUpdate"]) {
			if ([intervalArray count] == 3) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL || [intervalArray objectAtIndex:2] == NULL) {
					[tmpDict setObject:@"RECURRING@Daily@12:30:00" forKey:@"interval"];
				}
			} else {
				[tmpDict setObject:@"RECURRING@Daily@12:30:00" forKey:@"interval"];
			}
		} else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPAVCheck"]) {
			if ([intervalArray count] == 2) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
					[tmpDict setObject:@"EVERYRAND@14400" forKey:@"interval"];
				}
			} else if ([intervalArray count] == 3) {
				[tmpDict setObject:@"EVERYRAND@14400" forKey:@"interval"];
			}
        } else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPAVInfo"]) {
			if ([intervalArray count] == 2) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
					[tmpDict setObject:@"EVERYRAND@1800" forKey:@"interval"];
				}
			} else if ([intervalArray count] == 3) {
				[tmpDict setObject:@"EVERYRAND@14400" forKey:@"interval"];
			}
		} else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPInvScan"]) {
			if ([intervalArray count] == 2) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
					[tmpDict setObject:@"EVERY@21600" forKey:@"interval"];
				}
			} else if ([intervalArray count] == 3) {
				[tmpDict setObject:@"EVERY@21600" forKey:@"interval"];
			}
		} else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPProfiles"]) {
			if ([intervalArray count] == 2) {
				if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
					[tmpDict setObject:@"EVERY@1800" forKey:@"interval"];
				}
			} else if ([intervalArray count] == 3) {
				[tmpDict setObject:@"EVERY@1800" forKey:@"interval"];
			}
        }  else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPSrvList"]) {
            if ([intervalArray count] == 2) {
                if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
                    [tmpDict setObject:@"EVERY@600" forKey:@"interval"];
                }
            } else if ([intervalArray count] == 3) {
                [tmpDict setObject:@"EVERY@600" forKey:@"interval"];
            }
        }  else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPSUSrvList"]) {
            if ([intervalArray count] == 2) {
                if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
                    [tmpDict setObject:@"EVERY@900" forKey:@"interval"];
                }
            } else if ([intervalArray count] == 3) {
                [tmpDict setObject:@"EVERY@900" forKey:@"interval"];
            }
        }  else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPAppStore"]) {
            if ([intervalArray count] == 2) {
                if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
                    [tmpDict setObject:@"EVERY@7200" forKey:@"interval"];
                }
            } else if ([intervalArray count] == 3) {
                [tmpDict setObject:@"EVERY@900" forKey:@"interval"];
            }
        } else if ([[tmpDict objectForKey:@"cmd"] isEqualToString:@"kMPPatchCrit"]) {
            if ([intervalArray count] == 2) {
                if ([intervalArray objectAtIndex:0] == NULL || [intervalArray objectAtIndex:1] == NULL) {
                    [tmpDict setObject:@"EVERY@1800" forKey:@"interval"];
                }
            } else if ([intervalArray count] == 3) {
                [tmpDict setObject:@"EVERY@1800" forKey:@"interval"];
            }
        }
        
	} else {
		logit(lcl_vError,@"Could not validate interval. Not enough arguments (%@)",[tmpDict objectForKey:@"interval"]);
		logit(lcl_vError,@"Changing task (%@) state to inactive.",[tmpDict objectForKey:@"name"]);
		[tmpDict setObject:@"0" forKey:@"active"];
		NSDictionary *results = [NSDictionary dictionaryWithDictionary:tmpDict];
		tmpDict = nil;
		
		return results;	
	}
	
	if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"EVERY"]) 
	{
		next_run = (double)[[NSDate date] timeIntervalSince1970] + [[intervalArray objectAtIndex:1] intValue];
	} 
	else if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"EVERYRAND"]) 
	{
		int r = arc4random() % [[intervalArray objectAtIndex:1] intValue];
		next_run = (double)[[NSDate date] timeIntervalSince1970] + r;
	}
	else if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"RECURRING"]) 
	{
		_dt = [NSString stringWithFormat:@"%@ %@",[NSDate stringFromDate:[NSDate now] withFormat:@"yyyy-MM-dd"],[intervalArray objectAtIndex:2]]; // Default for Daily
		
		if ([[[intervalArray objectAtIndex:1] uppercaseString] isEqualToString:@"DAILY"]) 
		{
			if (![tmpDict objectForKey:@"nextrun"]) {
				// If Less than right now ...
				logit(lcl_vTrace,@"%ld < %ld",(long)[[NSDate dateFromString:_dt] timeIntervalSince1970], (long)[[NSDate date] timeIntervalSince1970]);
				if ([[NSDate dateFromString:_dt] timeIntervalSince1970] > [[NSDate date] timeIntervalSince1970]) {
					next_run = 	(double)[[NSDate dateFromString:_dt] timeIntervalSince1970];
				} else {
					next_run = [[NSDate addDayToInterval:[[NSDate dateFromString:_dt] timeIntervalSince1970]] timeIntervalSince1970];
				}
			} else {
				next_run = [[NSDate addDayToInterval:[[tmpDict objectForKey:@"nextrun"] intValue]] timeIntervalSince1970];
			}
		}
		else if ([[[intervalArray objectAtIndex:1] uppercaseString] isEqualToString:@"DAILYRAND"])
		{
			int dailyRandDelay = arc4random() % 1800; //Default is 30min
			if (intervalArray.count == 4) {
				dailyRandDelay = arc4random() % [[intervalArray objectAtIndex:3] intValue];
			}
			
			if (![tmpDict objectForKey:@"nextrun"]) {
				// If Less than right now ...
				logit(lcl_vTrace,@"%ld < %ld",(long)[[NSDate dateFromString:_dt] timeIntervalSince1970], (long)[[NSDate date] timeIntervalSince1970]);
				if ([[NSDate dateFromString:_dt] timeIntervalSince1970] > [[NSDate date] timeIntervalSince1970]) {
					next_run = 	(double)[[NSDate dateFromString:_dt] timeIntervalSince1970];
				} else {
					next_run = [[NSDate addDayToInterval:[[NSDate dateFromString:_dt] timeIntervalSince1970]] timeIntervalSince1970];
				}
			} else {
				next_run = [[NSDate addDayToInterval:[[tmpDict objectForKey:@"nextrun"] intValue]] timeIntervalSince1970];
			}
			
			next_run = (double)(next_run + dailyRandDelay);
		}
		else if ([[[intervalArray objectAtIndex:1] uppercaseString] isEqualToString:@"WEEKLY"]) 
		{
			NSString *_sdt = [NSString stringWithFormat:@"%@ %@",[tmpDict objectForKey:@"startdate"],[intervalArray objectAtIndex:2]];
			if (![tmpDict objectForKey:@"nextrun"]) {
				// If Less than right now ...
				if ([[NSDate dateFromString:_sdt] timeIntervalSince1970] > [[NSDate date] timeIntervalSince1970]) {
					next_run = (double)[[NSDate dateFromString:_dt] timeIntervalSince1970];
				} else {
					next_run = [[[NSDate date] weeklyNextRun:[NSDate dateWithSQLDateString:_sdt]] timeIntervalSince1970];
				}
			} else {
				next_run = [[[NSDate date] weeklyNextRun:[NSDate dateWithSQLDateString:_sdt]] timeIntervalSince1970];
			}
		}
		else if ([[[intervalArray objectAtIndex:1] uppercaseString] isEqualToString:@"MONTHLY"]) 
		{
			NSString *_sdt = [NSString stringWithFormat:@"%@ %@",[tmpDict objectForKey:@"startdate"],[intervalArray objectAtIndex:2]];
			if (![tmpDict objectForKey:@"nextrun"]) {
				// If Less than right now ...
				if ([[NSDate dateFromString:_dt] timeIntervalSince1970] > [[NSDate date] timeIntervalSince1970]) {
					next_run = 	(double)[[NSDate dateFromString:_dt] timeIntervalSince1970];
				} else {
					next_run = [[[NSDate date] monthlyNextRun:[NSDate dateWithSQLDateString:_sdt]] timeIntervalSince1970];
				}
			} else {
				next_run = [[[NSDate date] monthlyNextRun:[NSDate dateWithSQLDateString:_sdt]] timeIntervalSince1970];
			}
		} else {
			logit(lcl_vError,@"Configuration error. RECURRING value will be set to \"Daily\".");
			if (![tmpDict objectForKey:@"nextrun"]) {
				// If Less than right now ...
				if ([[NSDate dateFromString:_dt] timeIntervalSince1970] > [[NSDate date] timeIntervalSince1970]) {
					next_run = 	(double)[[NSDate dateFromString:_dt] timeIntervalSince1970];
				} else {
					next_run = [[NSDate addDayToInterval:[[NSDate dateFromString:_dt] timeIntervalSince1970]] timeIntervalSince1970];
				}
			} else {
				next_run = [[NSDate addDayToInterval:[[tmpDict objectForKey:@"nextrun"] intValue]] timeIntervalSince1970];
			}
		}

	}
	else if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"ONCE"]) 
	{
		next_run = [[tmpDict objectForKey:@"nextrun"] doubleValue]; // Leave the value as is
		if ([[tmpDict objectForKey:@"nextrun"] doubleValue] < [[NSDate date] timeIntervalSince1970])
		{
			[tmpDict setObject:@"0" forKey:@"active"]; // Disable the task
		}
	}
    
    
    NSString *nextRunStr = [[NSDate dateWithTimeIntervalSince1970:next_run] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S %z" timeZone:[NSTimeZone localTimeZone] locale:nil];
    if ([[tmpDict objectForKey:@"active"] isEqualTo:@"1"]) {
        logit(lcl_vInfo,@"%@ next run at %@",tmpDict[@"name"],nextRunStr);
    } else {
        logit(lcl_vInfo,@"%@ next run at %@ (DISABLED TASK)",tmpDict[@"name"],nextRunStr);
    }

	[tmpDict setObject:[NSNumber numberWithDouble:next_run] forKey:@"nextrun"];
	NSDictionary *results = [NSDictionary dictionaryWithDictionary:tmpDict];
	tmpDict = nil;
	
	return results;
}

# pragma mark Date Methods
- (NSInteger)weekDayFromDate:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSWeekdayCalendarUnit fromDate:aDate];
	NSInteger dateWeekDay = [components weekday];
	return dateWeekDay;
}

- (NSDate *)weeklyNextRun:(NSDate *)startDate
{
	NSDate *today = [[NSDate alloc] init];
	NSInteger startDateWeekDay = [self weekDayFromDate:startDate];
	NSInteger todayWeekDay = [self weekDayFromDate:today];
	NSInteger daysToAdd = 0;
	
	if (startDateWeekDay == todayWeekDay)
	{
		daysToAdd = 7;
	}
	else if (startDateWeekDay < todayWeekDay ) 
	{
		daysToAdd = (7 - (todayWeekDay - startDateWeekDay));
	}
	else if (startDateWeekDay > todayWeekDay ) 
	{
		daysToAdd = (startDateWeekDay - todayWeekDay);
	}
	
	NSDateComponents *components = [[NSDateComponents alloc] init];
	[components setDay:daysToAdd];
	
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDate *newDate = [gregorianCal dateByAddingComponents:components toDate:today options:0];
	
	return newDate;
}

@end
