//
//  MPTaskValidate.m
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

#import "MPTaskValidate.h"

NSString * const kMPCheckIn			= @"Every@300";
NSString * const kMPAgentCheck		= @"Every@3600";
NSString * const kMPVulScan			= @"Recurring@Daily@12:00:00";
NSString * const kMPVulUpdate		= @"Recurring@Daily@12:30:00";
NSString * const kMPAVCheck			= @"EVERYRAND@14400";
NSString * const kMPAVInfo			= @"EVERYRAND@1800";
NSString * const kMPInvScan			= @"EVERY@21600";
NSString * const kMPSWDistMan       = @"EVERY@14400";
NSString * const kMPCMD             = @"EVERY@21600";
NSString * const kMPProfiles        = @"EVERY@1800";
NSString * const kMPSrvList         = @"EVERY@600";
NSString * const kMPSUSrvList       = @"EVERY@1800";
NSString * const kMPAppStore        = @"EVERY@7200";
NSString * const kStartDate			= @"2017-01-01";
NSString * const kEndDate			= @"2030-01-01";
NSString * const kMPPatchCrit		= @"EVERY@1800";

#pragma mark -
#pragma mark NSString Category

@interface NSString (String_Task_Helper)

-(BOOL)isValidTimeString;
-(BOOL)isValidTimeStringUsingFormatter:(NSString *)aFormat;
-(BOOL)isValidNumberString;

@end

@implementation NSString (String_Task_Helper)

-(BOOL)isValidTimeString
{
	return [self isValidTimeStringUsingFormatter:@"HH:mm:ss"];
}

-(BOOL)isValidTimeStringUsingFormatter:(NSString *)aFormat
{
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:aFormat];
	
	NSDate *_date = [dateFormatter dateFromString:self];
	if (_date != NULL) {
		return YES;
	} else {
		return NO;
	}
}

-(BOOL)isValidNumberString
{
	BOOL valid;	
	NSCharacterSet *alphaNums = [NSCharacterSet decimalDigitCharacterSet];
	NSCharacterSet *inStringSet = [NSCharacterSet characterSetWithCharactersInString:self];
	
	valid = [alphaNums isSupersetOfSet:inStringSet];
	
	return valid;
}
@end

#pragma mark -
#pragma mark MPTaskValidate

@implementation MPTaskValidate

- (int)validateTask:(NSDictionary *)aTask
{
	//	Return Codes
	//	0 = Valid	
	//	1 = Error, replace with default cmd
	//	2 = Invalid Interval, we will reset startdate and endate as well
	//	3 = End Date has to be updated, due to bug in 10.8 NSDate. NSDate cant be older than 3512-12-31
	//	99 = Not a valid command type, should disable it.
	
	NSArray *intervalArray = [[aTask objectForKey:@"interval"] componentsSeparatedByString:@"@"];
	// If there are not enough args for the Interval
	if ([intervalArray count] <= 1) {
		logit(lcl_vError,@"Major error found in tasks file. Replacing current tasks file with default config.");
		return 1;
	}
    NSArray *approvedTasks = [NSArray arrayWithObjects:@"KMPCHECKIN",@"KMPAGENTCHECK",@"KMPVULSCAN",@"KMPVULUPDATE",@"KMPAVCHECK",@"KMPINVSCAN",
                              @"KMPCMD",@"KMPSWDISTMAN",@"KMPAVINFO",@"KMPSRVLIST",@"KMPPROFILES",@"KMPWSPOST",@"KMPSUSRVLIST",
                              @"KMPAPPSTORE", nil];
	
	if (![[aTask allKeys] containsObject:@"startdate"]) return 1;
	if (![[aTask allKeys] containsObject:@"enddate"]) return 1;
	if ([[aTask allKeys] containsObject:@"cmd"]) {
        int found = 0;
        NSString *_cmd = [NSString stringWithString:[aTask objectForKey:@"cmd"]];
        for (NSString *_taskName in approvedTasks) {
            if ([[_cmd uppercaseString] isEqualToString:_taskName]) {
                found++;
                break;
            }
        }
        if (found == 0) {
            // No Task Found
            return 99;
        }
	} else {
		return 1;
	}
	
	if ([self validateInterval:intervalArray] == NO) {
		return 2;
	}	
	
	if ([self validateEndDate:[aTask objectForKey:@"enddate"]] == NO) {
		return 3;
	}	
	
	return 0;
}

