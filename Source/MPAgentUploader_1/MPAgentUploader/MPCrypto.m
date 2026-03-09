//
//  MPCrypto.m
//
/*
 Copyright (c) 2016, Lawrence Livermore National Security, LLC.
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

#import "MPCrypto.h"
#import <CommonCrypto/CommonDigest.h>

//#undef  ql_component
//#define ql_component lcl_cMain

@interface MPCrypto (hidden)

- (NSString *)MD5HashForFile:(NSString *)aFilePath;
- (NSString *)SHA1HashForFile:(NSString *)aFilePath;

- (NSString *)MD5FromString:(NSString *)inputStr;
- (NSString *)SHA1FromString:(NSString *)inputStr;

@end


@implementation MPCrypto

#pragma mark -
#pragma mark Public API

-(NSString *)getHashFromStringForType:(NSString *)inputStr type:(NSString *)aType
{
    if ([aType isEqualToString:@"MD5"]) {
        return [self MD5FromString:inputStr];
    } else if ([aType isEqualToString:@"SHA1"]) {
        return [self SHA1FromString:inputStr];
    }
    
    return NULL;
}

-(NSString *)getHashForFileForType:(NSString *)aFile type:(NSString *)aType
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:aFile] == FALSE) {
		//qlerror(@"Unable to get file hash for %@, file does not exist.",aFile);
		return @"ERROR_FILE_MISSING";
	}
    
    if ([aType isEqualToString:@"MD5"]) {
        return [self MD5HashForFile:aFile];
    } else if ([aType isEqualToString:@"SHA1"]) {
        return [self SHA1HashForFile:aFile];
    }
    
    return NULL;
}

#pragma mark Older API Methods
- (NSString *)md5HashForFile:(NSString *)aFilePath
{
    return [self MD5HashForFile:aFilePath];
}

- (NSString *)sha1HashForFile:(NSString *)aFilePath
{
    return [self SHA1HashForFile:aFilePath];
}

#pragma mark -
#pragma mark Private API

#define BUF_SIZE 4096

- (NSString *)MD5HashForFile:(NSString *)aFilePath
{
    NSMutableString *hashStr = [NSMutableString string];
    size_t blockSize = BUF_SIZE;
    
    // Declare needed variables
    CFReadStreamRef readStream = NULL;
    
    // Create and open the read stream
    readStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)[NSURL fileURLWithPath:aFilePath]);
    
    if (!readStream) goto done;
    bool didSucceed = (bool)CFReadStreamOpen(readStream);
    if (!didSucceed) goto done;
    
    // Initialize the hash object
    CC_MD5_CTX hashObject;
    CC_MD5_Init(&hashObject);
    
    // Feed the data to the hash object
    bool hasMoreData = true;
    while (hasMoreData) {
        uint8_t buffer[blockSize];
        CFIndex readBytesCount = CFReadStreamRead(readStream,(UInt8 *)buffer,(CFIndex)sizeof(buffer));
        
        if (readBytesCount == -1) break;
        if (readBytesCount == 0) {
            hasMoreData = false;
            continue;
        }
        CC_MD5_Update(&hashObject,(const void *)buffer,(CC_LONG)readBytesCount);
    }
    
    // Check if the read operation succeeded
    didSucceed = !hasMoreData;
    
    // Compute the hash digest
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5_Final(digest, &hashObject);
    
    // Abort if the read operation failed
    if (!didSucceed) goto done;
    
    // Compute the string result
	int i = 0;
	for (i = 0; i < CC_MD5_DIGEST_LENGTH; ++i) {
		[hashStr appendFormat:@"%02x",digest[i]];
    }
    
done:    
    if (readStream) {
        CFReadStreamClose(readStream);
        CFRelease(readStream);
    }
    return hashStr;
}

- (NSString *)SHA1HashForFile:(NSString *)aFilePath
{
    NSMutableString *hashStr = [NSMutableString string];
    size_t blockSize = BUF_SIZE;
    
    // Declare needed variables
    CFReadStreamRef readStream = NULL;
    
    // Create and open the read stream
    readStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)[NSURL fileURLWithPath:aFilePath]);
    
    if (!readStream) goto done;
    bool didSucceed = (bool)CFReadStreamOpen(readStream);
    if (!didSucceed) goto done;
    
    // Initialize the hash object
    CC_SHA1_CTX hashObject;
    CC_SHA1_Init(&hashObject);
    
    // Feed the data to the hash object
    bool hasMoreData = true;
    while (hasMoreData) {
        uint8_t buffer[blockSize];
        CFIndex readBytesCount = CFReadStreamRead(readStream,(UInt8 *)buffer,(CFIndex)sizeof(buffer));
        
        if (readBytesCount == -1) break;
        if (readBytesCount == 0) {
            hasMoreData = false;
            continue;
        }
        CC_SHA1_Update(&hashObject,(const void *)buffer,(CC_LONG)readBytesCount);
    }
    
    // Check if the read operation succeeded
    didSucceed = !hasMoreData;
    
    // Compute the hash digest
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &hashObject);
    
    // Abort if the read operation failed
    if (!didSucceed) goto done;
    
    // Compute the string result
	int i = 0;
	for (i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) {
		[hashStr appendFormat:@"%02x",digest[i]];
    }
    
done:    
    if (readStream) {
        CFReadStreamClose(readStream);
        CFRelease(readStream);
    }
    return hashStr;
}

-(NSString *)MD5FromString:(NSString *)inputStr
{
	NSData* inputData = [inputStr dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char outputData[CC_MD5_DIGEST_LENGTH];
	CC_MD5([inputData bytes], (CC_LONG)[inputData length], outputData);
    
	NSMutableString* hashStr = [NSMutableString string];
	int i = 0;
	for (i = 0; i < CC_MD5_DIGEST_LENGTH; ++i)
		[hashStr appendFormat:@"%02x", outputData[i]];
    
	return hashStr;
}

-(NSString *)SHA1FromString:(NSString *)inputStr
{
	NSData* inputData = [inputStr dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char outputData[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1([inputData bytes], (CC_LONG)[inputData length], outputData);
    
	NSMutableString* hashStr = [NSMutableString string];
	int i = 0;
	for (i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
		[hashStr appendFormat:@"%02x", outputData[i]];
    
	return hashStr;
}

@end
