//
//  Logger.m
//  MPLibrary
//
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

#import "Logger.h"
#import <Foundation/Foundation.h>
#import <os/log.h>
#import <signal.h>

@interface Logger ()
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSFileHandle *stderrHandle;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, strong) os_log_t osLog;
@property (nonatomic, copy) NSString *logPath;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation Logger

+ (instancetype)sharedLogger
{
    static Logger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _logQueue = dispatch_queue_create("gov.llnl.mp.logger", DISPATCH_QUEUE_SERIAL);
        _minimumLogLevel = LogLevelInfo;
        _enableFileLogging = YES;
        _enableConsoleLogging = NO;
        _enableStderrLogging = NO;
        _enableFileNameAndLineNumber = NO;
        _enableFunctionName = NO;
        _enableFullFunctionName = NO;
        _maxFileSize = 10 * 1024 * 1024; // 10MB
        
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        
        // Get stderr handle
        _stderrHandle = [NSFileHandle fileHandleWithStandardError];
        
        // Register for signals
        [self setupSignalHandlers];
    }
    return self;
}

- (void)setupWithLogPath:(NSString *)path subsystem:(NSString *)subsystem category:(NSString *)category
{
    self.logPath = path;
    self.osLog = os_log_create([subsystem UTF8String], [category UTF8String]);
    
    // Create log file if it doesn't exist
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:nil attributes:nil];
    }
    
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (self.fileHandle) {
        [self.fileHandle seekToEndOfFile];
    } else {
        NSLog(@"Failed to open log file at: %@", path);
    }
}

- (void)setupSignalHandlers
{
    signal(SIGHUP, handleSignal);
    signal(SIGTERM, handleSignal);
    signal(SIGINT, handleSignal);
}

void handleSignal(int sig)
{
    [[Logger sharedLogger] flush];
    if (sig == SIGHUP) {
        [[Logger sharedLogger] rotate];
    }
}

#pragma mark - Convenience Methods

- (void)debug:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logMessage:message level:LogLevelDebug function:NULL file:NULL line:0];
}

- (void)info:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logMessage:message level:LogLevelInfo function:NULL file:NULL line:0];
}

- (void)warning:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logMessage:message level:LogLevelWarning function:NULL file:NULL line:0];
}

- (void)error:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logMessage:message level:LogLevelError function:NULL file:NULL line:0];
}

- (void)critical:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logMessage:message level:LogLevelCritical function:NULL file:NULL line:0];
}

- (void)log:(LogLevel)level function:(const char *)function file:(const char *)file
       line:(int)line format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logMessage:message level:level function:function file:file line:line];
}

#pragma mark - Core Logging

- (void)logMessage:(NSString *)message level:(LogLevel)level function:(const char *)function
              file:(const char *)file line:(int)line
{
    
    if (level < self.minimumLogLevel) {
        return;
    }
    
    NSString *levelString = [self stringForLogLevel:level];
    NSString *timestamp = [self.dateFormatter stringFromDate:[NSDate date]];
    
    // Build log line
    NSMutableString *logLine = [NSMutableString stringWithFormat:@"%@ [%@]",timestamp, levelString];
    NSString *funcName = @"";
    NSString *fileName = @"";
    
    if (function) {
        if (_enableFullFunctionName) {
            funcName = [NSString stringWithFormat:@" [%@]",[NSString stringWithUTF8String:function]];
        } else {
            funcName = [NSString stringWithFormat:@" [%@]",[self extractFunctionName:function]];
        }
        
        if (file) {
            fileName = [NSString stringWithFormat:@" (%@:%d)",[[NSString stringWithUTF8String:file]lastPathComponent], line];
        }
    }
    
    if (_enableFunctionName) [logLine appendFormat:@"%@", funcName];
    if (_enableFileNameAndLineNumber) [logLine appendFormat:@"%@", fileName];
    [logLine appendFormat:@": %@", message];
    
    
    // Console logging
    if (self.enableConsoleLogging) {
        NSLog(@"%@", logLine);
    }
    
    // stderr logging
    if (self.enableStderrLogging) {
        [self writeToStderr:logLine level:level];
    }
    
    // os_log
    if (self.osLog) {
        os_log_type_t osLogType = [self osLogTypeForLevel:level];
        os_log_with_type(self.osLog, osLogType, "%{public}s", [message UTF8String]);
    }
    
    // File logging
    if (self.enableFileLogging && self.fileHandle) {
        dispatch_async(self.logQueue, ^{
            [self writeToFile:[logLine stringByAppendingString:@"\n"]];
        });
    }
}

- (void)writeToStderr:(NSString *)logLine level:(LogLevel)level
{
    // Add ANSI color codes for stderr (optional, can be disabled)
    NSString *colorCode = [self ansiColorForLevel:level];
    NSString *resetCode = @"\033[0m";
    NSString *coloredLine = [NSString stringWithFormat:@"%@%@%@\n", colorCode, logLine, resetCode];
    
    NSData *data = [coloredLine dataUsingEncoding:NSUTF8StringEncoding];
    @try {
        [self.stderrHandle writeData:data];
    } @catch (NSException *exception) {
        // Fail silently if stderr is closed
    }
}

