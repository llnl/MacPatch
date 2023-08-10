//
//  MPFileUtils.m
//  MPLibrary
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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


#import "MPFileUtils.h"

@interface MPFileUtils ()
{
	NSFileManager *fm;
}

@end

@implementation MPFileUtils

- (id)init
{
	self = [super init];
	if (self)
	{
		fm = [NSFileManager defaultManager];
	}
	return self;
}

- (int)unzip:(NSString *)aZipFilePath error:(NSError **)err
{
	NSError *aErr = nil;
	NSString *parentDir = [aZipFilePath stringByDeletingLastPathComponent];
	[self unzip:aZipFilePath targetPath:parentDir error:&aErr];
	if (err != NULL) *err = aErr;
	return 0;
}

- (int)unzip:(NSString *)aZipFilePath targetPath:(NSString *)aTargetPath error:(NSError **)err
{
	if (![fm fileExistsAtPath:aZipFilePath])
	{
		qlerror(@"Error %@ was not found.",aZipFilePath);
		if (err != NULL) *err = [NSError errorWithDomain:@"MPFileUtils"
													code:1001
												userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"File to unzip was not found.", nil)}];
		return 1;
	}
	
	
	NSError *aErr = nil;
	NSString *binFile = @"/usr/bin/ditto";
	NSArray *binArgs = [NSArray arrayWithObjects:@"-x", @"-k", aZipFilePath, aTargetPath, nil];
	NSString *result;
	result = [self runTask:binFile binArgs:binArgs error:&aErr];
	qltrace(@"%@",result);
	if (err != NULL) *err = aErr;
	return 0;
}

- (BOOL)unzipItemAtPath:(NSString *)aZipFilePath targetPath:(NSString *)aTargetPath error:(NSError **)err
{
	NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:aZipFilePath] || ![fm createDirectoryAtPath:[aTargetPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:err]) {
		return NO;
	}
    
    return [self taskWithLaunchPath:@"/usr/bin/ditto" arguments:@[@"-x", @"-k", aZipFilePath, aTargetPath] error:err];
}

- (void)setOwnership:(NSString *)aPath owner:(NSString *)aOwner group:(NSString *)aGroup error:(NSError **)err
{
	BOOL isDir;
	if (![fm fileExistsAtPath:aPath isDirectory:&isDir])
	{
		NSString *errStr = [NSString stringWithFormat:@"Error setting ownership. File %@ not found.",aPath];
		qlerror(@"%@",errStr);
		if (err != NULL) *err = [NSError errorWithDomain:@"MPFileUtils"
													code:1001
												userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(errStr, nil)}];
	}
	
	NSDictionary *permDict = @{NSFileOwnerAccountName:aOwner,NSFileGroupOwnerAccountName:aGroup};
	NSError *error = nil;
	[fm setAttributes:permDict ofItemAtPath:aPath error:&error];
	if(error){
		if (err != NULL) *err = error;
		qlerror(@"Error settings permission %@",error.localizedDescription);
		return;
	}
	
	// If the item is not a directory, return
	if (!isDir) return;

	error = nil;
	NSArray *aContents = [fm subpathsOfDirectoryAtPath:aPath error:&error];
	if (error)
	{
		qlerror(@"Error subpaths of Directory %@.\n%@",aPath,error.localizedDescription);
		return;
	}

	for (NSString *i in aContents)
	{
		error = nil;
		[fm setAttributes:permDict ofItemAtPath:[aPath stringByAppendingPathComponent:i] error:&error];
		if (error) qlerror(@"Error settings permission %@",error.localizedDescription);
	}
	
}

- (BOOL)removeContentsOfDirectory:(NSString *)dirPath
{
	BOOL res = NO;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:dirPath];
	NSString *file;

	int errors = 0;
	
	while (file = [enumerator nextObject])
	{
		NSError *error = nil;
		BOOL result = [fm removeItemAtPath:[dirPath stringByAppendingPathComponent:file] error:&error];
		if (!result && error) {
			qlerror(@"Error: %@", error);
			errors++;
		}
	}
	
	if (errors == 0) res = YES;
	return res;
}

#pragma mark - Private

- (NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs error:(NSError **)err
{
	NSTask *cmd = [[NSTask alloc] init];
	[cmd setLaunchPath:aBinPath];
	[cmd setArguments: aArgs];
	
	NSPipe *pipe = [NSPipe pipe];
	[cmd setStandardOutput: pipe];
	[cmd setStandardError: pipe];
	
	NSFileHandle *file = [pipe fileHandleForReading];
	
	[cmd launch];
	[cmd waitUntilExit];
	
	if ([cmd terminationStatus] != 0)
	{
		qlerror(@"Error, unable to run task.");
		if (err != NULL) *err = [NSError errorWithDomain:@"MPFileUtils" code:[cmd terminationStatus] userInfo:nil];
	}
	
	NSData *data = [file readDataToEndOfFile];
	NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
	return [string trim];
}

- (BOOL)taskWithLaunchPath:(NSString *)launchPath arguments:(NSArray *)arguments error:(NSError **)error
{
    NSTask *task = [[NSTask alloc] init];
    NSPipe *standardErrorPipe = [NSPipe pipe];
    [task setStandardError:standardErrorPipe];
    [task setLaunchPath:launchPath];
    [task setArguments:arguments];
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    [task setTerminationHandler:^(NSTask *task) {
        dispatch_group_leave(group);
    }];
    [task launch];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    int terminationStatus = [task terminationStatus];
    BOOL success = ((terminationStatus == 0) && ([task terminationReason] == NSTaskTerminationReasonExit));
	if (!success && error) {
        *error = [NSError errorWithDomain:@"MPFileUtils" code:terminationStatus
								 userInfo:[NSDictionary dictionaryWithObject:[[NSString alloc] initWithData:[[standardErrorPipe fileHandleForReading] readDataToEndOfFile] encoding:[NSString defaultCStringEncoding]] forKey:NSLocalizedDescriptionKey]];
	}
    return success;
}

@end
