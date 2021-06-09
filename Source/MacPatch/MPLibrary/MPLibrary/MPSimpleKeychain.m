//
//  MPSimpleKeychain.m
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "MPSimpleKeychain.h"
#import "MPKeyItem.h"
#import "MPPassItem.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <sys/types.h>
#include <sys/sysctl.h>

#define ACCESS_LABEL    @"MPSimpleKeychainAccess"
#define ACCOUNT_LABEL   @"MacPatch-Service"

@interface MPSimpleKeychain () {
    SecKeychainRef xKeychain;
    NSString *keyChainFile;
}

@property (nonatomic) ServiceType type;

- (BOOL)keychainIsUnlocked;
- (NSDictionary *)serviceTypeNames;
- (NSString *)nameForServiceType:(ServiceType)aService;
- (SecAccessRef)createAccessRefWithLabel:(NSString *)label error:(NSError **)err;

- (NSString *)clientInfo;
- (NSString *)md5HexDigest:(NSString*)input;
- (NSString *)sha1HexDigest:(NSString*)input;
- (NSString *)clientUUID;
- (NSString *)modelInfo;

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message;
@end

@implementation MPSimpleKeychain

- (id)initWithKeychainFile:(NSString *)aKeyChainFile
{
    self = [super init];
    if (self)
    {
        if ([[NSFileManager defaultManager] fileExistsAtPath:aKeyChainFile]) {
            keyChainFile = [aKeyChainFile copy];
            OSStatus unlockResult = [self unlockKeyChain:aKeyChainFile];
            if (unlockResult != noErr) {
                NSLog(@"Unlock Keychain error: %d",unlockResult);
                return nil;
            }
        } else {
            keyChainFile = [aKeyChainFile copy];
        }
    }
    return self;
}

- (OSStatus)createKeyChain:(NSString *)aKeyChainFile
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:aKeyChainFile]) {
        return errSecDuplicateKeychain;
    }

    const char *path = [aKeyChainFile UTF8String];
    const char *pass = [[self clientInfo] UTF8String];
    
    OSStatus result = SecKeychainCreate(path,
                                     (UInt32) strlen(pass),
                                     pass,
                                     NO,
                                     NULL,
                                     &xKeychain);
    
    return result;
}

- (OSStatus)unlockKeyChain:(NSString *)aKeyChainFile
{
    const char *path = [aKeyChainFile UTF8String];
    const char *pass = [[self clientInfo] UTF8String];
    SecKeychainOpen(path, &xKeychain);
    OSStatus unlockResult = SecKeychainUnlock(xKeychain, (UInt32) strlen(pass), pass, TRUE);
	NSLog(@"unlockResult: %d",(int)unlockResult);
    return unlockResult;
}

- (OSStatus)lockKeyChain:(NSString *)aKeyChainFile
{
    return SecKeychainLock(xKeychain);
}

- (OSStatus)deleteKeyChain
{
    OSStatus result = SecKeychainDelete(xKeychain);
    CFRelease(xKeychain);
    return result;
}

#pragma mark - MacPatch

- (BOOL)saveKeyItemWithService:(MPKeyItem *)aPasswordObj service:(ServiceType)aService error:(NSError **)error
{
    NSString *accountName = [self nameForServiceType:aService];
    return [self saveKeyItemWithServiceAndAccount:aPasswordObj service:aService account:accountName error:error];
}

