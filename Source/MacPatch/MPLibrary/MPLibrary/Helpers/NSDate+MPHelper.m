//
// NSDate+Helper.h
//
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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
#import "NSDate+MPHelper.h"
#import "NSDate+Helper.h"

@implementation NSDate (MPHelper)

+ (NSDate *)now
{
	NSDate *d = [[NSDate alloc] init];
	
	NSTimeInterval timeSince1970 = [d timeIntervalSince1970];
	d = nil;
	return [NSDate dateWithTimeIntervalSince1970:timeSince1970];
}

+ (NSDate *)dateWithSQLDateString:(NSString *)string
{
	NSDate *date = [NSDate dateWithNaturalLanguageString:string];
	if (!date) return nil;
	NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	NSDateComponents *components = [calendar components:(
														 NSYearCalendarUnit |
														 NSMonthCalendarUnit |
														 NSDayCalendarUnit |
														 NSHourCalendarUnit |
														 NSMinuteCalendarUnit |
														 NSSecondCalendarUnit)
											   fromDate:date];
	[calendar setTimeZone:[NSTimeZone defaultTimeZone]];
	date = [calendar dateFromComponents:components];
	return date;
}

+ (NSDate *)shortDateFromString:(NSString *)string
{
	// MP Addition
	NSString *theDateTime = [NSString stringWithFormat:@"%@ 00:00:00",string];
	return [self dateFromString:theDateTime];
}

+ (NSDate *)shortDateFromStringWithTime:(NSString *)string time:(NSString *)aTime
{
	// MP Addition
	NSString *theDateTime = [NSString stringWithFormat:@"%@ %@",string, aTime];
	return [self dateFromString:theDateTime];
}

+ (NSDate *)shortDateFromTime:(NSString *)string time:(NSString *)aTime
{
	// MP Addition
	NSString *theDateTime = [NSString stringWithFormat:@"%@ %@",string, aTime];
	return [self dateFromString:theDateTime];
}

+ (NSDate *)addIntervalToNow:(double)aSeconds
{
	// MP Addition
	NSDate *d = [[NSDate alloc] init];
	NSDate *l_date = [d dateByAddingTimeInterval:(NSTimeInterval)aSeconds];
	return l_date;
}

+ (NSDate *)addDayToInterval:(double)aSeconds
{
	// MP Addition
	NSDate *l_interval = [NSDate dateWithTimeIntervalSince1970:aSeconds];
	NSDateComponents *components = [[NSDateComponents alloc] init];
	components.day = 1;
	NSDate *result = [[NSCalendar currentCalendar] dateByAddingComponents:components toDate:l_interval options:0];
	components = nil;
	return result;
}

+ (NSDate *)addWeekToInterval:(double)aSeconds
{
	// MP Addition
	NSDate *l_interval = [NSDate dateWithTimeIntervalSince1970:aSeconds];
	NSDateComponents *components = [[NSDateComponents alloc] init];
	components.day = 7;
	NSDate *result = [[NSCalendar currentCalendar] dateByAddingComponents:components toDate:l_interval options:0];
	components = nil;
	return result;
}

+ (NSDate *)addMonthToInterval:(double)aSeconds
{
	// MP Addition
	NSDate *l_interval = [NSDate dateWithTimeIntervalSince1970:aSeconds];
	NSDateComponents *components = [[NSDateComponents alloc] init];
	components.month = 1;
	NSDate *result = [[NSCalendar currentCalendar] dateByAddingComponents:components toDate:l_interval options:0];
	components = nil;
	return result;
}

- (NSInteger)dayFromDate:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSDayCalendarUnit fromDate:aDate];
	NSInteger _val = [components day];
	return _val;
}

- (NSInteger)weekDayFromDate:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSWeekdayCalendarUnit fromDate:aDate];
	NSInteger _weekDay = [components weekday];
	return _weekDay;
}

- (NSInteger)monthFromDate:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSMonthCalendarUnit fromDate:aDate];
	NSInteger _month = [components month];
	return _month;
}

- (NSInteger)yearFromDate:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSYearCalendarUnit fromDate:aDate];
	NSInteger _val = [components year];
	return _val;
}

- (NSInteger)hourFromDateTime:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSHourCalendarUnit fromDate:aDate];
	NSInteger _val = [components hour];
	return _val;
}

- (NSInteger)minuteFromDateTime:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSMinuteCalendarUnit fromDate:aDate];
	NSInteger _val = [components minute];
	return _val;
}

- (NSInteger)secondFromDateTime:(NSDate *)aDate
{
	NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [gregorianCal components:NSSecondCalendarUnit fromDate:aDate];
	NSInteger _val = [components second];
	return _val;
}

- (NSDate *)weeklyNextRun:(NSDate *)startDate
{
	NSDate *today = [NSDate date];
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
	
	NSDateComponents *components;
	components = [[NSDateComponents alloc] init];
	[components setDay:daysToAdd];
	
	NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDate *_newDate = [gregorian dateByAddingComponents:components toDate:self options:0];
	components = nil;
	
	// Build the New Date with what I have
	components = [[NSDateComponents alloc] init];
	[components setYear:[self yearFromDate:_newDate]];
	[components setMonth:[self monthFromDate:_newDate]];
	[components setDay:[self dayFromDate:_newDate]];
	[components setHour:[self hourFromDateTime:startDate]];
	[components setMinute:[self minuteFromDateTime:startDate]];
	[components setSecond:[self secondFromDateTime:startDate]];
	NSDate *newDate = [gregorian dateFromComponents:components];
	
	return newDate;
}

