//
//  MPDiskUtil.m
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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

#import "MPDiskUtil.h"

@implementation MPDiskUtil

#pragma mark - Disk Space & Usage

- (long)getFreeDiskSpace
{
    return [self getFreeDiskSpaceAtPath:@"/"];
}

- (long)getFreeDiskSpaceAtPath:(NSString *)aPath
{
	NSDictionary *fileAttributes = [[NSFileManager defaultManager] fileSystemAttributesAtPath:aPath];
	unsigned long freeSpace = (long)[[fileAttributes objectForKey:NSFileSystemFreeSize] longLongValue];
	return (freeSpace / 1024);
	//NSLog(@"free disk space: %dGB", (int)(freeSpace / 1024 / 1024 / 1024 ));
	//NSLog(@"free disk space: %dGB -- %dMB -- %dKB -- %lldB", (int)(freeSpace / 1000 / 1000 / 1000 ), (int)(freeSpace / 1000 / 1000 ), (int)(freeSpace / 1000),(long)freeSpace);
}

- (BOOL)diskHasEnoughSpaceForPackage:(long)requiredSpace
{
    return [self diskHasEnoughSpaceForPackage:@"/" spaceNeeded:requiredSpace];
}

- (BOOL)diskHasEnoughSpaceForPackage:(NSString *)aPath spaceNeeded:(long)requiredSpace
{
    long freeSpace = 0;
    freeSpace = [self getFreeDiskSpaceAtPath:aPath];
    unsigned long _recSize = (requiredSpace * 2);
    if (freeSpace > _recSize) {
        return YES;
    } else {
        return NO;
    }
}

@end
