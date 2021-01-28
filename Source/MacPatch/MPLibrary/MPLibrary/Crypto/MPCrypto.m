//
//  MPCrypto.m
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

#import "MPCrypto.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

#define BUF_SIZE 4096

@interface MPCrypto (hidden)

- (NSString *)MD5HashForFile:(NSString *)aFilePath;
- (NSString *)SHA1HashForFile:(NSString *)aFilePath;

- (NSString *)MD5FromString:(NSString *)inputStr;
- (NSString *)SHA1FromString:(NSString *)inputStr;

- (SecKeychainRef)genSecKeychainRef;

@end


@implementation MPCrypto
{
    SecKeychainRef keychainItem;
    SecKeyRef localPrivateKey;
    SecKeyRef localPublicKey;
}

#pragma mark -
#pragma mark Public API Digest Hashing

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
        qlerror(@"Unable to get file hash for %@, file does not exist.",aFile);
        return @"ERROR_FILE_MISSING";
    }
    
    if ([aType isEqualToString:@"MD5"]) {
        return [self MD5HashForFile:aFile];
    } else if ([aType isEqualToString:@"SHA1"]) {
        return [self SHA1HashForFile:aFile];
    }
    
    return NULL;
}

#pragma mark Convienience Methods
- (NSString *)md5HashForFile:(NSString *)aFilePath
{
    return [self MD5HashForFile:aFilePath];
}

- (NSString *)sha1HashForFile:(NSString *)aFilePath
{
    return [self SHA1HashForFile:aFilePath];
}

#pragma mark Private API

- (NSString *)MD5HashForFile:(NSString *)aFilePath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:aFilePath]) {
        qlerror(@"Unable to find %@, MD5HashForFile failed.",aFilePath);
        return @"ERROR FILE MISSING";
    }
    
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
    qldebug(@"MD5 HASH=%@",hashStr);
    return hashStr;
}

- (NSString *)SHA1HashForFile:(NSString *)aFilePath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:aFilePath]) {
        qlerror(@"Unable to find %@, MD5HashForFile failed.",aFilePath);
        return @"ERROR FILE MISSING";
    }
    
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
    qldebug(@"SHA1 HASH=%@",hashStr);
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

#pragma mark - RSA Keys

#pragma mark Private API

- (SecKeychainRef)genSecKeychainRef
{
    logit(lcl_vDebug,@"genSecKeychainRef called");
    OSStatus err;
    SecKeychainRef keychain = NULL;

    NSString *_keyID = [NSString stringWithFormat: @"mp_%.0f", [NSDate timeIntervalSinceReferenceDate] * 1000.0];
    NSString *_keychainFileName = [NSString stringWithFormat: @"%@.%@", _keyID, @"keychain"];
    NSString *_keychain = [NSTemporaryDirectory() stringByAppendingPathComponent:_keychainFileName];
    const char *pass = [_keyID UTF8String];
    logit(lcl_vDebug,@"Create temporary keychain for rsa key gen.");
    logit(lcl_vDebug,@"keyID: %@",_keyID);
    logit(lcl_vDebug,@"keychainFileName: %@",_keychainFileName);
    logit(lcl_vDebug,@"keychain: %@",_keychain);
    
    err = SecKeychainCreate([_keychain UTF8String], (UInt32)strlen(pass), pass, FALSE, NULL, &keychain);
    
    if (err != noErr) {
        logit(lcl_vError,@"%@",[self errorForOSStatus:err]);
    }
    
    return keychain;
}

#pragma mark Public API
- (int)generateRSAKeyPairOfSize:(unsigned)keySize error:(NSError **)error
{
    keychainItem = [self genSecKeychainRef];
    
    OSStatus err;
    err = SecKeyCreatePair(keychainItem,
                           CSSM_ALGID_RSA,
                           keySize,
                           0LL,
                           CSSM_KEYUSE_ENCRYPT | CSSM_KEYUSE_VERIFY | CSSM_KEYUSE_WRAP,     // public key
                           CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_PERMANENT,
                           CSSM_KEYUSE_ANY,                                                 // private key
                           CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_PERMANENT ,
                           NULL,                                                            // SecAccessRef
                           &localPublicKey, &localPrivateKey);
    
    if (error != NULL) *error = [self errorForOSStatus:err];
    return (int)err;
}

// @param format  The data format: kSecFormatPEMSequence, kSecFormatWrappedOpenSSL, kSecFormatOpenSSL, kSecFormatSSH, kSecFormatBSAFE or kSecFormatSSHv2.
- (NSData *)exportPrivateKeyInFormat:(SecExternalFormat)format withPEM:(BOOL)withPEM error:(NSError **)error
{
    OSStatus err;
    CFDataRef data = NULL;
    err = SecItemExport(localPrivateKey, format , (withPEM ?kSecItemPemArmour :0), NULL, &data);
    
    if (error != NULL) *error = [self errorForOSStatus:err];
    return (__bridge NSData *)data;
}

- (NSData *)exportPublicKeyInFormat:(SecExternalFormat)format withPEM:(BOOL)withPEM error:(NSError **)error
{
    OSStatus err;
    CFDataRef data = NULL;
    err = SecItemExport(localPublicKey, format , (withPEM ?kSecItemPemArmour :0), NULL, &data);
    
    if (error != NULL) *error = [self errorForOSStatus:err];
    return (__bridge NSData *)data;
}

- (NSString *)exportRSAPemKeyAsString:(SecKeyRef)aKey error:(NSError **)error
{
    OSStatus err;
    CFDataRef data = NULL;
    err = SecItemExport(aKey, kSecFormatPEMSequence , kSecItemPemArmour, NULL, &data);
    
    if (error != NULL) *error = [self errorForOSStatus:err];
    
    NSString *keyStr = [[NSString alloc] initWithData:(__bridge NSData *)data encoding:NSUTF8StringEncoding];
    return keyStr;
}

- (SecKeyRef)getKeyRef:(NSData *)aKeyData
{
    return [self getKeyRef:aKeyData format:kSecFormatPEMSequence];
}

- (SecKeyRef)getKeyRef:(NSData *)aKeyData format:(SecExternalFormat)aFormat
{
    CFArrayRef imported = NULL;
    OSStatus err = 0;
    SecExternalFormat format = kSecFormatPEMSequence;
    
    //err = SecItemImport((__bridge CFDataRef)(aKeyData), (CFStringRef)@"pem", &format, NULL, kNilOptions, kNilOptions, NULL, &imported);
    err = SecItemImport((__bridge CFDataRef)(aKeyData), (CFStringRef)@"pem", &format, NULL, kNilOptions, NULL, NULL, &imported);
    if (err != 0) {
        qlerror(@"SecItemImport[importPublicKey]: %@ ERROR: %@", self.class, [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]);
    }
    
    assert(err == errSecSuccess);
    assert(CFArrayGetCount(imported) == 1);
    return (SecKeyRef)CFArrayGetValueAtIndex(imported, 0);
}


#pragma mark Registration

- (NSDictionary *)rsaKeysForRegistration:(NSError **)error
{
    NSError *err = nil;
    NSString *priKeyStr = [self exportRSAPemKeyAsString:localPrivateKey error:&err];
    if (err) {
        if (error != NULL) *error = err;
        return nil;
    }
    NSString *pubKeyStr = [self exportRSAPemKeyAsString:localPublicKey error:&err];
    if (err) {
        if (error != NULL) *error = err;
        return nil;
    }
    
    return @{@"privateKey":priKeyStr,@"publicKey":pubKeyStr};
}

#pragma mark Misc

