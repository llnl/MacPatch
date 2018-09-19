//
//  MPNSTask.m
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

#import "MPNSTask.h"
#import "MacPatch.h"

#undef  ql_component
#define ql_component lcl_cMPNSTask

@implementation MPNSTask

- (id)init
{
    self = [super init];
	if (self) {

    }
	
    return self;
}


- (NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs error:(NSError **)err
{
	NSError *error = nil;
	NSString *result;
	result = [self runTask:aBinPath binArgs:aArgs environment:nil error:&error];
	if (error)
	{
		if (err != NULL) *err = error;
	}
	
    return [result trim];
}

- (NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs environment:(NSDictionary *)aEnv error:(NSError **)err
{
	NSTask *cmd = [[NSTask alloc] init];
    [cmd setLaunchPath:aBinPath];
    [cmd setArguments: aArgs];
	if (aEnv) {
		[cmd setEnvironment:aEnv];
	}
	
    NSPipe *pipe = [NSPipe pipe];
    [cmd setStandardOutput: pipe];
	[cmd setStandardError: pipe];
	
    NSFileHandle *file = [pipe fileHandleForReading];
	
    [cmd launch];
    [cmd waitUntilExit];
	
	if ([cmd terminationStatus] != 0)
	{
		qlerror(@"Error, unable to run task.");
		if (err != NULL) *err = [NSError errorWithDomain:@"RunTask" code:[cmd terminationStatus] userInfo:nil];
	}
	
    NSData *data = [file readDataToEndOfFile];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
    return [string trim];
}

@end
