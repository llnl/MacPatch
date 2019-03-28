//
// NSDate+Helper.h
//
// Created by Billy Gray on 2/26/09.
// Copyright (c) 2009, 2010, ZETETIC LLC
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the ZETETIC LLC nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY ZETETIC LLC ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL ZETETIC LLC BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "NSDate+Helper.h"

@implementation NSDate (Helper)

/*
 * This guy can be a little unreliable and produce unexpected results,
 * you're better off using daysAgoAgainstMidnight
 */
- (NSUInteger)daysAgo {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *components = [calendar components:(NSDayCalendarUnit) 
											   fromDate:self
												 toDate:[NSDate date]
												options:0];
	return [components day];
}

- (NSUInteger)daysAgoAgainstMidnight {
	// get a midnight version of ourself:
	NSDateFormatter *mdf = [[NSDateFormatter alloc] init];
	[mdf setDateFormat:@"yyyy-MM-dd"];
	NSDate *midnight = [mdf dateFromString:[mdf stringFromDate:self]];
	
	return (int)[midnight timeIntervalSinceNow] / (60*60*24) *-1;
}

- (NSString *)stringDaysAgo {
	return [self stringDaysAgoAgainstMidnight:YES];
}

- (NSString *)stringDaysAgoAgainstMidnight:(BOOL)flag {
	NSUInteger daysAgo = (flag) ? [self daysAgoAgainstMidnight] : [self daysAgo];
	NSString *text = nil;
	switch (daysAgo) {
		case 0:
			text = @"Today";
			break;
		case 1:
			text = @"Yesterday";
			break;
		default:
			text = [NSString stringWithFormat:@"%d days ago", (int)daysAgo];
	}
	return text;
}

- (NSUInteger)weekday {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *weekdayComponents = [calendar components:(NSWeekdayCalendarUnit) fromDate:self];
	return [weekdayComponents weekday];
}

+ (NSDate *)dateFromString:(NSString *)string {
	return [NSDate dateFromString:string withFormat:[NSDate dbFormatString]];
}

+ (NSDate *)dateFromString:(NSString *)string withFormat:(NSString *)format {
	NSDateFormatter *inputFormatter = [[NSDateFormatter alloc] init];
	[inputFormatter setDateFormat:format];
	NSDate *date = [inputFormatter dateFromString:string];
	return date;
}

+ (NSString *)stringFromDate:(NSDate *)date withFormat:(NSString *)format {
	return [date stringWithFormat:format];
}

+ (NSString *)stringFromDate:(NSDate *)date {
	return [date string];
}

+ (NSString *)stringForDisplayFromDate:(NSDate *)date prefixed:(BOOL)prefixed {
	/* 
	 * if the date is in today, display 12-hour time with meridian,
	 * if it is within the last 7 days, display weekday name (Friday)
	 * if within the calendar year, display as Jan 23
	 * else display as Nov 11, 2008
	 */
	
	NSDate *today = [NSDate date];
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDateComponents *offsetComponents = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) 
													 fromDate:today];
	
	NSDate *midnight = [calendar dateFromComponents:offsetComponents];
	
	NSDateFormatter *displayFormatter = [[NSDateFormatter alloc] init];
	NSString *displayString = nil;
	
	// comparing against midnight
	if ([date compare:midnight] == NSOrderedDescending) {
		if (prefixed) {
			[displayFormatter setDateFormat:@"'at' h:mm a"]; // at 11:30 am
		} else {
			[displayFormatter setDateFormat:@"h:mm a"]; // 11:30 am
		}
	} else {
		// check if date is within last 7 days
		NSDateComponents *componentsToSubtract = [[NSDateComponents alloc] init];
		[componentsToSubtract setDay:-7];
		NSDate *lastweek = [calendar dateByAddingComponents:componentsToSubtract toDate:today options:0];
		if ([date compare:lastweek] == NSOrderedDescending) {
			[displayFormatter setDateFormat:@"EEEE"]; // Tuesday
		} else {
			// check if same calendar year
			NSInteger thisYear = [offsetComponents year];
			
			NSDateComponents *dateComponents = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) 
														   fromDate:date];
			NSInteger thatYear = [dateComponents year];			
			if (thatYear >= thisYear) {
				[displayFormatter setDateFormat:@"MMM d"];
			} else {
				[displayFormatter setDateFormat:@"MMM d, yyyy"];
			}
		}
		if (prefixed) {
			NSString *dateFormat = [displayFormatter dateFormat];
			NSString *prefix = @"'on' ";
			[displayFormatter setDateFormat:[prefix stringByAppendingString:dateFormat]];
		}
	}
	
	// use display formatter to return formatted date string
	displayString = [displayFormatter stringFromDate:date];
	return displayString;
}

