//
//  NSFileManager+Helper.m
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

#import "NSFileManager+Helper.h"


@implementation NSFileManager (NSFileManagerHelper)

- (void)createDirectoryRecursivelyAtPath:(NSString *)path
{
	//check if the dir just above exists...
	BOOL isDir;
	NSString *directoryAbove = [path stringByDeletingLastPathComponent];
	if ([self fileExistsAtPath:directoryAbove isDirectory:&isDir] && isDir)
	{
  		// Fine, create the dir...
        [self createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:NULL];
	} else {
        // call ourself with the directory above...
  		[self createDirectoryRecursivelyAtPath:directoryAbove];
    }
}

- (int)fileSizeAtPath:(NSString *)path
{
    NSDictionary *attributes = [self attributesOfItemAtPath:path error:NULL];
    return [[attributes objectForKey:NSFileSize] intValue];
}

- (BOOL)isDirectoryAtPath:(NSString *)path
{
    return [self isDirectoryAtPath:path butNotPackage:NO];
}

- (BOOL)isDirectoryAtPath:(NSString *)path butNotPackage:(BOOL)notPackage
{
    BOOL isDirectory = NO;
    
    [self fileExistsAtPath:path isDirectory:&isDirectory];
    
    if (notPackage)
        return (isDirectory && ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:path]);
    else
        return isDirectory;
}

- (BOOL)renameFileAtPath:(NSString *)path toFilename:(NSString *)filename deleteExisting:(BOOL)deleteExisting handler:(id)handler
{
    NSString *destination = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:filename];
    
    // Special case: if the current name and the filename are equivalent, i.e. only differing in case, removing would be wrong and moving would fail, so we need to change the name:
    if ([[path lastPathComponent] isEqualToString:filename])
    {
        NSString *oldPath = path;
        
        path = [path stringByAppendingFormat:@"%.2f", [NSDate timeIntervalSinceReferenceDate]];
        [self moveItemAtPath:oldPath toPath:path error:NULL];
    }
    
    if (deleteExisting && [self fileExistsAtPath:destination]) {
        [self removeItemAtPath:destination error:NULL];
    }
    return [self moveItemAtPath:path toPath:destination error:NULL];
}

- (BOOL)removeFileIfExistsAtPath:(NSString *)path
{
    if ([self fileExistsAtPath:path])
        return [self removeItemAtPath:path error:NULL];
    else
        return YES;
}

@end
