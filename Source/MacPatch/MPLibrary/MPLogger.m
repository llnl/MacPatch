//
//  MPLogger.h
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

#import "MPLogger.h"
#import <os/log.h>

@interface MPLogger ()

@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, assign) BOOL mirrorToStderr;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, assign) os_log_t oslog;

@end

@implementation MPLogger

static MPLogger *_sharedLogger = nil;

+ (MPLogger *)sharedLogger {
    @synchronized(self) {
        return _sharedLogger;
    }
}

+ (void)configureSharedLoggerWithFilePath:(NSString *)filePath mirrorToStderr:(BOOL)mirrorToStderr {
    @synchronized(self) {
        _sharedLogger = [[MPLogger alloc] initWithFilePath:filePath mirrorToStderr:mirrorToStderr];
    }
}

- (instancetype)initWithFilePath:(NSString *)filePath mirrorToStderr:(BOOL)mirrorToStderr {
    self = [super init];
    if (self) {
        _filePath = [filePath copy];
        _mirrorToStderr = mirrorToStderr;
        
        // Create directory if needed
        NSString *dirPath = [_filePath stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:dirPath]) {
            NSError *dirError = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:&dirError];
            if (dirError) {
                NSLog(@"MPLogger: Failed to create directory at %@: %@", dirPath, dirError);
                return nil;
            }
        }
        
        // Create file if needed
        if (![[NSFileManager defaultManager] fileExistsAtPath:_filePath]) {
            BOOL success = [[NSFileManager defaultManager] createFileAtPath:_filePath contents:nil attributes:nil];
            if (!success) {
                NSLog(@"MPLogger: Failed to create log file at %@", _filePath);
                return nil;
            }
        }
        
        NSError *fileHandleError = nil;
        _fileHandle = [NSFileHandle fileHandleForWritingAtPath:_filePath];
        if (!_fileHandle) {
            NSLog(@"MPLogger: Failed to open file handle for writing at %@", _filePath);
            return nil;
        }
        [_fileHandle seekToEndOfFile];
        
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
        
        _logQueue = dispatch_queue_create("com.mparticle.MPLoggerQueue", DISPATCH_QUEUE_SERIAL);
        
        // Initialize unified os_log instance
        _oslog = os_log_create("gov.llnl.macpatch", "MPAgent");
    }
    return self;
}

+ (instancetype)loggerWithFilePath:(NSString *)filePath mirrorToStderr:(BOOL)mirrorToStderr {
    return [[self alloc] initWithFilePath:filePath mirrorToStderr:mirrorToStderr];
}

- (void)logWithLevel:(NSString *)level format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDate *now = [NSDate date];
    NSString *timestamp = [self.dateFormatter stringFromDate:now];
    NSString *logEntry = [NSString stringWithFormat:@"%@ [%@] %@\n", timestamp, level, message];
    
    // Map string level to os_log_type_t
    os_log_type_t type = OS_LOG_TYPE_DEFAULT;
    if ([level isEqualToString:@"ERROR"]) {
        type = OS_LOG_TYPE_ERROR;
    } else if ([level isEqualToString:@"WARN"]) {
        type = OS_LOG_TYPE_INFO;
    } else if ([level isEqualToString:@"INFO"]) {
        type = OS_LOG_TYPE_DEFAULT;
    } else if ([level isEqualToString:@"DEBUG"]) {
        type = OS_LOG_TYPE_DEBUG;
    }
    
    dispatch_async(self.logQueue, ^{
        // Unified logging with os_log
        os_log_with_type(self.oslog, type, "%{public}@", message);
        
        if (self.fileHandle) {
            NSData *data = [logEntry dataUsingEncoding:NSUTF8StringEncoding];
            [self.fileHandle writeData:data];
            [self.fileHandle synchronizeFile];
        }
        
        if (self.mirrorToStderr) {
            fprintf(stderr, "%s", [logEntry UTF8String]);
            fflush(stderr);
        }
    });
}

- (void)dealloc {
    if (_fileHandle) {
        [_fileHandle synchronizeFile];
        [_fileHandle closeFile];
        _fileHandle = nil;
    }
}

@end