- (BOOL)saveKeyItemWithServiceAndAccount:(MPKeyItem *)aPasswordObj service:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error
{
    if (![self keychainIsUnlocked]) {
        if (![self unlockKeyChain:keyChainFile]) {
            return NO;
        }
    }
    
    NSData *passData = [NSKeyedArchiver archivedDataWithRootObject:[aPasswordObj toDictionary]];
    
    // setup keychain storage properties
    SecAccessRef kAccess = [self createAccessRefWithLabel:ACCESS_LABEL error:NULL];
    NSDictionary *storageQuery = @{
                                   (__bridge id)kSecAttrAccount:    [self nameForServiceType:aService],
                                   (__bridge id)kSecAttrService:    aAccount,
                                   (__bridge id)kSecValueData:      passData,
                                   (__bridge id)kSecClass:          (__bridge id)kSecClassGenericPassword,
								   (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly,
                                   (__bridge id)kSecUseKeychain:    (__bridge id)xKeychain,
                                   (__bridge id)kSecAttrAccess:     (__bridge id)kAccess,
                                   };
    
    OSStatus osStatus = SecItemAdd((__bridge CFDictionaryRef)storageQuery, nil);
    if(osStatus != noErr) {
        if (error != NULL) {
            *error = [self errorForOSStatus:osStatus];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)savePassItemWithService:(MPPassItem *)aPasswordObj service:(NSString *)aService error:(NSError **)error
{
	@try
	{
        if ([[NSFileManager defaultManager] fileExistsAtPath:keyChainFile]) {
            if (![self keychainIsUnlocked]) {
                if (![self unlockKeyChain:keyChainFile]) {
                    NSLog(@"Keychain is locked, error trying to unlock it.");
                    return NO;
                }
            }
        }
		
		NSData *passData = [NSKeyedArchiver archivedDataWithRootObject:[aPasswordObj toDictionary]];
		
		// setup keychain storage properties
		NSError *err = nil;
		SecAccessRef kAccess = [self createAccessRefWithLabel:ACCESS_LABEL error:&err];
		if (err) {
			NSLog(@"%@",err.localizedDescription);
			return false;
		}
       
        NSParameterAssert((__bridge id)kSecClassGenericPassword);
        NSParameterAssert(aService);
        NSParameterAssert(aService);
        NSParameterAssert(passData);
        NSParameterAssert((__bridge id)xKeychain);
        NSParameterAssert((__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly);
        NSParameterAssert((__bridge id)kAccess);
        NSParameterAssert((__bridge id)kCFBooleanFalse);
    
        NSDictionary *storageQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService:           aService,
            (__bridge id)kSecAttrAccount:           aService,
            (__bridge id)kSecValueData:             passData,
            (__bridge id)kSecUseKeychain:           (__bridge id)xKeychain,
            (__bridge id)kSecAttrAccessible:        (__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly,
            (__bridge id)kSecAttrAccess:            (__bridge id)kAccess,
            (__bridge id)kSecAttrSynchronizable:    (__bridge id)kCFBooleanFalse
        };
        
		OSStatus osStatus = SecItemAdd((__bridge CFDictionaryRef)storageQuery, NULL);
		if(osStatus != noErr) {
			if (error != NULL) {
				*error = [self errorForOSStatus:osStatus];
			}
			return NO;
		}
		
		return YES;
	} @catch (NSException *exception) {
		NSLog(@"%@",exception);
		return NO;
	}
}

- (MPKeyItem *)retrieveKeyItemForService:(ServiceType)aService error:(NSError **)error
{
    NSString *accountName = [self nameForServiceType:aService];
    return [self retrieveKeyItemForServiceAndAccount:aService account:accountName error:error];
}

- (MPKeyItem *)retrieveKeyItemForServiceAndAccount:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error
{
    return [self retrieveKeyItemForServiceAndAccountWithKeychainItem:aService account:aAccount keychainItem:NULL error:error];
}

- (MPKeyItem *)retrieveKeyItemForServiceAndAccountWithKeychainItem:(ServiceType)aService account:(NSString *)aAccount keychainItem:(SecKeychainItemRef *)item error:(NSError **)error
{
    if (![self keychainIsUnlocked]) {
        if (![self unlockKeyChain:keyChainFile]) {
            return nil;
        }
    }
    
    const char *serviceUTF8  = [[self nameForServiceType:aService] UTF8String];
    const char *accountUTF8  = [aAccount UTF8String];
    char *passwordData;
    UInt32 passwordLength;
    
    OSStatus status = SecKeychainFindGenericPassword(xKeychain,
                                                     (UInt32)strlen(serviceUTF8),
                                                     serviceUTF8,
                                                     (UInt32)strlen(accountUTF8),
                                                     accountUTF8,
                                                     &passwordLength,
                                                     (void **)&passwordData,
                                                     item);
    
    if (status != noErr) {
        if (error != NULL) {
            *error = [self errorForOSStatus:status];
        }
        return nil;
    }
    
    NSData *data = [[NSData alloc] initWithBytesNoCopy:passwordData length:passwordLength];
    NSDictionary *storedDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    MPKeyItem *ki = [[MPKeyItem alloc] initWithDictionary:storedDictionary];
    return ki;
}

- (MPPassItem *)retrievePassItemForService:(NSString *)aService error:(NSError **)error
{
    if (![self keychainIsUnlocked]) {
        if (![self unlockKeyChain:keyChainFile]) {
            return nil;
        }
    }
    
    const char *serviceUTF8  = [aService UTF8String];
    const char *accountUTF8  = [aService UTF8String];
    char *passwordData;
    UInt32 passwordLength;
    
    OSStatus status = SecKeychainFindGenericPassword(xKeychain,
                                                     (UInt32)strlen(serviceUTF8),
                                                     serviceUTF8,
                                                     (UInt32)strlen(accountUTF8),
                                                     accountUTF8,
                                                     &passwordLength,
                                                     (void **)&passwordData,
                                                     NULL);
    
    if (status != noErr) {
        if (error != NULL) {
            *error = [self errorForOSStatus:status];
        }
        return nil;
    }
    
    NSData *data = [[NSData alloc] initWithBytesNoCopy:passwordData length:passwordLength];
    NSDictionary *storedDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    MPPassItem *pi = [[MPPassItem alloc] initWithDictionary:storedDictionary];
    return pi;
}

- (BOOL)updateKeyItemWithService:(MPKeyItem *)aPasswordObj service:(ServiceType)aService error:(NSError **)error
{
    NSString *accountName = [self nameForServiceType:aService];
    return [self updateKeyItemWithServiceAndAccount:aPasswordObj service:aService account:accountName error:error];
}

- (BOOL)updateKeyItemWithServiceAndAccount:(MPKeyItem *)aPasswordObj service:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error
{
    if (![self keychainIsUnlocked]) {
        if (![self unlockKeyChain:keyChainFile]) {
            return NO;
        }
    }
    
    NSError *err = nil;
    BOOL delItem = [self deleteKeyItemWithServiceAndAccount:aService account:aAccount error:&err];
    if (err) {
        if (error != NULL) *error = err;
        return NO;
    }
    
    err = nil;
    if (delItem == YES) {
        BOOL saveItem = [self saveKeyItemWithServiceAndAccount:aPasswordObj service:aService account:aAccount error:&err];
        if (err) {
            if (error != NULL) *error = err;
            return NO;
        }
        return saveItem;
    }
    
    return NO;
}

- (BOOL)updatePassItemForService:(MPPassItem *)aPasswordObj service:(NSString *)aService error:(NSError **)error
{
    if (![self keychainIsUnlocked]) {
        if (![self unlockKeyChain:keyChainFile]) {
            return NO;
        }
    }
    
    NSError *err = nil;
    BOOL delItem = [self deletePassItemforService:aService error:&err];
    if (err) {
        if (error != NULL) *error = err;
        return NO;
    }
    
    err = nil;
    if (delItem == YES) {
        BOOL saveItem = [self savePassItemWithService:aPasswordObj service:aService error:&err];
        if (err) {
            if (error != NULL) *error = err;
            return NO;
        }
        return saveItem;
    }
    
    return NO;
}

- (BOOL)deleteKeyItemWithService:(ServiceType)aService error:(NSError **)error
{
    NSString *accountName = [self nameForServiceType:aService];
    return [self deleteKeyItemWithServiceAndAccount:aService account:accountName error:error];
}

- (BOOL)deleteKeyItemWithServiceAndAccount:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error
{
    if (![self keychainIsUnlocked]) {
        if (![self unlockKeyChain:keyChainFile]) {
            return NO;
        }
    }
    
    NSError *err = nil;
    SecKeychainItemRef item = nil;
    MPKeyItem *keyItem = [self retrieveKeyItemForServiceAndAccountWithKeychainItem:aService account:aAccount keychainItem:&item error:&err];
    if (err) {
        if (error != NULL) *error = err;
        return NO;
    }
    
    OSStatus status;
    
    if (keyItem == nil || item == nil) {
        status = errSecItemNotFound;
    } else {
        status = SecKeychainItemDelete(item);
    }
    
    if (item != nil) CFRelease(item);
    
    if (status == noErr) {
        return YES;
    } else {
        if (error != NULL) *error = [self errorForOSStatus:status];
        return NO;
    }
}

- (BOOL)deletePassItemforService:(NSString *)aService error:(NSError **)error
{
    if (![self keychainIsUnlocked]) {
        if (![self unlockKeyChain:keyChainFile]) {
            return NO;
        }
    }
    
    NSError *err = nil;
    SecKeychainItemRef item = nil;
	MPPassItem *passItem = [self retrievePassItemForService:aService error:&err];
    if (err) {
        if (error != NULL) *error = err;
        return NO;
    }
    
    OSStatus status;
    
    if (passItem == nil || item == nil) {
        status = errSecItemNotFound;
    } else {
        status = SecKeychainItemDelete(item);
    }
    
    if (item != nil) CFRelease(item);
    
    if (status == noErr) {
        return YES;
    } else {
        if (error != NULL) *error = [self errorForOSStatus:status];
        return NO;
    }
}

#pragma mark - Private

- (BOOL)keychainIsUnlocked
{
    SecKeychainStatus keychainStatus;
    OSStatus err = SecKeychainGetStatus(xKeychain, &keychainStatus);
    
    if (err != errSecSuccess) {
        NSLog(@"Error getting Keychain status.");
        NSLog(@"OSStatus: %@",[self errorForOSStatus:err]);
        return NO;
    }
    
    return (keychainStatus & kSecUnlockStateStatus) ? YES : NO;
}

- (NSDictionary *)serviceTypeNames
{
    return @{@(kMPServerService) : [NSString stringWithFormat:@"Server (%@)",[self clientUUID]],
             @(kMPClientService) : [NSString stringWithFormat:@"Client (%@)",[self clientUUID]]};
}

- (NSString *)nameForServiceType:(ServiceType)aService
{
    return [self serviceTypeNames][@(aService)];
}

- (SecAccessRef)createAccessRefWithLabel:(NSString *)label error:(NSError **)err
{
    OSStatus result;
    SecTrustedApplicationRef me;
    SecTrustedApplicationRef MPAgent = NULL;
    SecTrustedApplicationRef MacPatchApp1 = NULL;
    SecTrustedApplicationRef MPClientStatus = NULL;
    SecTrustedApplicationRef MPLoginAgent = NULL;
    SecTrustedApplicationRef MPUpdateAgent = NULL;
	SecTrustedApplicationRef MPHelper = NULL;
    
    result = SecTrustedApplicationCreateFromPath(NULL, &me);
	result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/MPAgent", &MPAgent);
	result = SecTrustedApplicationCreateFromPath("/Applications/MacPatch.app", &MacPatchApp1);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/MPClientStatus.app", &MPClientStatus);
    result = SecTrustedApplicationCreateFromPath("/Library/PrivilegedHelperTools/MPLoginAgent.app", &MPLoginAgent);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Updater/MPUpdater", &MPUpdateAgent);
	result = SecTrustedApplicationCreateFromPath("/Library/PrivilegedHelperTools/gov.llnl.mp.helper", &MPHelper);
    
    NSArray *trustedApplications = @[(__bridge_transfer id)me,
									 (__bridge_transfer id)MPAgent,
									 (__bridge_transfer id)MacPatchApp1,
									 (__bridge_transfer id)MPClientStatus,
									 (__bridge_transfer id)MPLoginAgent,
									 (__bridge_transfer id)MPUpdateAgent,
									 (__bridge_transfer id)MPHelper];
    
    SecAccessRef accessObj = NULL;
    result = SecAccessCreate((__bridge CFStringRef)label, (__bridge CFArrayRef)trustedApplications, &accessObj);
    if (noErr != result) {
        if (err != NULL) *err = [self errorForOSStatus:result];
        return nil;
    }
    
    return accessObj;
}

#pragma mark Client Info
- (NSString *)clientInfo
{
    NSMutableString *client = [NSMutableString new];
    [client appendString:[self clientUUID]];
    [client appendFormat:@" %@",[self modelInfo]];
    return [self sha1HexDigest:client];
}

- (NSString *)md5HexDigest:(NSString*)input
{
    const char* str = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), digest);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%03x",digest[i]];
    }
    return ret;
}

- (NSString *)sha1HexDigest:(NSString*)input
{
    const char* str = [input UTF8String];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(str, (CC_LONG)strlen(str), digest);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_SHA1_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%03x",digest[i]];
    }
    return ret;
}

- (NSString *)clientUUID
{
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault,IOServiceMatching("IOPlatformExpertDevice"));
    CFTypeRef serialNumberAsCFString = IORegistryEntryCreateCFProperty(platformExpert,CFSTR(kIOPlatformUUIDKey),kCFAllocatorDefault, 0);
    IOObjectRelease(platformExpert);
    NSString __strong *serialNumber = (__bridge NSString *)(serialNumberAsCFString);
    CFRelease(serialNumberAsCFString);
    return serialNumber;
}

- (NSString *)modelInfo
{
    size_t size;
    sysctlbyname("machdep.cpu.brand_string", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("machdep.cpu.brand_string", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);
    return platform;
}

#pragma mark Error codes

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message
{
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: message};
    return [NSError errorWithDomain:@"MPSimpleKeychain" code:code userInfo:userInfo];
}

// Not Private
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