- (NSString *)ansiColorForLevel:(LogLevel)level
{
    // ANSI Color Codes Reference:
    // Black: \033[30m, Red: \033[31m, Green: \033[32m, Yellow: \033[33m
    // Blue: \033[34m, Magenta: \033[35m, Cyan: \033[36m, White: \033[37m
    // Reset: \033[0m
    
    switch (level) {
        case LogLevelDebug:
            return @"\033[36m"; // Cyan
        case LogLevelInfo:
            //return @"\033[32m"; // Green
            return @"\033[30m"; // Black
        case LogLevelWarning:
            return @"\033[33m"; // Yellow
        case LogLevelError:
            return @"\033[31m"; // Red
        case LogLevelCritical:
            return @"\033[35m"; // Magenta
    }
}

- (void)writeToFile:(NSString *)logLine
{
    @try {
        NSData *data = [logLine dataUsingEncoding:NSUTF8StringEncoding];
        [self.fileHandle writeData:data];
        
        // Check file size and rotate if needed
        unsigned long long fileSize = [self.fileHandle offsetInFile];
        if (fileSize > self.maxFileSize) {
            [self rotateLogFile];
        }
    } @catch (NSException *exception) {
        NSLog(@"Failed to write to log file: %@", exception);
    }
}

#pragma mark - File Management

- (void)flush
{
    if (self.fileHandle) {
        dispatch_sync(self.logQueue, ^{
            [self.fileHandle synchronizeFile];
        });
    }
}

- (void)rotate
{
    dispatch_async(self.logQueue, ^{
        [self rotateLogFile];
    });
}

- (void)rotateLogFile
{
    if (!self.logPath || !self.fileHandle) {
        return;
    }
    
    [self.fileHandle synchronizeFile];
    [self.fileHandle closeFile];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *rotatedPath = [self.logPath stringByAppendingFormat:@".%@",
                            [self.dateFormatter stringFromDate:[NSDate date]]];
    
    NSError *error = nil;
    [fm moveItemAtPath:self.logPath toPath:rotatedPath error:&error];
    
    if (error) {
        NSLog(@"Failed to rotate log file: %@", error);
    }
    
    // Create new log file
    [fm createFileAtPath:self.logPath contents:nil attributes:nil];
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.logPath];
    
    [self info:@"Log file rotated"];
}

#pragma mark - Helpers

- (NSString *)stringForLogLevel:(LogLevel)level
{
    switch (level) {
        case LogLevelDebug: return @"DEB";
        case LogLevelInfo: return @"INF";
        case LogLevelWarning: return @"WAR";
        case LogLevelError: return @"ERR";
        case LogLevelCritical: return @"CRI";
    }
}

- (os_log_type_t)osLogTypeForLevel:(LogLevel)level {
    switch (level) {
        case LogLevelDebug: return OS_LOG_TYPE_DEBUG;
        case LogLevelInfo: return OS_LOG_TYPE_INFO;
        case LogLevelWarning: return OS_LOG_TYPE_DEFAULT;
        case LogLevelError: return OS_LOG_TYPE_ERROR;
        case LogLevelCritical: return OS_LOG_TYPE_FAULT;
    }
}

- (NSString *)extractFunctionName:(const char *)prettyFunction {
    if (!prettyFunction) {
        return nil;
    }
    
    NSString *fullName = [NSString stringWithUTF8String:prettyFunction];
    
    // Handle Objective-C methods: "-[ClassName methodName:]" or "+[ClassName methodName:]"
    NSRange startBracket = [fullName rangeOfString:@"["];
    NSRange endBracket = [fullName rangeOfString:@"]"];
    
    if (startBracket.location != NSNotFound && endBracket.location != NSNotFound) {
        NSString *methodPart = [fullName substringWithRange:NSMakeRange(startBracket.location + 1,
                                                                         endBracket.location - startBracket.location - 1)];
        // Split "ClassName methodName:" and take just the method name
        NSArray *parts = [methodPart componentsSeparatedByString:@" "];
        if (parts.count >= 2) {
            return parts[1]; // Just the method name
        }
    }
    
    // Handle C functions: just return as-is
    // For "void myFunction()" it will return "void myFunction()"
    // We can clean this up further if needed
    NSRange openParen = [fullName rangeOfString:@"("];
    if (openParen.location != NSNotFound) {
        NSString *beforeParen = [fullName substringToIndex:openParen.location];
        NSArray *parts = [beforeParen componentsSeparatedByString:@" "];
        return [parts lastObject]; // Get function name after return type
    }
    
    return fullName;
}

- (void)dealloc {
    [self flush];
    [self.fileHandle closeFile];
}

@end