- (NSString *)stripAndEncodePEMKey:(NSString *)aKey isPublic:(BOOL)aPublic
{
    NSString *startHeader;
    NSString *endHeader;
    
    if (aPublic) {
        NSRange isRange = [aKey rangeOfString:@"BEGIN RSA PUBLIC KEY" options:NSCaseInsensitiveSearch];
        if(isRange.location != NSNotFound) {
            startHeader = @"-----BEGIN RSA PUBLIC KEY-----";
            endHeader = @"-----END RSA PUBLIC KEY-----";
        } else {
            NSRange isSpacedRange = [aKey rangeOfString:@"BEGIN PUBLIC KEY" options:NSCaseInsensitiveSearch];
            if(isSpacedRange.location != NSNotFound) {
                startHeader = @"-----BEGIN PUBLIC KEY-----";
                endHeader = @"-----END PUBLIC KEY-----";
            } else {
                return nil;
            }
        }
    } else {
        startHeader = @"-----BEGIN RSA PRIVATE KEY-----";
        endHeader = @"-----END RSA PRIVATE KEY-----";
    }
    
    NSString *keyStr;
    NSScanner *scanner = [NSScanner scannerWithString:aKey];
    [scanner scanUpToString:startHeader intoString:nil];
    [scanner scanString:startHeader intoString:nil];
    [scanner scanUpToString:endHeader intoString:&keyStr];
    
    return [keyStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - Encryption using RSA Keys
- (NSString *)encryptStringUsingKey:(NSString *)stringToEncrypt key:(SecKeyRef)aKey error:(NSError **)err
{
    return [self secKeyEncrypt:aKey padding:kSecPaddingPKCS1 stringToEncrypt:stringToEncrypt error:err];
}

- (NSString *)secKeyEncrypt:(SecKeyRef)aKey padding:(SecPadding)aSecPadding stringToEncrypt:(NSString *)AstringToEncrypt error:(NSError **)err
{
    
    NSData *plainData = [AstringToEncrypt dataUsingEncoding:NSUTF8StringEncoding];
    const void *plainBytes = [plainData bytes];
    int plainLength = (int)[plainData length];
    
    const uint8_t *plainText = (uint8_t*)plainBytes;
    size_t plainTextLen = plainLength;
    
    CFMutableDictionaryRef parameters = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                  0,
                                                                  &kCFTypeDictionaryKeyCallBacks,
                                                                  &kCFTypeDictionaryValueCallBacks);
    
    CFDictionarySetValue(parameters, kSecAttrKeyType, kSecAttrKeyTypeAES);
    
    CFErrorRef error;
    SecTransformRef encrypt = SecEncryptTransformCreate(aKey, &error);
    
    if (error) {
        if (err != NULL) *err = (__bridge NSError *)error;
        
        qlerror(@"Encryption failed: %@\n", (__bridge NSError *)error);
        return nil;
    }
    
    /*
    SecTransformSetAttribute(encrypt,
                             kSecPaddingKey,
                             NULL, // kSecPaddingPKCS1Key (rdar://13661366 : NULL means kSecPaddingPKCS1Key and
                             // kSecPaddingPKCS1Key fails horribly)
                             &error);
    */
    
    // Switched to kSecPaddingOAEPKey
    SecTransformSetAttribute(encrypt, kSecPaddingKey, kSecPaddingOAEPKey, &error);
    
    CFDataRef sourceData = CFDataCreate(kCFAllocatorDefault, plainText, plainTextLen);
    SecTransformSetAttribute(encrypt, kSecTransformInputAttributeName, sourceData, &error);
    
    CFDataRef encryptedData = SecTransformExecute(encrypt, &error);
    if (error) {
        if (err != NULL) *err = (__bridge NSError *)error;
        
        qlerror(@"Encryption failed: %@\n", (__bridge NSError *)error);
        return nil;
    }
    
    // Switch to Apple method when 10.9 is min OS
    return [(__bridge NSData *)encryptedData base64EncodedString];
}

- (NSString *)decryptStringUsingKey:(NSString *)stringToDecrypt key:(SecKeyRef)aKey error:(NSError **)err
{
    return [self secKeyDecrypt:aKey padding:kSecPaddingPKCS1 stringToDecrypt:stringToDecrypt error:err];
}

- (NSString *)secKeyDecrypt:(SecKeyRef)aKey padding:(SecPadding)aSecPadding stringToDecrypt:(NSString *)AstringToDecrypt error:(NSError **)err
{
    
    // Switch to Apple method when 10.9 is min OS
    NSData *encData = [NSData dataFromBase64String:AstringToDecrypt];
    
    CFMutableDictionaryRef parameters = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                  0,
                                                                  &kCFTypeDictionaryKeyCallBacks,
                                                                  &kCFTypeDictionaryValueCallBacks);
    
    CFDictionarySetValue(parameters, kSecAttrKeyType, kSecAttrKeyTypeAES);
    
    CFErrorRef error = nil;
    SecTransformRef decrypt = SecDecryptTransformCreate(aKey, &error);
    if (error) {
        if (err != NULL) *err = (__bridge NSError *)error;
        
        qlerror(@"Encryption failed: %@\n", (__bridge NSError *)error);
        return nil;
    }
    /*
    SecTransformSetAttribute(decrypt,
                             kSecPaddingKey,
                             NULL, // kSecPaddingPKCS1Key (rdar://13661366 : NULL means kSecPaddingPKCS1Key and kSecPaddingPKCS1Key fails horribly)
                             &error);
    */
    
    // Switched to kSecPaddingOAEPKey
    SecTransformSetAttribute(encrypt, kSecPaddingKey, kSecPaddingOAEPKey, &error);
    
    SecTransformSetAttribute(decrypt, kSecTransformInputAttributeName, (CFDataRef)encData, &error);
    
    CFDataRef decryptedData = SecTransformExecute(decrypt, &error);
    if (error) {
        if (err != NULL) *err = (__bridge NSError *)error;
        
        qlerror(@"Encryption failed: %@\n", (__bridge NSError *)error);
        return nil;
    }
    
    NSString *newStr = [[NSString alloc] initWithData:(__bridge NSData *)decryptedData encoding:NSUTF8StringEncoding];
    return newStr;
}

#pragma mark - Error Codes for OSStatus

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message
{
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: message};
    return [NSError errorWithDomain:@"MPCryptoDomain" code:code userInfo:userInfo];
}