- (NSDate *)monthlyNextRun:(NSDate *)startDate
{
	NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateComponents *components = [[NSDateComponents alloc] init];
	// Build the New Date with what I have
	[components setYear:[self yearFromDate:self]];
	[components setDay:[self dayFromDate:startDate]];
	[components setHour:[self hourFromDateTime:startDate]];
	[components setMinute:[self minuteFromDateTime:startDate]];
	[components setSecond:[self secondFromDateTime:startDate]];
	
	// Get Integer Values for Day, Month, Year
	NSInteger startMonth = [self monthFromDate:startDate];
	NSInteger thisMonth = [self monthFromDate:self];
	NSInteger startDay = [self dayFromDate:startDate];
	NSInteger thisDay = [self weekDayFromDate:self];
	NSInteger monthToAdd = thisMonth;
	
	if (startMonth == thisMonth)
	{
		if (startDay < thisDay) monthToAdd = thisMonth + 1;
	}
	else if (startMonth < thisMonth )
	{
		if (startDay > thisDay) monthToAdd = thisMonth + 1;
	}
	else if (startMonth > thisMonth )
	{
		monthToAdd = startMonth;
	}
	
	// Dont need to ad another year, setMonth greater than 12 will auto add the year.
	[components setMonth:monthToAdd];
	
	NSDate *newDate = [gregorian dateFromComponents:components];
	return newDate;
}

#pragma mark - Extend NSDate+Helper category

static NSString *kNSDateHelperFormatFullDateWithTime    = @"MMM d, yyyy h:mm a";
static NSString *kNSDateHelperFormatFullDate            = @"MMM d, yyyy";
static NSString *kNSDateHelperFormatShortDateWithTime   = @"MMM d h:mm a";
static NSString *kNSDateHelperFormatShortDate           = @"MMM d";
static NSString *kNSDateHelperFormatWeekday             = @"EEEE";
static NSString *kNSDateHelperFormatWeekdayWithTime     = @"EEEE h:mm a";
static NSString *kNSDateHelperFormatTime                = @"h:mm a";
static NSString *kNSDateHelperFormatTimeWithPrefix      = @"'at' h:mm a";
static NSString *kNSDateHelperFormatSQLDate             = @"yyyy-MM-dd";
static NSString *kNSDateHelperFormatSQLTime             = @"HH:mm:ss";
static NSString *kNSDateHelperFormatSQLDateWithTime     = @"yyyy-MM-dd HH:mm:ss";

/*
 * if the date is in today, display 12-hour time with meridian,
 * if it is within the last 7 days, display weekday name (Friday)
 * if within the calendar year, display as Jan 23
 * else display as Nov 11, 2008
 */
/*
+ (NSString *)stringForDisplayFromDate:(NSDate *)date prefixed:(BOOL)prefixed alwaysDisplayTime:(BOOL)displayTime
{
	NSDate *today = [NSDate date];
	NSDateComponents *offsetComponents = [[self sharedCalendar] components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit)
																  fromDate:today];
	NSDate *midnight = [[self sharedCalendar] dateFromComponents:offsetComponents];
	NSString *displayString = nil;
	// comparing against midnight
	NSComparisonResult midnight_result = [date compare:midnight];
	if (midnight_result == NSOrderedDescending) {
		if (prefixed) {
			[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatTimeWithPrefix]; // at 11:30 am
		} else {
			[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatTime]; // 11:30 am
		}
	} else {
		// check if date is within last 7 days
		NSDateComponents *componentsToSubtract = [[NSDateComponents alloc] init];
		[componentsToSubtract setDay:-7];
		NSDate *lastweek = [[self sharedCalendar] dateByAddingComponents:componentsToSubtract toDate:today options:0];
#if !__has_feature(objc_arc)
		[componentsToSubtract release];
#endif
		NSComparisonResult lastweek_result = [date compare:lastweek];
		if (lastweek_result == NSOrderedDescending) {
			if (displayTime) {
				[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatWeekdayWithTime];
			} else {
				[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatWeekday]; // Tuesday
			}
		} else {
			// check if same calendar year
			NSInteger thisYear = [offsetComponents year];
			NSDateComponents *dateComponents = [[self sharedCalendar] components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit)
																		fromDate:date];
			NSInteger thatYear = [dateComponents year];
			if (thatYear >= thisYear) {
				if (displayTime) {
					[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatShortDateWithTime];
				}
				else {
					[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatShortDate];
				}
			} else {
				if (displayTime) {
					[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatFullDateWithTime];
				}
				else {
					[[self sharedDateFormatter] setDateFormat:kNSDateHelperFormatFullDate];
				}
			}
		}
		if (prefixed) {
			NSString *dateFormat = [[self sharedDateFormatter] dateFormat];
			NSString *prefix = @"'on' ";
			[[self sharedDateFormatter] setDateFormat:[prefix stringByAppendingString:dateFormat]];
		}
	}
	// use display formatter to return formatted date string
	displayString = [[self sharedDateFormatter] stringFromDate:date];
	return displayString;
}
*/
static NSDateFormatter *searchDateFormatter = nil;

- (NSString *)searchString
{
	if (!searchDateFormatter) {
		searchDateFormatter = [[NSDateFormatter alloc] init];
		searchDateFormatter.dateStyle = NSDateFormatterShortStyle;
		searchDateFormatter.timeStyle = NSDateFormatterNoStyle;
	}
	return [searchDateFormatter stringFromDate:self];
}

@end
