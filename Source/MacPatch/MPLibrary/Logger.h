//
//  Logger.h
//  MPLibrary
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

/* USAGE
 
 Logger *logger = [Logger sharedLogger];
 [logger setupWithLogPath:@"/var/log/yourapp.log"
                subsystem:@"com.example.yourapp"
                 category:@"daemon"];
 
 // Configure which outputs to enable
 logger.enableFileLogging = YES;
 logger.enableConsoleLogging = NO;  // Disable NSLog
 logger.enableStderrLogging = YES;  // Enable stderr
 logger.minimumLogLevel = LogLevelInfo;
 
 LogInfo(@"Daemon starting up");
 LogError(@"Connection failed: %@", error);
 
 
 */

#import <Foundation/Foundation.h>
#import <os/log.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LogLevel) {
    LogLevelDebug,
    LogLevelInfo,
    LogLevelWarning,
    LogLevelError,
    LogLevelCritical
};

@interface Logger : NSObject

@property (nonatomic, assign) LogLevel minimumLogLevel;
@property (nonatomic, assign) BOOL enableFileLogging;
@property (nonatomic, assign) BOOL enableConsoleLogging;
@property (nonatomic, assign) BOOL enableStderrLogging;
@property (nonatomic, assign) BOOL enableFileNameAndLineNumber;
@property (nonatomic, assign) BOOL enableFunctionName;
@property (nonatomic, assign) BOOL enableFullFunctionName;
@property (nonatomic, assign) NSUInteger maxFileSize; // bytes, default 10MB

+ (instancetype)sharedLogger;
- (void)setupWithLogPath:(NSString *)path subsystem:(NSString *)subsystem category:(NSString *)category;

// Convenience logging methods
- (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)warning:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)critical:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

// Log with explicit function/file/line info
- (void)log:(LogLevel)level
   function:(const char *)function
       file:(const char *)file
       line:(int)line
     format:(NSString *)format, ... NS_FORMAT_FUNCTION(5,6);

// Manual flush
- (void)flush;
- (void)rotate;

@end

// Convenience macros
#define LogDebug(fmt, ...) [[Logger sharedLogger] log:LogLevelDebug function:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]
#define LogInfo(fmt, ...) [[Logger sharedLogger] log:LogLevelInfo function:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]
#define LogWarning(fmt, ...) [[Logger sharedLogger] log:LogLevelWarning function:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]
#define LogError(fmt, ...) [[Logger sharedLogger] log:LogLevelError function:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]
#define LogCritical(fmt, ...) [[Logger sharedLogger] log:LogLevelCritical function:__PRETTY_FUNCTION__ file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]

NS_ASSUME_NONNULL_END