- (NSError *)errorForOSStatus:(OSStatus)OSStatus
{
    switch (OSStatus)
    {
        default:
        case errSecSuccess:
        {
            return nil;
        }
            
        case errSecUnimplemented:
        {
            return [self errorWithCode:OSStatus message:@"Function or operation not implemented"];
        }
            
        case errSecIO:
        {
            return [self errorWithCode:OSStatus message:@"I/O error (bummers)"];
        }
            
        case errSecParam:
        {
            return [self errorWithCode:OSStatus message:@"One or more parameters passed to a function where not valid"];
        }
            
        case errSecAllocate:
        {
            return [self errorWithCode:OSStatus message:@"Failed to allocate memory"];
        }
            
        case errSecUserCanceled:
        {
            return [self errorWithCode:OSStatus message:@"User canceled the operation"];
        }
            
        case errSecBadReq:
        {
            return [self errorWithCode:OSStatus message:@"Bad parameter or invalid state for operation"];
        }
            
        case errSecInternalComponent:
        {
            return nil;
        }
            
        case errSecNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"No keychain is available. You may need to restart your computer"];;
        }
            
        case errSecDuplicateItem:
        {
            return [self errorWithCode:OSStatus message:@"The specified item already exists in the keychain"];;
        }
            
        case errSecItemNotFound:
        {
            return [self errorWithCode:OSStatus message:@"The specified item could not be found in the keychain"];;
        }
            
        case errSecInteractionNotAllowed:
        {
            return [self errorWithCode:OSStatus message:@"User interaction is not allowed"];;
        }
            
        case errSecDecode:
        {
            return [self errorWithCode:OSStatus message:@"Unable to decode the provided data"];;
        }
            
        case errSecAuthFailed:
        {
            return [self errorWithCode:OSStatus message:@"The user name or passphrase you entered is not correct"];;
        }
            
        case 100002:
        {
            // kPOSIXErrorEACCES
            return [self errorWithCode:OSStatus message:@"Permission denied"];
        }
            
        case errSecWrPerm:
        {
            return [self errorWithCode:OSStatus message:@"write permissions error"];
        }
            
        case errSecReadOnly:
        {
            return [self errorWithCode:OSStatus message:@"This keychain cannot be modified."];
        }
            
        case errSecNoSuchKeychain:
        {
            return [self errorWithCode:OSStatus message:@"The specified keychain could not be found."];
        }
            
        case errSecInvalidKeychain:
        {
            return [self errorWithCode:OSStatus message:@"The specified keychain is not a valid keychain file."];
        }
            
        case errSecDuplicateKeychain:
        {
            return [self errorWithCode:OSStatus message:@"A keychain with the same name already exists."];
        }
            
        case errSecDuplicateCallback:
        {
            return [self errorWithCode:OSStatus message:@"The specified callback function is already installed."];
        }
            
        case errSecInvalidCallback:
        {
            return [self errorWithCode:OSStatus message:@"The specified callback function is not valid."];
        }
            
        case errSecBufferTooSmall:
        {
            return [self errorWithCode:OSStatus message:@"There is not enough memory available to use the specified item."];
        }
            
        case errSecDataTooLarge:
        {
            return [self errorWithCode:OSStatus message:@"This item contains information which is too large or in a format that cannot be displayed."];
        }
            
        case errSecNoSuchAttr:
        {
            return [self errorWithCode:OSStatus message:@"The specified attribute does not exist."];
        }
            
        case errSecInvalidItemRef:
        {
            return [self errorWithCode:OSStatus message:@"The specified item is no longer valid. It may have been deleted from the keychain."];
        }
            
        case errSecInvalidSearchRef:
        {
            return [self errorWithCode:OSStatus message:@"Unable to search the current keychain."];
        }
            
        case errSecNoSuchClass:
        {
            return [self errorWithCode:OSStatus message:@"The specified item does not appear to be a valid keychain item."];
        }
            
        case errSecNoDefaultKeychain:
        {
            return [self errorWithCode:OSStatus message:@"A default keychain could not be found."];
        }
            
        case errSecReadOnlyAttr:
        {
            return [self errorWithCode:OSStatus message:@"The specified attribute could not be modified."];
        }
            
        case errSecWrongSecVersion:
        {
            return [self errorWithCode:OSStatus message:@"This keychain was created by a different version of the system software and cannot be opened."];
        }
            
        case errSecKeySizeNotAllowed:
        {
            return [self errorWithCode:OSStatus message:@"This item specifies a key size which is too large."];
        }
            
        case errSecNoStorageModule:
        {
            return [self errorWithCode:OSStatus message:@"A required component (data storage module) could not be loaded. You may need to restart your computer."];
        }
            
        case errSecNoCertificateModule:
        {
            return [self errorWithCode:OSStatus message:@"A required component (certificate module) could not be loaded. You may need to restart your computer."];
        }
            
        case errSecNoPolicyModule:
        {
            return [self errorWithCode:OSStatus message:@"A required component (policy module) could not be loaded. You may need to restart your computer."];
        }
            
        case errSecInteractionRequired:
        {
            return [self errorWithCode:OSStatus message:@"User interaction is required but is currently not allowed."];
        }
            
        case errSecDataNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"The contents of this item cannot be retrieved."];
        }
            
        case errSecDataNotModifiable:
        {
            return [self errorWithCode:OSStatus message:@"The contents of this item cannot be modified."];
        }
            
        case errSecCreateChainFailed:
        {
            return [self errorWithCode:OSStatus message:@"One or more certificates required to validate this certificate cannot be found."];
        }
            
        case errSecInvalidPrefsDomain:
        {
            return [self errorWithCode:OSStatus message:@"The specified preferences domain is not valid."];
        }
            
        case errSecInDarkWake:
        {
            return [self errorWithCode:OSStatus message:@"In dark wake no UI possible"];
        }
            
        case errSecACLNotSimple:
        {
            return [self errorWithCode:OSStatus message:@"The specified access control list is not in standard (simple) form."];
        }
            
        case errSecPolicyNotFound:
        {
            return [self errorWithCode:OSStatus message:@"The specified policy cannot be found."];
        }
            
        case errSecInvalidTrustSetting:
        {
            return [self errorWithCode:OSStatus message:@"The specified trust setting is invalid."];
        }
            
        case errSecNoAccessForItem:
        {
            return [self errorWithCode:OSStatus message:@"The specified item has no access control."];
        }
            
        case errSecInvalidOwnerEdit:
        {
            return [self errorWithCode:OSStatus message:@"Invalid attempt to change the owner of this item."];
        }
            
        case errSecTrustNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"No trust results are available."];
        }
            
        case errSecUnsupportedFormat:
        {
            return [self errorWithCode:OSStatus message:@"Import/Export format unsupported."];
        }
            
        case errSecUnknownFormat:
        {
            return [self errorWithCode:OSStatus message:@"Unknown format in import."];
        }
            
        case errSecKeyIsSensitive:
        {
            return [self errorWithCode:OSStatus message:@"Key material must be wrapped for export."];
        }
            
        case errSecMultiplePrivKeys:
        {
            return [self errorWithCode:OSStatus message:@"An attempt was made to import multiple private keys."];
        }
            
        case errSecPassphraseRequired:
        {
            return [self errorWithCode:OSStatus message:@"Passphrase is required for import/export."];
        }
            
        case errSecInvalidPasswordRef:
        {
            return [self errorWithCode:OSStatus message:@"The password reference was invalid."];
        }
            
        case errSecInvalidTrustSettings:
        {
            return [self errorWithCode:OSStatus message:@"The Trust Settings Record was corrupted."];
        }
            
        case errSecNoTrustSettings:
        {
            return [self errorWithCode:OSStatus message:@"No Trust Settings were found."];
        }
            
        case errSecPkcs12VerifyFailure:
        {
            return [self errorWithCode:OSStatus message:@"MAC verification failed during PKCS12 import (wrong password?)"];
        }
            
        case errSecNotSigner:
        {
            return [self errorWithCode:OSStatus message:@"A certificate was not signed by its proposed parent."];
        }
            
        case errSecServiceNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"The required service is not available."];
        }
            
        case errSecInsufficientClientID:
        {
            return [self errorWithCode:OSStatus message:@"The client ID is not correct."];
        }
            
        case errSecDeviceReset:
        {
            return [self errorWithCode:OSStatus message:@"A device reset has occurred."];
        }
            
        case errSecDeviceFailed:
        {
            return [self errorWithCode:OSStatus message:@"A device failure has occurred."];
        }
            
        case errSecAppleAddAppACLSubject:
        {
            return [self errorWithCode:OSStatus message:@"Adding an application ACL subject failed."];
        }
            
        case errSecApplePublicKeyIncomplete:
        {
            return [self errorWithCode:OSStatus message:@"The public key is incomplete."];
        }
            
        case errSecAppleSignatureMismatch:
        {
            return [self errorWithCode:OSStatus message:@"A signature mismatch has occurred."];
        }
            
        case errSecAppleInvalidKeyStartDate:
        {
            return [self errorWithCode:OSStatus message:@"The specified key has an invalid start date."];
        }
            
        case errSecAppleInvalidKeyEndDate:
        {
            return [self errorWithCode:OSStatus message:@"The specified key has an invalid end date."];
        }
            
        case errSecConversionError:
        {
            return [self errorWithCode:OSStatus message:@"A conversion error has occurred."];
        }
            
        case errSecAppleSSLv2Rollback:
        {
            return [self errorWithCode:OSStatus message:@"A SSLv2 rollback error has occurred."];
        }
            
        case errSecDiskFull:
        {
            return [self errorWithCode:OSStatus message:@"The disk is full."];
        }
            
        case errSecQuotaExceeded:
        {
            return [self errorWithCode:OSStatus message:@"The quota was exceeded."];
        }
            
        case errSecFileTooBig:
        {
            return [self errorWithCode:OSStatus message:@"The file is too big."];
        }
            
        case errSecInvalidDatabaseBlob:
        {
            return [self errorWithCode:OSStatus message:@"The specified database has an invalid blob."];
        }
            
        case errSecInvalidKeyBlob:
        {
            return [self errorWithCode:OSStatus message:@"The specified database has an invalid key blob."];
        }
            
        case errSecIncompatibleDatabaseBlob:
        {
            return [self errorWithCode:OSStatus message:@"The specified database has an incompatible blob."];
        }
            
        case errSecIncompatibleKeyBlob:
        {
            return [self errorWithCode:OSStatus message:@"The specified database has an incompatible key blob."];
        }
            
        case errSecHostNameMismatch:
        {
            return [self errorWithCode:OSStatus message:@"A host name mismatch has occurred."];
        }
            
        case errSecUnknownCriticalExtensionFlag:
        {
            return [self errorWithCode:OSStatus message:@"There is an unknown critical extension flag."];
        }
            
        case errSecNoBasicConstraints:
        {
            return [self errorWithCode:OSStatus message:@"No basic constraints were found."];
        }
            
        case errSecNoBasicConstraintsCA:
        {
            return [self errorWithCode:OSStatus message:@"No basic CA constraints were found."];
        }
            
        case errSecInvalidAuthorityKeyID:
        {
            return [self errorWithCode:OSStatus message:@"The authority key ID is not valid."];
        }
            
        case errSecInvalidSubjectKeyID:
        {
            return [self errorWithCode:OSStatus message:@"The subject key ID is not valid."];
        }
            
        case errSecInvalidKeyUsageForPolicy:
        {
            return [self errorWithCode:OSStatus message:@"The key usage is not valid for the specified policy."];
        }
            
        case errSecInvalidExtendedKeyUsage:
        {
            return [self errorWithCode:OSStatus message:@"The extended key usage is not valid."];
        }
            
        case errSecInvalidIDLinkage:
        {
            return [self errorWithCode:OSStatus message:@"The ID linkage is not valid."];
        }
            
        case errSecPathLengthConstraintExceeded:
        {
            return [self errorWithCode:OSStatus message:@"The path length constraint was exceeded."];
        }
            
        case errSecInvalidRoot:
        {
            return [self errorWithCode:OSStatus message:@"The root or anchor certificate is not valid."];
        }
            
        case errSecCRLExpired:
        {
            return [self errorWithCode:OSStatus message:@"The CRL has expired."];
        }
            
        case errSecCRLNotValidYet:
        {
            return [self errorWithCode:OSStatus message:@"The CRL is not yet valid."];
        }
            
        case errSecCRLNotFound:
        {
            return [self errorWithCode:OSStatus message:@"The CRL was not found."];
        }
            
        case errSecCRLServerDown:
        {
            return [self errorWithCode:OSStatus message:@"The CRL server is down."];
        }
            
        case errSecCRLBadURI:
        {
            return [self errorWithCode:OSStatus message:@"The CRL has a bad Uniform Resource Identifier."];
        }
            
        case errSecUnknownCertExtension:
        {
            return [self errorWithCode:OSStatus message:@"An unknown certificate extension was encountered."];
        }
            
        case errSecUnknownCRLExtension:
        {
            return [self errorWithCode:OSStatus message:@"An unknown CRL extension was encountered."];
        }
            
        case errSecCRLNotTrusted:
        {
            return [self errorWithCode:OSStatus message:@"The CRL is not trusted."];
        }
            
        case errSecCRLPolicyFailed:
        {
            return [self errorWithCode:OSStatus message:@"The CRL policy failed."];
        }
            
        case errSecIDPFailure:
        {
            return [self errorWithCode:OSStatus message:@"The issuing distribution point was not valid."];
        }
            
        case errSecSMIMEEmailAddressesNotFound:
        {
            return [self errorWithCode:OSStatus message:@"An email address mismatch was encountered."];
        }
            
        case errSecSMIMEBadExtendedKeyUsage:
        {
            return [self errorWithCode:OSStatus message:@"The appropriate extended key usage for SMIME was not found."];
        }
            
        case errSecSMIMEBadKeyUsage:
        {
            return [self errorWithCode:OSStatus message:@"The key usage is not compatible with SMIME."];
        }
            
        case errSecSMIMEKeyUsageNotCritical:
        {
            return [self errorWithCode:OSStatus message:@"The key usage extension is not marked as critical."];
        }
            
        case errSecSMIMENoEmailAddress:
        {
            return [self errorWithCode:OSStatus message:@"No email address was found in the certificate."];
        }
            
        case errSecSMIMESubjAltNameNotCritical:
        {
            return [self errorWithCode:OSStatus message:@"The subject alternative name extension is not marked as critical."];
        }
            
        case errSecSSLBadExtendedKeyUsage:
        {
            return [self errorWithCode:OSStatus message:@"The appropriate extended key usage for SSL was not found."];
        }
            
        case errSecOCSPBadResponse:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP response was incorrect or could not be parsed."];
        }
            
        case errSecOCSPBadRequest:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP request was incorrect or could not be parsed."];
        }
            
        case errSecOCSPUnavailable:
        {
            return [self errorWithCode:OSStatus message:@"OCSP service is unavailable."];
        }
            
        case errSecOCSPStatusUnrecognized:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP server did not recognize this certificate."];
        }
            
        case errSecEndOfData:
        {
            return [self errorWithCode:OSStatus message:@"An end-of-data was detected."];
        }
            
        case errSecIncompleteCertRevocationCheck:
        {
            return [self errorWithCode:OSStatus message:@"An incomplete certificate revocation check occurred."];
        }
            
        case errSecNetworkFailure:
        {
            return [self errorWithCode:OSStatus message:@"A network failure occurred."];
        }
            
        case errSecOCSPNotTrustedToAnchor:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP response was not trusted to a root or anchor certificate."];
        }
            
        case errSecRecordModified:
        {
            return [self errorWithCode:OSStatus message:@"The record was modified."];
        }
            
        case errSecOCSPSignatureError:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP response had an invalid signature."];
        }
            
        case errSecOCSPNoSigner:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP response had no signer."];
        }
            
        case errSecOCSPResponderMalformedReq:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP responder was given a malformed request."];
        }
            
        case errSecOCSPResponderInternalError:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP responder encountered an internal error."];
        }
            
        case errSecOCSPResponderTryLater:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP responder is busy try again later."];
        }
            
        case errSecOCSPResponderSignatureRequired:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP responder requires a signature."];
        }
            
        case errSecOCSPResponderUnauthorized:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP responder rejected this request as unauthorized."];
        }
            
        case errSecOCSPResponseNonceMismatch:
        {
            return [self errorWithCode:OSStatus message:@"The OCSP response nonce did not match the request."];
        }
            
        case errSecCodeSigningBadCertChainLength:
        {
            return [self errorWithCode:OSStatus message:@"Code signing encountered an incorrect certificate chain length."];
        }
            
        case errSecCodeSigningNoBasicConstraints:
        {
            return [self errorWithCode:OSStatus message:@"Code signing found no basic constraints."];
        }
            
        case errSecCodeSigningBadPathLengthConstraint:
        {
            return [self errorWithCode:OSStatus message:@"Code signing encountered an incorrect path length constraint."];
        }
            
        case errSecCodeSigningNoExtendedKeyUsage:
        {
            return [self errorWithCode:OSStatus message:@"Code signing found no extended key usage."];
        }
            
        case errSecCodeSigningDevelopment:
        {
            return [self errorWithCode:OSStatus message:@"Code signing indicated use of a development-only certificate."];
        }
            
        case errSecResourceSignBadCertChainLength:
        {
            return [self errorWithCode:OSStatus message:@"Resource signing has encountered an incorrect certificate chain length."];
        }
            
        case errSecResourceSignBadExtKeyUsage:
        {
            return [self errorWithCode:OSStatus message:@"Resource signing has encountered an error in the extended key usage."];
        }
            
        case errSecTrustSettingDeny:
        {
            return [self errorWithCode:OSStatus message:@"The trust setting for this policy was set to Deny."];
        }
            
        case errSecInvalidSubjectName:
        {
            return [self errorWithCode:OSStatus message:@"An invalid certificate subject name was encountered."];
        }
            
        case errSecUnknownQualifiedCertStatement:
        {
            return [self errorWithCode:OSStatus message:@"An unknown qualified certificate statement was encountered."];
        }
            
        case errSecMobileMeRequestQueued:
        {
            return [self errorWithCode:OSStatus message:@"The MobileMe request will be sent during the next connection."];
        }
            
        case errSecMobileMeRequestRedirected:
        {
            return [self errorWithCode:OSStatus message:@"The MobileMe request was redirected."];
        }
            
        case errSecMobileMeServerError:
        {
            return [self errorWithCode:OSStatus message:@"A MobileMe server error occurred."];
        }
            
        case errSecMobileMeServerNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"The MobileMe server is not available."];
        }
            
        case errSecMobileMeServerAlreadyExists:
        {
            return [self errorWithCode:OSStatus message:@"The MobileMe server reported that the item already exists."];
        }
            
        case errSecMobileMeServerServiceErr:
        {
            return [self errorWithCode:OSStatus message:@"A MobileMe service error has occurred."];
        }
            
        case errSecMobileMeRequestAlreadyPending:
        {
            return [self errorWithCode:OSStatus message:@"A MobileMe request is already pending."];
        }
            
        case errSecMobileMeNoRequestPending:
        {
            return [self errorWithCode:OSStatus message:@"MobileMe has no request pending."];
        }
            
        case errSecMobileMeCSRVerifyFailure:
        {
            return [self errorWithCode:OSStatus message:@"A MobileMe CSR verification failure has occurred."];
        }
            
        case errSecMobileMeFailedConsistencyCheck:
        {
            return [self errorWithCode:OSStatus message:@"MobileMe has found a failed consistency check."];
        }
            
        case errSecNotInitialized:
        {
            return [self errorWithCode:OSStatus message:@"A function was called without initializing CSSM."];
        }
            
        case errSecInvalidHandleUsage:
        {
            return [self errorWithCode:OSStatus message:@"The CSSM handle does not match with the service type."];
        }
            
        case errSecPVCReferentNotFound:
        {
            return [self errorWithCode:OSStatus message:@"A reference to the calling module was not found in the list of authorized callers."];
        }
            
        case errSecFunctionIntegrityFail:
        {
            return [self errorWithCode:OSStatus message:@"A function address was not within the verified module."];
        }
            
        case errSecInternalError:
        {
            return [self errorWithCode:OSStatus message:@"An internal error has occurred."];
        }
            
        case errSecMemoryError:
        {
            return [self errorWithCode:OSStatus message:@"A memory error has occurred."];
        }
            
        case errSecInvalidData:
        {
            return [self errorWithCode:OSStatus message:@"Invalid data was encountered."];
        }
            
        case errSecMDSError:
        {
            return [self errorWithCode:OSStatus message:@"A Module Directory Service error has occurred."];
        }
            
        case errSecInvalidPointer:
        {
            return [self errorWithCode:OSStatus message:@"An invalid pointer was encountered."];
        }
            
        case errSecSelfCheckFailed:
        {
            return [self errorWithCode:OSStatus message:@"Self-check has failed."];
        }
            
        case errSecFunctionFailed:
        {
            return [self errorWithCode:OSStatus message:@"A function has failed."];
        }
            
        case errSecModuleManifestVerifyFailed:
        {
            return [self errorWithCode:OSStatus message:@"A module manifest verification failure has occurred."];
        }
            
        case errSecInvalidGUID:
        {
            return [self errorWithCode:OSStatus message:@"An invalid GUID was encountered."];
        }
            
        case errSecInvalidHandle:
        {
            return [self errorWithCode:OSStatus message:@"An invalid handle was encountered."];
        }
            
        case errSecInvalidDBList:
        {
            return [self errorWithCode:OSStatus message:@"An invalid DB list was encountered."];
        }
            
        case errSecInvalidPassthroughID:
        {
            return [self errorWithCode:OSStatus message:@"An invalid passthrough ID was encountered."];
        }
            
        case errSecInvalidNetworkAddress:
        {
            return [self errorWithCode:OSStatus message:@"An invalid network address was encountered."];
        }
            
        case errSecCRLAlreadySigned:
        {
            return [self errorWithCode:OSStatus message:@"The certificate revocation list is already signed."];
        }
            
        case errSecInvalidNumberOfFields:
        {
            return [self errorWithCode:OSStatus message:@"An invalid number of fields were encountered."];
        }
            
        case errSecVerificationFailure:
        {
            return [self errorWithCode:OSStatus message:@"A verification failure occurred."];
        }
            
        case errSecUnknownTag:
        {
            return [self errorWithCode:OSStatus message:@"An unknown tag was encountered."];
        }
            
        case errSecInvalidSignature:
        {
            return [self errorWithCode:OSStatus message:@"An invalid signature was encountered."];
        }
            
        case errSecInvalidName:
        {
            return [self errorWithCode:OSStatus message:@"An invalid name was encountered."];
        }
            
        case errSecInvalidCertificateRef:
        {
            return [self errorWithCode:OSStatus message:@"An invalid certificate reference was encountered."];
        }
            
        case errSecInvalidCertificateGroup:
        {
            return [self errorWithCode:OSStatus message:@"An invalid certificate group was encountered."];
        }
            
        case errSecTagNotFound:
        {
            return [self errorWithCode:OSStatus message:@"The specified tag was not found."];
        }
            
        case errSecInvalidQuery:
        {
            return [self errorWithCode:OSStatus message:@"The specified query was not valid."];
        }
            
        case errSecInvalidValue:
        {
            return [self errorWithCode:OSStatus message:@"An invalid value was detected."];
        }
            
        case errSecCallbackFailed:
        {
            return [self errorWithCode:OSStatus message:@"A callback has failed."];
        }
            
        case errSecACLDeleteFailed:
        {
            return [self errorWithCode:OSStatus message:@"An ACL delete operation has failed."];
        }
            
        case errSecACLReplaceFailed:
        {
            return [self errorWithCode:OSStatus message:@"An ACL replace operation has failed."];
        }
            
        case errSecACLAddFailed:
        {
            return [self errorWithCode:OSStatus message:@"An ACL add operation has failed."];
        }
            
        case errSecACLChangeFailed:
        {
            return [self errorWithCode:OSStatus message:@"An ACL change operation has failed."];
        }
            
        case errSecInvalidAccessCredentials:
        {
            return [self errorWithCode:OSStatus message:@"Invalid access credentials were encountered."];
        }
            
        case errSecInvalidRecord:
        {
            return [self errorWithCode:OSStatus message:@"An invalid record was encountered."];
        }
            
        case errSecInvalidACL:
        {
            return [self errorWithCode:OSStatus message:@"An invalid ACL was encountered."];
        }
            
        case errSecInvalidSampleValue:
        {
            return [self errorWithCode:OSStatus message:@"An invalid sample value was encountered."];
        }
            
        case errSecIncompatibleVersion:
        {
            return [self errorWithCode:OSStatus message:@"An incompatible version was encountered."];
        }
            
        case errSecPrivilegeNotGranted:
        {
            return [self errorWithCode:OSStatus message:@"The privilege was not granted."];
        }
            
        case errSecInvalidScope:
        {
            return [self errorWithCode:OSStatus message:@"An invalid scope was encountered."];
        }
            
        case errSecPVCAlreadyConfigured:
        {
            return [self errorWithCode:OSStatus message:@"The PVC is already configured."];
        }
            
        case errSecInvalidPVC:
        {
            return [self errorWithCode:OSStatus message:@"An invalid PVC was encountered."];
        }
            
        case errSecEMMLoadFailed:
        {
            return [self errorWithCode:OSStatus message:@"The EMM load has failed."];
        }
            
        case errSecEMMUnloadFailed:
        {
            return [self errorWithCode:OSStatus message:@"The EMM unload has failed."];
        }
            
        case errSecAddinLoadFailed:
        {
            return [self errorWithCode:OSStatus message:@"The add-in load operation has failed."];
        }
            
        case errSecInvalidKeyRef:
        {
            return [self errorWithCode:OSStatus message:@"An invalid key was encountered."];
        }
            
        case errSecInvalidKeyHierarchy:
        {
            return [self errorWithCode:OSStatus message:@"An invalid key hierarchy was encountered."];
        }
            
        case errSecAddinUnloadFailed:
        {
            return [self errorWithCode:OSStatus message:@"The add-in unload operation has failed."];
        }
            
        case errSecLibraryReferenceNotFound:
        {
            return [self errorWithCode:OSStatus message:@"A library reference was not found."];
        }
            
        case errSecInvalidAddinFunctionTable:
        {
            return [self errorWithCode:OSStatus message:@"An invalid add-in function table was encountered."];
        }
            
        case errSecInvalidServiceMask:
        {
            return [self errorWithCode:OSStatus message:@"An invalid service mask was encountered."];
        }
            
        case errSecModuleNotLoaded:
        {
            return [self errorWithCode:OSStatus message:@"A module was not loaded."];
        }
            
        case errSecInvalidSubServiceID:
        {
            return [self errorWithCode:OSStatus message:@"An invalid subservice ID was encountered."];
        }
            
        case errSecAttributeNotInContext:
        {
            return [self errorWithCode:OSStatus message:@"An attribute was not in the context."];
        }
            
        case errSecModuleManagerInitializeFailed:
        {
            return [self errorWithCode:OSStatus message:@"A module failed to initialize."];
        }
            
        case errSecModuleManagerNotFound:
        {
            return [self errorWithCode:OSStatus message:@"A module was not found."];
        }
            
        case errSecEventNotificationCallbackNotFound:
        {
            return [self errorWithCode:OSStatus message:@"An event notification callback was not found."];
        }
            
        case errSecInputLengthError:
        {
            return [self errorWithCode:OSStatus message:@"An input length error was encountered."];
        }
            
        case errSecOutputLengthError:
        {
            return [self errorWithCode:OSStatus message:@"An output length error was encountered."];
        }
            
        case errSecPrivilegeNotSupported:
        {
            return [self errorWithCode:OSStatus message:@"The privilege is not supported."];
        }
            
        case errSecDeviceError:
        {
            return [self errorWithCode:OSStatus message:@"A device error was encountered."];
        }
            
        case errSecAttachHandleBusy:
        {
            return [self errorWithCode:OSStatus message:@"The CSP handle was busy."];
        }
            
        case errSecNotLoggedIn:
        {
            return [self errorWithCode:OSStatus message:@"You are not logged in."];
        }
            
        case errSecAlgorithmMismatch:
        {
            return [self errorWithCode:OSStatus message:@"An algorithm mismatch was encountered."];
        }
            
        case errSecKeyUsageIncorrect:
        {
            return [self errorWithCode:OSStatus message:@"The key usage is incorrect."];
        }
            
        case errSecKeyBlobTypeIncorrect:
        {
            return [self errorWithCode:OSStatus message:@"The key blob type is incorrect."];
        }
            
        case errSecKeyHeaderInconsistent:
        {
            return [self errorWithCode:OSStatus message:@"The key header is inconsistent."];
        }
            
        case errSecUnsupportedKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"The key header format is not supported."];
        }
            
        case errSecUnsupportedKeySize:
        {
            return [self errorWithCode:OSStatus message:@"The key size is not supported."];
        }
            
        case errSecInvalidKeyUsageMask:
        {
            return [self errorWithCode:OSStatus message:@"The key usage mask is not valid."];
        }
            
        case errSecUnsupportedKeyUsageMask:
        {
            return [self errorWithCode:OSStatus message:@"The key usage mask is not supported."];
        }
            
        case errSecInvalidKeyAttributeMask:
        {
            return [self errorWithCode:OSStatus message:@"The key attribute mask is not valid."];
        }
            
        case errSecUnsupportedKeyAttributeMask:
        {
            return [self errorWithCode:OSStatus message:@"The key attribute mask is not supported."];
        }
            
        case errSecInvalidKeyLabel:
        {
            return [self errorWithCode:OSStatus message:@"The key label is not valid."];
        }
            
        case errSecUnsupportedKeyLabel:
        {
            return [self errorWithCode:OSStatus message:@"The key label is not supported."];
        }
            
        case errSecInvalidKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"The key format is not valid."];
        }
            
        case errSecUnsupportedVectorOfBuffers:
        {
            return [self errorWithCode:OSStatus message:@"The vector of buffers is not supported."];
        }
            
        case errSecInvalidInputVector:
        {
            return [self errorWithCode:OSStatus message:@"The input vector is not valid."];
        }
            
        case errSecInvalidOutputVector:
        {
            return [self errorWithCode:OSStatus message:@"The output vector is not valid."];
        }
            
        case errSecInvalidContext:
        {
            return [self errorWithCode:OSStatus message:@"An invalid context was encountered."];
        }
            
        case errSecInvalidAlgorithm:
        {
            return [self errorWithCode:OSStatus message:@"An invalid algorithm was encountered."];
        }
            
        case errSecInvalidAttributeKey:
        {
            return [self errorWithCode:OSStatus message:@"A key attribute was not valid."];
        }
            
        case errSecMissingAttributeKey:
        {
            return [self errorWithCode:OSStatus message:@"A key attribute was missing."];
        }
            
        case errSecInvalidAttributeInitVector:
        {
            return [self errorWithCode:OSStatus message:@"An init vector attribute was not valid."];
        }
            
        case errSecMissingAttributeInitVector:
        {
            return [self errorWithCode:OSStatus message:@"An init vector attribute was missing."];
        }
            
        case errSecInvalidAttributeSalt:
        {
            return [self errorWithCode:OSStatus message:@"A salt attribute was not valid."];
        }
            
        case errSecMissingAttributeSalt:
        {
            return [self errorWithCode:OSStatus message:@"A salt attribute was missing."];
        }
            
        case errSecInvalidAttributePadding:
        {
            return [self errorWithCode:OSStatus message:@"A padding attribute was not valid."];
        }
            
        case errSecMissingAttributePadding:
        {
            return [self errorWithCode:OSStatus message:@"A padding attribute was missing."];
        }
            
        case errSecInvalidAttributeRandom:
        {
            return [self errorWithCode:OSStatus message:@"A random number attribute was not valid."];
        }
            
        case errSecMissingAttributeRandom:
        {
            return [self errorWithCode:OSStatus message:@"A random number attribute was missing."];
        }
            
        case errSecInvalidAttributeSeed:
        {
            return [self errorWithCode:OSStatus message:@"A seed attribute was not valid."];
        }
            
        case errSecMissingAttributeSeed:
        {
            return [self errorWithCode:OSStatus message:@"A seed attribute was missing."];
        }
            
        case errSecInvalidAttributePassphrase:
        {
            return [self errorWithCode:OSStatus message:@"A passphrase attribute was not valid."];
        }
            
        case errSecMissingAttributePassphrase:
        {
            return [self errorWithCode:OSStatus message:@"A passphrase attribute was missing."];
        }
            
        case errSecInvalidAttributeKeyLength:
        {
            return [self errorWithCode:OSStatus message:@"A key length attribute was not valid."];
        }
            
        case errSecMissingAttributeKeyLength:
        {
            return [self errorWithCode:OSStatus message:@"A key length attribute was missing."];
        }
            
        case errSecInvalidAttributeBlockSize:
        {
            return [self errorWithCode:OSStatus message:@"A block size attribute was not valid."];
        }
            
        case errSecMissingAttributeBlockSize:
        {
            return [self errorWithCode:OSStatus message:@"A block size attribute was missing."];
        }
            
        case errSecInvalidAttributeOutputSize:
        {
            return [self errorWithCode:OSStatus message:@"An output size attribute was not valid."];
        }
            
        case errSecMissingAttributeOutputSize:
        {
            return [self errorWithCode:OSStatus message:@"An output size attribute was missing."];
        }
            
        case errSecInvalidAttributeRounds:
        {
            return [self errorWithCode:OSStatus message:@"The number of rounds attribute was not valid."];
        }
            
        case errSecMissingAttributeRounds:
        {
            return [self errorWithCode:OSStatus message:@"The number of rounds attribute was missing."];
        }
            
        case errSecInvalidAlgorithmParms:
        {
            return [self errorWithCode:OSStatus message:@"An algorithm parameters attribute was not valid."];
        }
            
        case errSecMissingAlgorithmParms:
        {
            return [self errorWithCode:OSStatus message:@"An algorithm parameters attribute was missing."];
        }
            
        case errSecInvalidAttributeLabel:
        {
            return [self errorWithCode:OSStatus message:@"A label attribute was not valid."];
        }
            
        case errSecMissingAttributeLabel:
        {
            return [self errorWithCode:OSStatus message:@"A label attribute was missing."];
        }
            
        case errSecInvalidAttributeKeyType:
        {
            return [self errorWithCode:OSStatus message:@"A key type attribute was not valid."];
        }
            
        case errSecMissingAttributeKeyType:
        {
            return [self errorWithCode:OSStatus message:@"A key type attribute was missing."];
        }
            
        case errSecInvalidAttributeMode:
        {
            return [self errorWithCode:OSStatus message:@"A mode attribute was not valid."];
        }
            
        case errSecMissingAttributeMode:
        {
            return [self errorWithCode:OSStatus message:@"A mode attribute was missing."];
        }
            
        case errSecInvalidAttributeEffectiveBits:
        {
            return [self errorWithCode:OSStatus message:@"An effective bits attribute was not valid."];
        }
            
        case errSecMissingAttributeEffectiveBits:
        {
            return [self errorWithCode:OSStatus message:@"An effective bits attribute was missing."];
        }
            
        case errSecInvalidAttributeStartDate:
        {
            return [self errorWithCode:OSStatus message:@"A start date attribute was not valid."];
        }
            
        case errSecMissingAttributeStartDate:
        {
            return [self errorWithCode:OSStatus message:@"A start date attribute was missing."];
        }
            
        case errSecInvalidAttributeEndDate:
        {
            return [self errorWithCode:OSStatus message:@"An end date attribute was not valid."];
        }
            
        case errSecMissingAttributeEndDate:
        {
            return [self errorWithCode:OSStatus message:@"An end date attribute was missing."];
        }
            
        case errSecInvalidAttributeVersion:
        {
            return [self errorWithCode:OSStatus message:@"A version attribute was not valid."];
        }
            
        case errSecMissingAttributeVersion:
        {
            return [self errorWithCode:OSStatus message:@"A version attribute was missing."];
        }
            
        case errSecInvalidAttributePrime:
        {
            return [self errorWithCode:OSStatus message:@"A prime attribute was not valid."];
        }
            
        case errSecMissingAttributePrime:
        {
            return [self errorWithCode:OSStatus message:@"A prime attribute was missing."];
        }
            
        case errSecInvalidAttributeBase:
        {
            return [self errorWithCode:OSStatus message:@"A base attribute was not valid."];
        }
            
        case errSecMissingAttributeBase:
        {
            return [self errorWithCode:OSStatus message:@"A base attribute was missing."];
        }
            
        case errSecInvalidAttributeSubprime:
        {
            return [self errorWithCode:OSStatus message:@"A subprime attribute was not valid."];
        }
            
        case errSecMissingAttributeSubprime:
        {
            return [self errorWithCode:OSStatus message:@"A subprime attribute was missing."];
        }
            
        case errSecInvalidAttributeIterationCount:
        {
            return [self errorWithCode:OSStatus message:@"An iteration count attribute was not valid."];
        }
            
        case errSecMissingAttributeIterationCount:
        {
            return [self errorWithCode:OSStatus message:@"An iteration count attribute was missing."];
        }
            
        case errSecInvalidAttributeDLDBHandle:
        {
            return [self errorWithCode:OSStatus message:@"A database handle attribute was not valid."];
        }
            
        case errSecMissingAttributeDLDBHandle:
        {
            return [self errorWithCode:OSStatus message:@"A database handle attribute was missing."];
        }
            
        case errSecInvalidAttributeAccessCredentials:
        {
            return [self errorWithCode:OSStatus message:@"An access credentials attribute was not valid."];
        }
            
        case errSecMissingAttributeAccessCredentials:
        {
            return [self errorWithCode:OSStatus message:@"An access credentials attribute was missing."];
        }
            
        case errSecInvalidAttributePublicKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A public key format attribute was not valid."];
        }
            
        case errSecMissingAttributePublicKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A public key format attribute was missing."];
        }
            
        case errSecInvalidAttributePrivateKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A private key format attribute was not valid."];
        }
            
        case errSecMissingAttributePrivateKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A private key format attribute was missing."];
        }
            
        case errSecInvalidAttributeSymmetricKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A symmetric key format attribute was not valid."];
        }
            
        case errSecMissingAttributeSymmetricKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A symmetric key format attribute was missing."];
        }
            
        case errSecInvalidAttributeWrappedKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A wrapped key format attribute was not valid."];
        }
            
        case errSecMissingAttributeWrappedKeyFormat:
        {
            return [self errorWithCode:OSStatus message:@"A wrapped key format attribute was missing."];
        }
            
        case errSecStagedOperationInProgress:
        {
            return [self errorWithCode:OSStatus message:@"A staged operation is in progress."];
        }
            
        case errSecStagedOperationNotStarted:
        {
            return [self errorWithCode:OSStatus message:@"A staged operation was not started."];
        }
            
        case errSecVerifyFailed:
        {
            return [self errorWithCode:OSStatus message:@"A cryptographic verification failure has occurred."];
        }
            
        case errSecQuerySizeUnknown:
        {
            return [self errorWithCode:OSStatus message:@"The query size is unknown."];
        }
            
        case errSecBlockSizeMismatch:
        {
            return [self errorWithCode:OSStatus message:@"A block size mismatch occurred."];
        }
            
        case errSecPublicKeyInconsistent:
        {
            return [self errorWithCode:OSStatus message:@"The public key was inconsistent."];
        }
            
        case errSecDeviceVerifyFailed:
        {
            return [self errorWithCode:OSStatus message:@"A device verification failure has occurred."];
        }
            
        case errSecInvalidLoginName:
        {
            return [self errorWithCode:OSStatus message:@"An invalid login name was detected."];
        }
            
        case errSecAlreadyLoggedIn:
        {
            return [self errorWithCode:OSStatus message:@"The user is already logged in."];
        }
            
        case errSecInvalidDigestAlgorithm:
        {
            return [self errorWithCode:OSStatus message:@"An invalid digest algorithm was detected."];
        }
            
        case errSecInvalidCRLGroup:
        {
            return [self errorWithCode:OSStatus message:@"An invalid CRL group was detected."];
        }
            
        case errSecCertificateCannotOperate:
        {
            return [self errorWithCode:OSStatus message:@"The certificate cannot operate."];
        }
            
        case errSecCertificateExpired:
        {
            return [self errorWithCode:OSStatus message:@"An expired certificate was detected."];
        }
            
        case errSecCertificateNotValidYet:
        {
            return [self errorWithCode:OSStatus message:@"The certificate is not yet valid."];
        }
            
        case errSecCertificateRevoked:
        {
            return [self errorWithCode:OSStatus message:@"The certificate was revoked."];
        }
            
        case errSecCertificateSuspended:
        {
            return [self errorWithCode:OSStatus message:@"The certificate was suspended."];
        }
            
        case errSecInsufficientCredentials:
        {
            return [self errorWithCode:OSStatus message:@"Insufficient credentials were detected."];
        }
            
        case errSecInvalidAction:
        {
            return [self errorWithCode:OSStatus message:@"The action was not valid."];
        }
            
        case errSecInvalidAuthority:
        {
            return [self errorWithCode:OSStatus message:@"The authority was not valid."];
        }
            
        case errSecVerifyActionFailed:
        {
            return [self errorWithCode:OSStatus message:@"A verify action has failed."];
        }
            
        case errSecInvalidCertAuthority:
        {
            return [self errorWithCode:OSStatus message:@"The certificate authority was not valid."];
        }
            
        case errSecInvaldCRLAuthority:
        {
            return [self errorWithCode:OSStatus message:@"The CRL authority was not valid."];
        }
            
        case errSecInvalidCRLEncoding:
        {
            return [self errorWithCode:OSStatus message:@"The CRL encoding was not valid."];
        }
            
        case errSecInvalidCRLType:
        {
            return [self errorWithCode:OSStatus message:@"The CRL type was not valid."];
        }
            
        case errSecInvalidCRL:
        {
            return [self errorWithCode:OSStatus message:@"The CRL was not valid."];
        }
            
        case errSecInvalidFormType:
        {
            return [self errorWithCode:OSStatus message:@"The form type was not valid."];
        }
            
        case errSecInvalidID:
        {
            return [self errorWithCode:OSStatus message:@"The ID was not valid."];
        }
            
        case errSecInvalidIdentifier:
        {
            return [self errorWithCode:OSStatus message:@"The identifier was not valid."];
        }
            
        case errSecInvalidIndex:
        {
            return [self errorWithCode:OSStatus message:@"The index was not valid."];
        }
            
        case errSecInvalidPolicyIdentifiers:
        {
            return [self errorWithCode:OSStatus message:@"The policy identifiers are not valid."];
        }
            
        case errSecInvalidTimeString:
        {
            return [self errorWithCode:OSStatus message:@"The time specified was not valid."];
        }
            
        case errSecInvalidReason:
        {
            return [self errorWithCode:OSStatus message:@"The trust policy reason was not valid."];
        }
            
        case errSecInvalidRequestInputs:
        {
            return [self errorWithCode:OSStatus message:@"The request inputs are not valid."];
        }
            
        case errSecInvalidResponseVector:
        {
            return [self errorWithCode:OSStatus message:@"The response vector was not valid."];
        }
            
        case errSecInvalidStopOnPolicy:
        {
            return [self errorWithCode:OSStatus message:@"The stop-on policy was not valid."];
        }
            
        case errSecInvalidTuple:
        {
            return [self errorWithCode:OSStatus message:@"The tuple was not valid."];
        }
            
        case errSecMultipleValuesUnsupported:
        {
            return [self errorWithCode:OSStatus message:@"Multiple values are not supported."];
        }
            
        case errSecNotTrusted:
        {
            return [self errorWithCode:OSStatus message:@"The trust policy was not trusted."];
        }
            
        case errSecNoDefaultAuthority:
        {
            return [self errorWithCode:OSStatus message:@"No default authority was detected."];
        }
            
        case errSecRejectedForm:
        {
            return [self errorWithCode:OSStatus message:@"The trust policy had a rejected form."];
        }
            
        case errSecRequestLost:
        {
            return [self errorWithCode:OSStatus message:@"The request was lost."];
        }
            
        case errSecRequestRejected:
        {
            return [self errorWithCode:OSStatus message:@"The request was rejected."];
        }
            
        case errSecUnsupportedAddressType:
        {
            return [self errorWithCode:OSStatus message:@"The address type is not supported."];
        }
            
        case errSecUnsupportedService:
        {
            return [self errorWithCode:OSStatus message:@"The service is not supported."];
        }
            
        case errSecInvalidTupleGroup:
        {
            return [self errorWithCode:OSStatus message:@"The tuple group was not valid."];
        }
            
        case errSecInvalidBaseACLs:
        {
            return [self errorWithCode:OSStatus message:@"The base ACLs are not valid."];
        }
            
        case errSecInvalidTupleCredendtials:
        {
            return [self errorWithCode:OSStatus message:@"The tuple credentials are not valid."];
        }
            
        case errSecInvalidEncoding:
        {
            return [self errorWithCode:OSStatus message:@"The encoding was not valid."];
        }
            
        case errSecInvalidValidityPeriod:
        {
            return [self errorWithCode:OSStatus message:@"The validity period was not valid."];
        }
            
        case errSecInvalidRequestor:
        {
            return [self errorWithCode:OSStatus message:@"The requestor was not valid."];
        }
            
        case errSecRequestDescriptor:
        {
            return [self errorWithCode:OSStatus message:@"The request descriptor was not valid."];
        }
            
        case errSecInvalidBundleInfo:
        {
            return [self errorWithCode:OSStatus message:@"The bundle information was not valid."];
        }
            
        case errSecInvalidCRLIndex:
        {
            return [self errorWithCode:OSStatus message:@"The CRL index was not valid."];
        }
            
        case errSecNoFieldValues:
        {
            return [self errorWithCode:OSStatus message:@"No field values were detected."];
        }
            
        case errSecUnsupportedFieldFormat:
        {
            return [self errorWithCode:OSStatus message:@"The field format is not supported."];
        }
            
        case errSecUnsupportedIndexInfo:
        {
            return [self errorWithCode:OSStatus message:@"The index information is not supported."];
        }
            
        case errSecUnsupportedLocality:
        {
            return [self errorWithCode:OSStatus message:@"The locality is not supported."];
        }
            
        case errSecUnsupportedNumAttributes:
        {
            return [self errorWithCode:OSStatus message:@"The number of attributes is not supported."];
        }
            
        case errSecUnsupportedNumIndexes:
        {
            return [self errorWithCode:OSStatus message:@"The number of indexes is not supported."];
        }
            
        case errSecUnsupportedNumRecordTypes:
        {
            return [self errorWithCode:OSStatus message:@"The number of record types is not supported."];
        }
            
        case errSecFieldSpecifiedMultiple:
        {
            return [self errorWithCode:OSStatus message:@"Too many fields were specified."];
        }
            
        case errSecIncompatibleFieldFormat:
        {
            return [self errorWithCode:OSStatus message:@"The field format was incompatible."];
        }
            
        case errSecInvalidParsingModule:
        {
            return [self errorWithCode:OSStatus message:@"The parsing module was not valid."];
        }
            
        case errSecDatabaseLocked:
        {
            return [self errorWithCode:OSStatus message:@"The database is locked."];
        }
            
        case errSecDatastoreIsOpen:
        {
            return [self errorWithCode:OSStatus message:@"The data store is open."];
        }
            
        case errSecMissingValue:
        {
            return [self errorWithCode:OSStatus message:@"A missing value was detected."];
        }
            
        case errSecUnsupportedQueryLimits:
        {
            return [self errorWithCode:OSStatus message:@"The query limits are not supported."];
        }
            
        case errSecUnsupportedNumSelectionPreds:
        {
            return [self errorWithCode:OSStatus message:@"The number of selection predicates is not supported."];
        }
            
        case errSecUnsupportedOperator:
        {
            return [self errorWithCode:OSStatus message:@"The operator is not supported."];
        }
            
        case errSecInvalidDBLocation:
        {
            return [self errorWithCode:OSStatus message:@"The database location is not valid."];
        }
            
        case errSecInvalidAccessRequest:
        {
            return [self errorWithCode:OSStatus message:@"The access request is not valid."];
        }
            
        case errSecInvalidIndexInfo:
        {
            return [self errorWithCode:OSStatus message:@"The index information is not valid."];
        }
            
        case errSecInvalidNewOwner:
        {
            return [self errorWithCode:OSStatus message:@"The new owner is not valid."];
        }
            
        case errSecInvalidModifyMode:
        {
            return [self errorWithCode:OSStatus message:@"The modify mode is not valid."];
        }
            
        case errSecMissingRequiredExtension:
        {
            return [self errorWithCode:OSStatus message:@"A required certificate extension is missing."];
        }
            
        case errSecExtendedKeyUsageNotCritical:
        {
            return [self errorWithCode:OSStatus message:@"The extended key usage extension was not marked critical."];
        }
            
        case errSecTimestampMissing:
        {
            return [self errorWithCode:OSStatus message:@"A timestamp was expected but was not found."];
        }
            
        case errSecTimestampInvalid:
        {
            return [self errorWithCode:OSStatus message:@"The timestamp was not valid."];
        }
            
        case errSecTimestampNotTrusted:
        {
            return [self errorWithCode:OSStatus message:@"The timestamp was not trusted."];
        }
            
        case errSecTimestampServiceNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"The timestamp service is not available."];
        }
            
        case errSecTimestampBadAlg:
        {
            return [self errorWithCode:OSStatus message:@"An unrecognized or unsupported Algorithm Identifier in timestamp."];
        }
            
        case errSecTimestampBadRequest:
        {
            return [self errorWithCode:OSStatus message:@"The timestamp transaction is not permitted or supported."];
        }
            
        case errSecTimestampBadDataFormat:
        {
            return [self errorWithCode:OSStatus message:@"The timestamp data submitted has the wrong format."];
        }
            
        case errSecTimestampTimeNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"The time source for the Timestamp Authority is not available."];
        }
            
        case errSecTimestampUnacceptedPolicy:
        {
            return [self errorWithCode:OSStatus message:@"The requested policy is not supported by the Timestamp Authority."];
        }
            
        case errSecTimestampUnacceptedExtension:
        {
            return [self errorWithCode:OSStatus message:@"The requested extension is not supported by the Timestamp Authority."];
        }
            
        case errSecTimestampAddInfoNotAvailable:
        {
            return [self errorWithCode:OSStatus message:@"The additional information requested is not available."];
        }
            
        case errSecTimestampSystemFailure:
        {
            return [self errorWithCode:OSStatus message:@"The timestamp request cannot be handled due to system failure."];
        }
            
        case errSecSigningTimeMissing:
        {
            return [self errorWithCode:OSStatus message:@"A signing time was expected but was not found."];
        }
            
        case errSecTimestampRejection:
        {
            return [self errorWithCode:OSStatus message:@"A timestamp transaction was rejected."];
        }
            
        case errSecTimestampWaiting:
        {
            return [self errorWithCode:OSStatus message:@"A timestamp transaction is waiting."];
        }
            
        case errSecTimestampRevocationWarning:
        {
            return [self errorWithCode:OSStatus message:@"A timestamp authority revocation warning was issued."];
        }
            
        case errSecTimestampRevocationNotification:
        {
            return [self errorWithCode:OSStatus message:@"A timestamp authority revocation notification was issued."];
        }
            
    }
}

@end
