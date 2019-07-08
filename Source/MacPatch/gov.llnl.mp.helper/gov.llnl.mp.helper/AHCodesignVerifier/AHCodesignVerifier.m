//
//  AHCodesignVerifier.m
//
// Copyright (c) 2014 Eldon Ahrold
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AHCodesignVerifier.h"
#import <Security/Security.h>

@implementation AHCodesignVerifier

+ (SecCertificateRef)codesignCertOfItemAtPath:(NSString*)path
                                         deep:(BOOL)deep
                                        error:(NSError* __autoreleasing*)error
{
    SecCertificateRef cert = NULL;
    NSURL* url = [NSURL URLWithString:[path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]];
    if (url) {
        SecStaticCodeRef staticCodeRef = NULL;
        if (SecStaticCodeCreateWithPath((__bridge CFURLRef)(url), 0,
                                        &staticCodeRef) == errSecSuccess) {

            int flags = deep ? kSecCSCheckNestedCode:0;
            CFErrorRef err;
            OSStatus status = SecStaticCodeCheckValidityWithErrors(staticCodeRef, flags, NULL, &err);
            if (status != errSecSuccess) {
                NSError *errorLiteral = CFBridgingRelease(err);
                NSLog(@"CFError %@",errorLiteral.localizedDescription);
                
                [self errorFromSecError:status
                                   item:[path lastPathComponent]
                                  error:error];
            } else {
                CFDictionaryRef codeSigningInfo;
                if (SecCodeCopySigningInformation(staticCodeRef,
                                                  kSecCSSigningInformation,
                                                  &codeSigningInfo) == errSecSuccess) {
                    NSArray* certs = CFDictionaryGetValue(codeSigningInfo, kSecCodeInfoCertificates);
                    if (certs) {
                        cert = (__bridge_retained SecCertificateRef)([certs firstObject]);
                    }
                }
                CFRelease(codeSigningInfo);
            }
            CFRelease(staticCodeRef);
        }
    }
    return cert;
}

+ (NSString*)certNameOfItemAtPath:(NSString*)path
                            error:(NSError* __autoreleasing*)error
{
    CFStringRef certString = NULL;
    NSString* certName = nil;

    SecCertificateRef cert = [self codesignCertOfItemAtPath:path deep:NO error:error];
    if (cert != NULL) {
        if (SecCertificateCopyCommonName(cert, &certString) == errSecSuccess) {
            certName = CFBridgingRelease(certString);
        }
        CFRelease(cert);
    }
    return certName;
}

+ (BOOL)codeSignOfItemAtPathIsValid:(NSString *)path
                               deep:(BOOL)deep
                              error:(NSError *__autoreleasing *)error
{
    SecCertificateRef cert = [self codesignCertOfItemAtPath:path deep:deep error:error];
    if (cert != NULL) {
        CFRelease(cert);
        return YES;
    }
    return NO;

}

+ (BOOL)codeSignOfItemAtPathIsValid:(NSString *)path
                              error:(NSError* __autoreleasing*)error
{
    return [self codeSignOfItemAtPathIsValid:path deep:NO error:error];
}

+ (NSData*)codesignCertDataOfItemAtPath:(NSString*)path
                                  error:(NSError* __autoreleasing*)error
{
    NSData* data = nil;
    SecCertificateRef cert = [self codesignCertOfItemAtPath:path deep:NO error:error];

    if (cert != NULL) {
        data = CFBridgingRelease(SecCertificateCopyData(cert));
        CFRelease(cert);
    }
    return data;
}

+ (BOOL)codesignOfItemAtPath:(NSString*)item1
          isSameAsItemAtPath:(NSString*)item2
                       error:(NSError* __autoreleasing*)error
{
    NSData* certData1 = [self codesignCertDataOfItemAtPath:item1 error:error];
    if (certData1) {
        NSData* certData2 = [self codesignCertDataOfItemAtPath:item2 error:error];
        if (certData2) {
            if ([certData1 isEqualToData:certData2]) {
                return YES;
            } else
                return [self errorFromSecError:errSecAppleSignatureMismatch
                                          item:item1
                                         error:error];
        }
    }
    return NO;
}

+ (BOOL)errorFromSecError:(OSStatus)status
                     item:(NSString*)item
                    error:(NSError* __autoreleasing*)error
{
    NSError* err;
    if (status != errSecSuccess) {
        NSString* emsg = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
        err = [NSError
            errorWithDomain:@"com.eeaapps.csvalidator"
                       code:status
                   userInfo:@{
                       NSLocalizedDescriptionKey : [NSString
                           stringWithFormat:@"Codesign check failed on %@ because %@",
                                            item, emsg]
                   }];
        if (error)
            *error = err;
        return NO;
    } else {
        return YES;
    }
}
@end
