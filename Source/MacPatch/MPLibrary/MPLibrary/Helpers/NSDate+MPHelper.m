//
// NSDate+Helper.h
//
/*
 Cpyright (c) 2026, Lawrence Livermore National Security, LLC.
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
    // Parse common SQL date/time representations without using deprecated natural language parsing.
    if (string.length == 0) { return nil; }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    // Use en_US_POSIX for predictable parsing regardless of user settings.
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    // Incoming SQL timestamps are typically in UTC; set GMT to match prior behavior where we first interpret in GMT.
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    NSDate *date = nil;
    // Try a few common SQL formats in order of specificity.
    NSArray<NSString *> *formats = @[@"yyyy-MM-dd HH:mm:ss",
                                     @"yyyy-MM-dd'T'HH:mm:ss",
                                     @"yyyy-MM-dd"]; // date-only
    for (NSString *format in formats) {
        formatter.dateFormat = format;
        date = [formatter dateFromString:string];
        if (date) { break; }
    }
    if (!date) return nil;

    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDateComponents *components = [calendar components:(
                                                         NSCalendarUnitYear |
                                                         NSCalendarUnitMonth |
                                                         NSCalendarUnitDay |
                                                         NSCalendarUnitHour |
                                                         NSCalendarUnitMinute |
                                                         NSCalendarUnitSecond)
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
    NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorianCal components:NSCalendarUnitDay fromDate:aDate];
    NSInteger _val = [components day];
    return _val;
}

- (NSInteger)weekDayFromDate:(NSDate *)aDate
{
    NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorianCal components:NSCalendarUnitWeekday fromDate:aDate];
    NSInteger _weekDay = [components weekday];
    return _weekDay;
}

- (NSInteger)monthFromDate:(NSDate *)aDate
{
    NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorianCal components:NSCalendarUnitMonth fromDate:aDate];
    NSInteger _month = [components month];
    return _month;
}

- (NSInteger)yearFromDate:(NSDate *)aDate
{
    NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorianCal components:NSCalendarUnitYear fromDate:aDate];
    NSInteger _val = [components year];
    return _val;
}

- (NSInteger)hourFromDateTime:(NSDate *)aDate
{
    NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorianCal components:NSCalendarUnitHour fromDate:aDate];
    NSInteger _val = [components hour];
    return _val;
}

- (NSInteger)minuteFromDateTime:(NSDate *)aDate
{
    NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorianCal components:NSCalendarUnitMinute fromDate:aDate];
    NSInteger _val = [components minute];
    return _val;
}

- (NSInteger)secondFromDateTime:(NSDate *)aDate
{
    NSCalendar *gregorianCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [gregorianCal components:NSCalendarUnitSecond fromDate:aDate];
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
    
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
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
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
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

+ (NSDate *)parseDateFromString:(NSString *)timeString {
    NSArray *formats = @[@"HH:mm:ss", @"HH:mm", @"hh:mm:ss a", @"hh:mm a"];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    
    for (NSString *format in formats) {
        [formatter setDateFormat:format];
        NSDate *date = [formatter dateFromString:timeString];
        if (date) {
            return date;
        }
    }
    
    NSLog(@"%s: Failed to parse time string: %@", __PRETTY_FUNCTION__, timeString);
    return nil;
}

+ (NSDateComponents *)timeComponentsFromString:(NSString *)timeString
{
    //NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    //[formatter setDateFormat:@"HH:mm:ss"];
    
    //NSDate *date = [formatter dateFromString:timeString];
    NSDate *date = [NSDate parseDateFromString:timeString];
    if (!date) {
        return nil;
    }
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                               fromDate:date];
    return components;
}

+ (NSInteger)weekdayUnitFromCurrentDate
{
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:NSCalendarUnitWeekday fromDate:now];

    NSInteger weekday = [components weekday];
    //NSLog(@"Weekday: %ld", (long)weekday);
    return weekday;

    /*
    Weekday values:
    1 = Sunday
    2 = Monday
    3 = Tuesday
    4 = Wednesday
    5 = Thursday
    6 = Friday
    7 = Saturday
    */
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


