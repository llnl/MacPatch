//
// NSDate+Helper.h
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


#import <Foundation/Foundation.h>

@interface NSDate (MPHelper)

+ (NSDate *)now;
+ (NSDate *)dateWithSQLDateString:(NSString *)string;

+ (NSDate *)shortDateFromString:(NSString *)string;
+ (NSDate *)shortDateFromStringWithTime:(NSString *)string time:(NSString *)aTime;
+ (NSDate *)addIntervalToNow:(double)aSeconds;
+ (NSDate *)addDayToInterval:(double)aSeconds;
+ (NSDate *)addWeekToInterval:(double)aSeconds;
+ (NSDate *)addMonthToInterval:(double)aSeconds;

// Date
- (NSInteger)dayFromDate:(NSDate *)aDate;
- (NSInteger)weekDayFromDate:(NSDate *)aDate;
- (NSInteger)monthFromDate:(NSDate *)aDate;
- (NSInteger)yearFromDate:(NSDate *)aDate;
// Time
- (NSInteger)hourFromDateTime:(NSDate *)aDate;
- (NSInteger)minuteFromDateTime:(NSDate *)aDate;
- (NSInteger)secondFromDateTime:(NSDate *)aDate;

- (NSDate *)weeklyNextRun:(NSDate *)startDate;
- (NSDate *)monthlyNextRun:(NSDate *)startDate;

// Extend Other NSDate Category

// + (NSString *)stringForDisplayFromDate:(NSDate *)date prefixed:(BOOL)prefixed alwaysDisplayTime:(BOOL)displayTime;

// NSDateFormatter for bindings search
- (NSString *)searchString;
@end
