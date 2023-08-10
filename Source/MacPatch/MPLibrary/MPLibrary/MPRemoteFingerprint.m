//
//  MPRemoteFingerprint.m
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

#import "MPRemoteFingerprint.h"
#import <CommonCrypto/CommonDigest.h>

#pragma mark - NSData SHA1 Helper
@interface NSData (sha1)

- (NSData *)sha1;

- (NSData *)sha1Digest;
- (NSString *)hexStringValue;
- (NSString *)hexColonSeperatedStringValue;
@end

@implementation NSData (sha1)

- (NSData *)sha1
{
    unsigned char buffer[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(self.bytes, (CC_LONG)self.length, buffer);
    return [NSData dataWithBytes:buffer length:CC_SHA1_DIGEST_LENGTH];
}

- (NSData *)sha1Digest
{
    unsigned char result[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1([self bytes], (CC_LONG)[self length], result);
    return [NSData dataWithBytes:result length:CC_SHA1_DIGEST_LENGTH];
}

- (NSString *)hexStringValue
{
    NSMutableString *stringBuffer = [NSMutableString stringWithCapacity:([self length] * 2)];
    
    const unsigned char *dataBuffer = [self bytes];
    int i;
    
    for (i = 0; i < [self length]; ++i)
    {
        [stringBuffer appendFormat:@"%02lx", (unsigned long)dataBuffer[i]];
    }
    
    return [stringBuffer copy];
}


- (NSString *)hexColonSeperatedStringValue
{
    return [self hexColonSeperatedStringValueWithCapitals:YES];
}

- (NSString *)hexColonSeperatedStringValueWithCapitals:(BOOL)capitalize {
    NSMutableString *stringBuffer = [NSMutableString stringWithCapacity:([self length] * 3)];
    
    const unsigned char *dataBuffer = [self bytes];
    NSString * format = capitalize ? @"%02X" : @"%02x";
    int i;
    
    for (i = 0; i < [self length]; ++i)
    {
        if (i)
            [stringBuffer appendString:@":"];
        [stringBuffer appendFormat:format, (unsigned long)dataBuffer[i]];
    }
    
    return [stringBuffer copy];
}

@end

#pragma mark - Main Class
@interface MPRemoteFingerprint()

@property (nonatomic, assign, readwrite) NSString *fingerPrint;
@property (nonatomic, assign, readwrite) NSString *remoteFingerPrint;

@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSURLResponse *response;
@property (nonatomic, strong) NSData *responseData;
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, assign) BOOL connectionDidFinishLoading;
@property (nonatomic, strong) NSError *error;

@property (assign, nonatomic) BOOL certVerify;
@property (strong, nonatomic) NSMutableData *data;

@end

@implementation MPRemoteFingerprint

- (BOOL)isValidRemoteFingerPrint:(NSURL *)aURL fingerprint:(NSString *)aFingerprint
{
    BOOL result = NO;
    NSError *urlErr = nil;
    
    self.fingerPrint = aFingerprint;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:aURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.f];
    NSURLResponse *response;
    NSData *urlData = [self sendSynchronousRequest:request returningResponse:&response error:&urlErr];
    if (urlData)
    {
        result = self.certVerify;
    }
    return result;
}

#pragma mark - Private Methods

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error
{
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [self.connection setDelegateQueue:[[NSOperationQueue alloc] init]];
    [self.connection start];
    
    [self waitForDidFinishLoading];
    if (self.error != nil) {
        if (response) *response = self.response;
        if (error) *error = self.error;
        return nil;
    } else {
        if (response) *response = self.response;
        if (error) *error = nil;
        return self.responseData;
    }
}

- (void)waitForDidFinishLoading
{
    [self.condition lock];
    while (!self.connectionDidFinishLoading)
    {
        [self.condition wait];
    }
    [self.condition unlock];
}

#pragma mark NSURLConnection Delegates

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    self.certVerify = NO; // Default Value
    
    if ([[challenge protectionSpace] authenticationMethod] == NSURLAuthenticationMethodServerTrust)
    {
        SecTrustRef trustRef = [[challenge protectionSpace] serverTrust];
        CFIndex count = SecTrustGetCertificateCount(trustRef);
        
        for (CFIndex i = 0; i < count; i++) {
            SecCertificateRef certRef = SecTrustGetCertificateAtIndex(trustRef, i);
            CFDataRef certData = SecCertificateCopyData(certRef);
            
            NSData *sha1 = ((__bridge NSData *)certData).sha1Digest;
            self.remoteFingerPrint = [sha1 hexStringValue];
            CFRelease(certData);
            
            // compare by sha1 strings.
            if ([[[sha1 hexStringValue] uppercaseString] isEqualToString:[self.fingerPrint uppercaseString]]) {
                self.certVerify = YES;
                //success
                [[challenge sender] useCredential:[NSURLCredential credentialForTrust:trustRef] forAuthenticationChallenge:challenge];
                return;
            }
        }
    }
    
    // Fail
    [[challenge sender] cancelAuthenticationChallenge: challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.data = [NSMutableData data];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.data appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self.condition lock];
    self.error = error;
    self.connectionDidFinishLoading = YES;
    [self.condition signal];
    [self.condition unlock];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self.condition lock];
    self.connectionDidFinishLoading = YES;
    [self.condition signal];
    [self.condition unlock];
}

@end
