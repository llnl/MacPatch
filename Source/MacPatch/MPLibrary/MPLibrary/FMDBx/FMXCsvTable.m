//
//  FMXCsvTable.m
//  FMDBx
//
//  Created by KohkiMakimoto on 6/9/14.
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

// ====================================================
// The Code that parses CSV file refers `NTYCSVTable`.
// see https://github.com/naoty/NTYCSVTable
// ====================================================
//
// NTYCSVTable
//
// The MIT License (MIT)
//
// Copyright (c) 2014 Naoto Kaneko
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import "FMXCsvTable.h"

static NSCharacterSet *FMXCsvTableDigitCharacterSet = nil;
static NSArray *FMXCsvTableBooleanStrings = nil;

@implementation FMXCsvTable

+ (void)foreachFileName:(NSString *)fileName process:(void (^)(NSDictionary *))process
{
    [self foreachFileName:fileName columnSeparator:@"," process:process];
}

+ (void)foreachFileName:(NSString *)fileName columnSeparator:(NSString *)separator process:(void (^)(NSDictionary *))process
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:fileName ofType:nil];
    NSURL *url = [NSURL fileURLWithPath:path];
    [self foreachURL:url columnSeparator:separator process:process];
}

+ (void)foreachURL:(NSURL *)url process:(void (^)(NSDictionary *))process
{
    [self foreachURL:url columnSeparator:@"," process:process];
}

+ (void)foreachURL:(NSURL *)url columnSeparator:(NSString *)separator process:(void (^)(NSDictionary *))process
{
    NSString *csvString = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    csvString = [csvString stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    
    NSArray *lines = [csvString componentsSeparatedByString:@"\n"];
    NSArray *headers = [self headersFromLines:lines columnSeparator:separator];
    NSArray *rows = [self rowsFromLines:lines headers:headers columnSeparator:separator];
    
    for (NSDictionary *row in rows) {
        process(row);
    }
}

# pragma mark - private methods

+ (NSArray *)headersFromLines:(NSArray *)lines columnSeparator:(NSString *)separator
{
    NSString *headerLine = lines.firstObject;
    return [headerLine componentsSeparatedByString:separator];
}

+ (NSArray *)rowsFromLines:(NSArray *)lines headers:(NSArray *)headers columnSeparator:(NSString *)separator
{
    NSMutableArray *rows = [NSMutableArray new];
    for (NSString *line in lines) {
        NSInteger lineNumber = [lines indexOfObject:line];
        if (lineNumber == 0) {
            continue;
        }
        
        NSArray *values = [line componentsSeparatedByString:separator];
        NSMutableDictionary *row = [NSMutableDictionary new];
        for (NSString *header in headers) {
            NSUInteger index = [headers indexOfObject:header];
            NSString *value = values[index];
            if ([self isDigit:value]) {
                row[header] = [NSNumber numberWithLongLong:value.longLongValue];
            } else if ([self isBoolean:value]) {
                row[header] = [NSNumber numberWithBool:value.boolValue];
            } else {
                row[header] = values[index];
            }
        }
        [rows addObject:[NSDictionary dictionaryWithDictionary:row]];
    }
    return [NSArray arrayWithArray:rows];
}

+ (BOOL)isDigit:(NSString *)string
{
    if (!FMXCsvTableDigitCharacterSet) {
        FMXCsvTableDigitCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    }
    
    NSScanner *scanner = [NSScanner localizedScannerWithString:string];
    [scanner scanCharactersFromSet:FMXCsvTableDigitCharacterSet intoString:NULL];
    return scanner.isAtEnd;
}

+ (BOOL)isBoolean:(NSString *)string
{
    if (!FMXCsvTableBooleanStrings) {
        FMXCsvTableBooleanStrings = @[@"YES", @"NO", @"yes", @"no", @"TRUE", @"FALSE", @"true", @"false"];
    }
    
    return [FMXCsvTableBooleanStrings containsObject:string];
}

@end
