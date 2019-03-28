//
//  CHDiskInfo.m
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
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

#import "CHDiskInfo.h"
#import "CHDisk.h"

#include <IOKit/IOKitLib.h>
#include <DiskArbitration/DiskArbitration.h>

@interface CHDiskInfo (Private)

@end

@implementation CHDiskInfo

@synthesize diskInfoArray;
@synthesize bsdDiskArray;

- (id)init
{
    self = [super init];
    if (self)
    {
        [self setBsdDiskArray:[self collectBSDDiskNames]];
    }
    return self;
}

- (NSArray *)collectBSDDiskNames
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *uniqueString = (NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    
    NSString *tempFile = [NSString pathWithComponents:[NSArray arrayWithObjects:NSTemporaryDirectory(), uniqueString, nil]];
    [fm createFileAtPath:tempFile contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:tempFile];
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/diskutil"];
    [task setArguments:[NSArray arrayWithObjects:@"list",@"-plist",nil]];
    [task setStandardOutput:file];
    [task launch];
    [task waitUntilExit];
    
    NSDictionary *_res = [NSDictionary dictionaryWithContentsOfFile:tempFile];
    if ([_res objectForKey:@"AllDisks"]) {
        [fm removeItemAtPath:tempFile error:NULL];
        return [_res objectForKey:@"AllDisks"];
    } else {
        [fm removeItemAtPath:tempFile error:NULL];
        return nil;
    }
}

- (NSArray *)collectDiskInfoForLocalDisks
{
    NSMutableArray *_disks;
    CHDisk *cdisk;
    
    DADiskRef disk = NULL;
    DASessionRef session = NULL;
    CFDictionaryRef diskDescription = NULL;
    
    session = DASessionCreate(kCFAllocatorDefault);
    if(session == NULL) {
		logit(lcl_vDebug,@"DASessionCreate");
    }
    
    if ([bsdDiskArray count] >= 1) {
        _disks = [[NSMutableArray alloc] init];
        for (id item in bsdDiskArray)
        {
            disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, [item UTF8String]);
            diskDescription = DADiskCopyDescription(disk);
            NSDictionary *diskData = (__bridge NSDictionary *)diskDescription;
            if (![[diskData objectForKey:@"DADeviceModel"] isEqualToString:@"Disk Image"]) {
                cdisk = [[CHDisk alloc] init];
                [cdisk populateDeviceDataFromDict:diskData];
                [_disks addObject:[cdisk deviceData]];
                cdisk = nil;
            }
            if (diskDescription) {
                CFRelease(diskDescription);
            }
            if (disk) {
                CFRelease(disk);
            }
        }
        [self setDiskInfoArray:[NSArray arrayWithArray:[_disks copy]]];
        _disks = nil;
    }
    
    if (session) {
        CFRelease(session);
    }

    return diskInfoArray;
}

@end
