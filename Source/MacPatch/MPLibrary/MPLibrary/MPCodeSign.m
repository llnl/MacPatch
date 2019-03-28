//
//  MPCodeSign.m
//  MPFramework
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

#import "MPCodeSign.h"
//#import "MPDefaults.h"

@interface MPCodeSign ()
{
    MPSettings *settings;
}
@end

@implementation MPCodeSign

- (id)init
{
    self = [super init];
    if (self)
    {
        settings = [MPSettings sharedInstance];
    }
    return self;
}

- (BOOL)verifyAppleBinary:(NSString *)aFilePath error:(NSError **)err
{
    return [self verifyBinary:aFilePath requirement:@"anchor apple" error:err];
}

- (BOOL)verifyAppleDevBinary:(NSString *)aFilePath error:(NSError **)err
{
    return [self verifyBinary:aFilePath requirement:@"anchor apple generic" error:err];
}

/*
 Use "anchor apple generic" as the requirement type for Apple Developer
 account certs.
 */

- (BOOL)verifyBinary:(NSString *)aFilePath requirement:(NSString *)aRequirement error:(NSError **)err
{
    if (settings.agent.verifySignatures == 0) {
        return YES;
    }
    
    NSError *error = nil;
    BOOL result = NO;
    
    SecStaticCodeRef code = NULL;
    SecRequirementRef ancorReq  = 0;
    
    // File Exists
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:aFilePath]) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"File not found.", nil)};
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:-1 userInfo:userInfo];
        if (err != NULL) *err = error;
        return result;
    }
    
    CFStringRef pathStr = CFStringCreateWithCString( kCFAllocatorDefault, [aFilePath UTF8String], kCFStringEncodingUTF8 );
    if( pathStr == NULL ) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"File not found.", nil)};
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:-2 userInfo:userInfo];
        if (err != NULL) *err = error;
        return result;
    }
    
    CFURLRef pathURL = CFURLCreateWithString( kCFAllocatorDefault, pathStr, NULL );
    CFRelease(pathStr);
    
    if( pathURL == NULL ) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"Unable to convert path to CFURL.", nil)};
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:-3 userInfo:userInfo];
        if (err != NULL) *err = error;
        return result;
    }
    
    OSStatus status = SecStaticCodeCreateWithPath( pathURL, kSecCSDefaultFlags, &code );
    CFRelease(pathURL);
    
    if( status ) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        if (err != NULL) *err = error;
        return result;
    }
    
    status = SecRequirementCreateWithString( (__bridge CFStringRef)aRequirement, kSecCSDefaultFlags, &ancorReq );
    if( status ) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        if (err != NULL) *err = error;
        return result;
    }
    
    status = SecStaticCodeCheckValidity(code, kSecCSDefaultFlags, ancorReq );
    if (status == errSecSuccess) {
        result = YES;
    } else {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
    
    if (err != NULL) *err = error;
    
    if (result != YES) {
        logit(lcl_vError,@"%@ is not signed or trusted.",aFilePath);
    }
    return result;
}

@end
