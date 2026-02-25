//
//  MPLogger.h
//  This class which is built on os_log will replace LCLLogFile in future version
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma once

@interface MPLogger : NSObject

- (instancetype)initWithFilePath:(NSString *)filePath mirrorToStderr:(BOOL)mirrorToStderr NS_DESIGNATED_INITIALIZER;
+ (instancetype)loggerWithFilePath:(NSString *)filePath mirrorToStderr:(BOOL)mirrorToStderr;

- (void)logWithLevel:(NSString *)level format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

+ (MPLogger *)sharedLogger;
+ (void)configureSharedLoggerWithFilePath:(NSString *)filePath mirrorToStderr:(BOOL)mirrorToStderr;

- (instancetype)init NS_UNAVAILABLE;

@end

#define MPLOG_INFO(fmt, ...)   [[MPLogger sharedLogger] logWithLevel:@"INFO" format:(fmt), ##__VA_ARGS__]
#define MPLOG_WARN(fmt, ...)   [[MPLogger sharedLogger] logWithLevel:@"WARN" format:(fmt), ##__VA_ARGS__]
#define MPLOG_ERROR(fmt, ...)  [[MPLogger sharedLogger] logWithLevel:@"ERROR" format:(fmt), ##__VA_ARGS__]
#define MPLOG_DEBUG(fmt, ...)  [[MPLogger sharedLogger] logWithLevel:@"DEBUG" format:(fmt), ##__VA_ARGS__]

#define MPLOG_INF(fmt, ...)   [[MPLogger sharedLogger] logWithLevel:@"INFO" format:(fmt), ##__VA_ARGS__]
#define MPLOG_WAR(fmt, ...)   [[MPLogger sharedLogger] logWithLevel:@"WARN" format:(fmt), ##__VA_ARGS__]
#define MPLOG_ERR(fmt, ...)  [[MPLogger sharedLogger] logWithLevel:@"ERROR" format:(fmt), ##__VA_ARGS__]
#define MPLOG_DEB(fmt, ...)  [[MPLogger sharedLogger] logWithLevel:@"DEBUG" format:(fmt), ##__VA_ARGS__]

NS_ASSUME_NONNULL_END