+ (NSString *)stringForDisplayFromDate:(NSDate *)date {
	return [self stringForDisplayFromDate:date prefixed:NO];
}



- (NSString *)stringWithFormat:(NSString *)format {
	NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
	[outputFormatter setDateFormat:format];
	NSString *timestamp_str = [outputFormatter stringFromDate:self];
	return timestamp_str;
}

- (NSString *)string {
	return [self stringWithFormat:[NSDate dbFormatString]];
}

- (NSString *)stringWithDateStyle:(NSDateFormatterStyle)dateStyle timeStyle:(NSDateFormatterStyle)timeStyle {
	NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
	[outputFormatter setDateStyle:dateStyle];
	[outputFormatter setTimeStyle:timeStyle];
	NSString *outputString = [outputFormatter stringFromDate:self];
	return outputString;
}

- (NSDate *)beginningOfWeek {
	// largely borrowed from "Date and Time Programming Guide for Cocoa"
	// we'll use the default calendar and hope for the best
	
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSDate *beginningOfWeek = nil;
	BOOL ok = [calendar rangeOfUnit:NSWeekCalendarUnit startDate:&beginningOfWeek
						   interval:NULL forDate:self];
	if (ok) {
		return beginningOfWeek;
	} 
	
	// couldn't calc via range, so try to grab Sunday, assuming gregorian style
	// Get the weekday component of the current date
	NSDateComponents *weekdayComponents = [calendar components:NSWeekdayCalendarUnit fromDate:self];
	
	/*
	 Create a date components to represent the number of days to subtract from the current date.
	 The weekday value for Sunday in the Gregorian calendar is 1, so subtract 1 from the number of days to subtract from the date in question.  (If today's Sunday, subtract 0 days.)
	 */
	NSDateComponents *componentsToSubtract = [[NSDateComponents alloc] init];
	[componentsToSubtract setDay: 0 - ([weekdayComponents weekday] - 1)];
	beginningOfWeek = nil;
	beginningOfWeek = [calendar dateByAddingComponents:componentsToSubtract toDate:self options:0];
	
	//normalize to midnight, extract the year, month, and day components and create a new date from those components.
	NSDateComponents *components = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit)
											   fromDate:beginningOfWeek];
	return [calendar dateFromComponents:components];
}

- (NSDate *)beginningOfDay {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	// Get the weekday component of the current date
	NSDateComponents *components = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) 
											   fromDate:self];
	return [calendar dateFromComponents:components];
}

- (NSDate *)endOfWeek {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	// Get the weekday component of the current date
	NSDateComponents *weekdayComponents = [calendar components:NSWeekdayCalendarUnit fromDate:self];
	NSDateComponents *componentsToAdd = [[NSDateComponents alloc] init];
	// to get the end of week for a particular date, add (7 - weekday) days
	[componentsToAdd setDay:(7 - [weekdayComponents weekday])];
	NSDate *endOfWeek = [calendar dateByAddingComponents:componentsToAdd toDate:self options:0];
	
	return endOfWeek;
}

+ (NSString *)dateFormatString {
	return @"yyyy-MM-dd";
}

+ (NSString *)timeFormatString {
	return @"HH:mm:ss";
}

+ (NSString *)timestampFormatString {
	return @"yyyy-MM-dd HH:mm:ss";
}

// preserving for compatibility
+ (NSString *)dbFormatString {	
	return [NSDate timestampFormatString];
}

#pragma mark -
#pragma mark MP Additions
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
@end
