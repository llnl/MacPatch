//
//  CHDisk.m
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

#import "CHDisk.h"

@interface NSString (CHDiskHelper)

- (NSString *)stringTrim;

@end

@implementation NSString (CHDiskHelper)

- (NSString *)stringTrim
{
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end


@implementation CHDisk

@synthesize deviceData;
@synthesize defaultData;
@synthesize daKeys;

- (id)init
{
    self = [super init];
    if (self) 
    {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        [d setObject:@"NA" forKey:@"DeviceInternal"];
        [d setObject:@"NA" forKey:@"DeviceModel"];
        [d setObject:@"NA" forKey:@"DeviceProtocol"];
        [d setObject:@"NA" forKey:@"DeviceRevision"];
        [d setObject:@"NA" forKey:@"MediaBSDName"];
        [d setObject:@"NA" forKey:@"MediaBlockSize"];
        [d setObject:@"NA" forKey:@"MediaEjectable"];
        [d setObject:@"NA" forKey:@"MediaRemovable"];
        [d setObject:@"NA" forKey:@"MediaWritable"];
        [d setObject:@"NA" forKey:@"VolumeKind"];
        [d setObject:@"NA" forKey:@"VolumeMountable"];
        [d setObject:@"NA" forKey:@"MediaName"];
        [d setObject:@"NA" forKey:@"MediaPath"];
        [d setObject:@"NA" forKey:@"MediaSize"];
        [d setObject:@"NA" forKey:@"MediaUUID"];
        [d setObject:@"NA" forKey:@"VolumeUUID"];
        [d setObject:@"NA" forKey:@"VolumePath"];
        [d setObject:@"NA" forKey:@"MediaFreeSpace"];
        [d setObject:@"NA" forKey:@"UNIXPath"];
        [self setDefaultData:d];
        
        NSString *_keys = @"DADeviceInternal,DADeviceModel,DADeviceProtocol,"
                           "DADeviceRevision,DAMediaBSDName,DAMediaBlockSize,DAMediaEjectable,DAMediaRemovable"
                           ",DAMediaWritable,DAVolumeKind,DAVolumeMountable,DAMediaName,DAMediaPath"
                           ",DAMediaSize,DAMediaUUID,DAVolumeUUID,DAVolumePath";
        [self setDaKeys:[_keys componentsSeparatedByString:@","]];

    }
    return self;
}

- (void)populateDeviceDataFromDict:(NSDictionary *)aDict
{
    NSString *_tmpTxt;
    NSDictionary *_sizeInfo = nil;
    NSMutableDictionary *_res = [NSMutableDictionary dictionaryWithDictionary:defaultData];
    for (NSString *item in daKeys) {
        if ([aDict objectForKey:item]) {
            _tmpTxt = [NSString stringWithString:[[NSString stringWithFormat:@"%@",[aDict objectForKey:item]] stringTrim]];
            NSRange stringRange = {0, MIN([_tmpTxt length], 255)};
            
            [_res setObject:[_tmpTxt substringWithRange:stringRange] forKey:[item stringByReplacingOccurrencesOfString:@"DA" withString:@"" options:0 range:NSMakeRange(0,2)]];
        }
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([[_res objectForKey:@"VolumePath"] isEqual:@"NA"] == NO) {
        NSURL *f = [NSURL URLWithString:[_res objectForKey:@"VolumePath"]];
        BOOL isDir;
        if ([fm fileExistsAtPath:[f path] isDirectory:&isDir]) {
            _sizeInfo = [NSDictionary dictionaryWithDictionary:[self volumeSizeInfo:[f path]]];
            if ([_sizeInfo objectForKey:@"totalFreeSpaceRaw"]) {
                [_res setObject:[_sizeInfo objectForKey:@"totalFreeSpaceRaw"] forKey:@"MediaFreeSpace"];
                [_res setObject:[_sizeInfo objectForKey:@"VolumePath"] forKey:@"UNIXPath"];
            }
        }
    }
    [self setDeviceData:[NSDictionary dictionaryWithDictionary:_res]];
}

- (NSDictionary *)volumeSizeInfo:(NSString *)aPath
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    
    float totalSpace = 0.0f;
    float totalFreeSpace = 0.0f;
    
    NSError *error = nil;  
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/" error:&error];
    if (error) {
		logit(lcl_vDebug,@"%@",[error description]);
	}
    
    if (dictionary) {  
        NSNumber *fileSystemSizeInBytes = [dictionary objectForKey: NSFileSystemSize];  
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalSpace = [fileSystemSizeInBytes floatValue];
        totalFreeSpace = [freeFileSystemSizeInBytes floatValue];
        //NSLog(@"Memory Capacity of %.fMB with %.fMB Free memory available.", ((totalSpace/1000.0f)/1000.0f), ((totalFreeSpace/1000.0f)/1000.0f));
		logit(lcl_vDebug,@"Memory Capacity of %.fMB with %.fMB Free memory available.", ((totalSpace/1000.0f)/1000.0f), ((totalFreeSpace/1000.0f)/1000.0f));
    } else {  
		logit(lcl_vError,@"Error Obtaining System Memory Info: Domain = %@, Code = %d", [error domain], (int)[error code]);  
    }  
    
    [d setObject:aPath forKey:@"VolumePath"];
    //[d setObject:[NSString stringWithFormat:@"%d",(int)(totalSpace/1000)] forKey:@"totalSpaceRaw"];
    [d setObject:[NSString stringWithFormat:@"%llu",(long long)totalSpace] forKey:@"totalSpaceRaw"]; // Using Bytes for RAW Value
    [d setObject:[NSString stringWithFormat:@"%d",(int)((totalSpace/1000)/1000)] forKey:@"totalSpaceMB"];
    //[d setObject:[NSString stringWithFormat:@"%d",(int)(totalFreeSpace/1000)]  forKey:@"totalFreeSpaceRaw"];
    [d setObject:[NSString stringWithFormat:@"%llu",(long long)totalFreeSpace]  forKey:@"totalFreeSpaceRaw"]; // Using Bytes for RAW Value
    [d setObject:[NSString stringWithFormat:@"%d",(int)((totalFreeSpace/1000)/1000)] forKey:@"totalFreeSpaceMB"];
    logit(lcl_vDebug,@"volumeSizeInfo: %@",d);
	
    return (NSDictionary *)d;
}

@end