- (BOOL)validateInterval:(NSArray *)aInterval
{
	
	/*	Valid Formats:
	 Once@Time; Recurring@Daily,Weekly,Monthly@Time; Every@seconds; EveryRand@seconds 
	 */
	
	if ([aInterval count] <= 1) return NO;
	if ([aInterval count] > 3) return NO;
	
	if ([[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"RECURRING"] || [[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"ONCE"]
		|| [[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"EVERY"] || [[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"EVERYRAND"]) {
	} else {
		return NO;
	}
	
	if ([aInterval count] == 2) {
		if ([aInterval objectAtIndex:0] == NULL || [aInterval objectAtIndex:1] == NULL) {
			return NO;	
		}
		if ([[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"ONCE"]) {
			return [[aInterval objectAtIndex:1] isValidTimeString];	
		}
		if ([[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"EVERY"]) {
			return [[aInterval objectAtIndex:1] isValidNumberString];	
		}
		if ([[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"EVERYRAND"]) {
			return [[aInterval objectAtIndex:1] isValidNumberString];
		}
	}
	
	if ([aInterval count] == 3) {
		if ([aInterval objectAtIndex:0] == NULL || [aInterval objectAtIndex:1] == NULL || [aInterval objectAtIndex:2] == NULL) {
			return NO;	
		}
		NSString *_mod = [[aInterval objectAtIndex:1] uppercaseString];
		if ([_mod isEqualToString:@"DAILY"] || [_mod isEqualToString:@"DAILYRAND"] || [_mod isEqualToString:@"WEEKLY"] || [_mod isEqualToString:@"MONTHLY"]) {
			return [[aInterval objectAtIndex:2] isValidTimeString];
		} else {
			return NO;
		}
	}
	
	// Only DailyRand can have 4 options
	if ([aInterval count] == 4) {
		if ([aInterval objectAtIndex:0] == NULL || [aInterval objectAtIndex:1] == NULL || [aInterval objectAtIndex:2] == NULL || [aInterval objectAtIndex:3] == NULL) {
			return NO;
		}
		if ([[[aInterval objectAtIndex:0] uppercaseString] isEqual:@"DAILYRAND"]) {
			return [[aInterval objectAtIndex:3] isValidNumberString];
		} else {
			return NO;
		}
	}
	
	return NO;
}

- (BOOL)validateStateDate:(NSString *)aStringDate
{
	return YES;
}

- (BOOL)validateEndDate:(NSString *)aStringDate
{
	NSRange range = NSMakeRange (0, 4); // Get First 4 Chars
	NSString *_year = [aStringDate substringWithRange:range];
	if ([_year intValue] <= 3000) {
		return YES;
	} else {
		return NO;
	}
}

- (NSDictionary *)updateTaskIntervalForCommand:(NSDictionary *)aTask cmd:(NSString *)aCMDName
{
	NSDictionary *_res;
	NSMutableDictionary *_tmp = [NSMutableDictionary dictionaryWithDictionary:aTask];
	if ([aCMDName isEqualToString:@"kMPCheckIn"]) {
		[_tmp setObject:kMPCheckIn forKey:@"interval"];
	} else if ([aCMDName isEqualToString:@"kMPAgentCheck"]) {
		[_tmp setObject:kMPAgentCheck forKey:@"interval"];
	} else if ([aCMDName isEqualToString:@"kMPVulScan"]) {
		[_tmp setObject:kMPVulScan forKey:@"interval"];
	} else if ([aCMDName isEqualToString:@"kMPVulUpdate"]) {
		[_tmp setObject:kMPVulUpdate forKey:@"interval"];
	} else if ([aCMDName isEqualToString:@"kMPAVCheck"]) {
		[_tmp setObject:kMPAVCheck forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPAVInfo"]) {
		[_tmp setObject:kMPAVInfo forKey:@"interval"];
	} else if ([aCMDName isEqualToString:@"kMPInvScan"]) {
		[_tmp setObject:kMPInvScan forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPSWDistMan"]) {
        [_tmp setObject:kMPSWDistMan forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPCMD"]) {
        [_tmp setObject:kMPCMD forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPProfiles"]) {
        [_tmp setObject:kMPProfiles forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPSrvList"]) {
        [_tmp setObject:kMPSrvList forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPSUSrvList"]) {
        [_tmp setObject:kMPSUSrvList forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPAppStore"]) {
        [_tmp setObject:kMPAppStore forKey:@"interval"];
    } else if ([aCMDName isEqualToString:@"kMPPatchCrit"]) {
        [_tmp setObject:kMPPatchCrit forKey:@"interval"];
    }
	
	[_tmp setObject:kStartDate forKey:@"startdate"];	
	[_tmp setObject:kEndDate forKey:@"enddate"];	
	_res = [NSDictionary dictionaryWithDictionary:_tmp];
	return _res;
}

- (NSDictionary *)updateEndDateForTask:(NSDictionary *)aTask
{
	NSDictionary *_res;
	NSMutableDictionary *_tmp = [NSMutableDictionary dictionaryWithDictionary:aTask];
	
	NSRange range = NSMakeRange (4, [[aTask objectForKey:@"enddate"] length] - 4);
	NSString *_date = [[aTask objectForKey:@"enddate"] substringWithRange:range];
	[_tmp setObject:[NSString stringWithFormat:@"3000%@",_date] forKey:@"enddate"];	
	_res = [NSDictionary dictionaryWithDictionary:_tmp];
	return _res;
}

- (NSDictionary *)disableTask:(NSDictionary *)aTask
{
	NSDictionary *_res;
	NSMutableDictionary *_tmp = [NSMutableDictionary dictionaryWithDictionary:aTask];
	[_tmp setObject:@"0" forKey:@"active"];
	_res = [NSDictionary dictionaryWithDictionary:_tmp];
	return _res;
}


@end
