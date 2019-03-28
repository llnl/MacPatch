//
//  MPKeychain.m
//  MPLibrary
//
//  Created by Heizer, Charles on 8/14/14.
//
//

#import "MPKeychain.h"
#include <stdlib.h>
#include <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>

#define ACCESS_LABEL @"MPClientKeychain"
#define DEFAULT_KEYCHAIN @"MacPatch.keychain"

@interface MPKeychain ()

- (NSString *)clientInfo;
- (NSString *)md5HexDigest:(NSString*)input;
- (NSString *)clientUUID;
- (NSString *)modelInfo;

- (OSStatus)keychainRefFromFile:(NSString *)aKeychainFilePath usingAccess:(SecAccessRef)aAccessRef;

- (SecAccessRef)createDefaultAccessRef:(NSError **)err;
- (SecAccessRef)createAccessRef:(NSError **)err;

- (OSStatus)deleteFromKeychainWithKey:(NSString *)aKey;

@property (nonatomic, strong) NSString *keyChainPath;

@end

@implementation MPKeychain

@synthesize keyChainPath = _keyChainPath;
@synthesize accessLabel = _accessLabel;
@synthesize error = _error;

- (id)init
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSSystemDomainMask, YES);
    [self setKeyChainPath:[[paths firstObject] stringByAppendingFormat:@"/MacPatch/%@",DEFAULT_KEYCHAIN]];
    return [self initWithKeychainFile:_keyChainPath accessLabel:ACCESS_LABEL];
}

- (id)initWithKeychainFile:(NSString *)aKeychain
{
    return [self initWithKeychainFile:aKeychain accessLabel:ACCESS_LABEL];
}

- (id)initWithKeychainFile:(NSString *)aKeychain accessLabel:(NSString *)aAccessLabel
{
    self = [super init];
    if (self)
    {
        self.error = nil;
        OSStatus res = noErr;
        res = [self keychainRefFromFile:aKeychain usingAccess:nil];
        self.overWriteKeyChainData = NO;
        if (noErr != res) {
            CFStringRef errMsg = SecCopyErrorMessageString(res, NULL);
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:(__bridge NSString *)errMsg forKey:NSLocalizedDescriptionKey];
            self.error = [NSError errorWithDomain:@"gov.llnl.mp.keychain" code:-1001 userInfo:userInfo];
            CFRelease(errMsg);
        }
        self.accessLabel = aAccessLabel;
    }
    return self;
}

- (OSStatus)keychainRefFromFile:(NSString *)aKeychainFilePath
{
    logit(lcl_vError,@"Does nothing");
    return noErr;
}

- (OSStatus)keychainRefFromFile:(NSString *)aKeychainFilePath usingAccess:(SecAccessRef)aAccessRef
{
    OSStatus result;
    const char *uuid = [[self clientInfo] UTF8String];
    NSFileManager *fm = [NSFileManager defaultManager];
    SecKeychainRef aKeychainItem;
    if (![fm fileExistsAtPath:aKeychainFilePath]) {
        result = SecKeychainCreate([aKeychainFilePath fileSystemRepresentation], (UInt32)strlen(uuid), uuid, FALSE, NULL, &aKeychainItem);
        keychainItem = aKeychainItem;
    } else {
        /*
        result = SecKeychainSetUserInteractionAllowed(FALSE);
        if ( result ) {
            logit(lcl_vError,@"[SecKeychainSetUserInteractionAllowed] %@",[self errorForOSStatus:result].localizedDescription);
            return result;
        }
         */
        result = SecKeychainOpen([aKeychainFilePath fileSystemRepresentation], &keychainItem);
        if (result != 0) {
            logit(lcl_vError,@"[SecKeychainOpen] %@",[self errorForOSStatus:result].localizedDescription);
            NSLog(@"%@",[self errorForOSStatus:result].localizedDescription);
        }
        result = SecKeychainUnlock(keychainItem, (UInt32)strlen(uuid), uuid, TRUE);
        if (result != 0) {
            logit(lcl_vError,@"[SecKeychainUnlock] %@",[self errorForOSStatus:result].localizedDescription);
            NSLog(@"%@",[self errorForOSStatus:result].localizedDescription);
        }
    }
    
    return result;
}

#pragma mark - Public

//
// Uses SecKeychainItemCreateFromContent()
// This method is an experiment, normally use addPasswordItemToKeychain
//
- (OSStatus)addPassword:(NSString *)aPassword username:(NSString *)aUserName serviceName:(NSString *)aServiceName
{
    OSStatus err;
    SecKeychainItemRef item = nil;
    const char *aUserNameUTF8 = [aUserName UTF8String];
    const char *aPasswordUTF8 = [aPassword UTF8String];
    const char *aServiceNameUTF8 = [aServiceName UTF8String];
    
    //Following is the lower-level equivalent to the
    // SecKeychainAddInternetPassword function:
    
    //Set up the attribute vector (each attribute consists
    // of {tag, length, pointer}):
    SecKeychainAttribute attrs[] = {
        { kSecServiceItemAttr, (UInt32)strlen(aServiceNameUTF8), (char *)aServiceNameUTF8 },
        { kSecAccountItemAttr, (UInt32)strlen(aUserNameUTF8), (char *)aUserNameUTF8 }
    };
    
    SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]), attrs };
    err = SecKeychainItemCreateFromContent(
                                           kSecGenericPasswordItemClass,
                                           &attributes,
                                           (UInt32)strlen(aPasswordUTF8),
                                           aPasswordUTF8,
                                           keychainItem,
                                           accessRef,
                                           &item);
    return err;
}

- (OSStatus)addPasswordItemToKeychain:(NSString *)aPassword username:(NSString *)aUserName serviceName:(NSString *)aServiceName
{
    OSStatus result = noErr;
    result = SecKeychainAddGenericPassword(keychainItem, //the custom keychain
                                           (UInt32)strlen([aServiceName UTF8String]),[aServiceName UTF8String],
                                           (UInt32)strlen([aUserName UTF8String]),[aUserName UTF8String],
                                           (UInt32)strlen([aPassword UTF8String]),[aPassword UTF8String],
                                           NULL);
    if (noErr != result) {
        CFStringRef errMsg = SecCopyErrorMessageString(result, NULL);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:(__bridge NSString *)errMsg forKey:NSLocalizedDescriptionKey];
        self.error = nil;
        self.error = [NSError errorWithDomain:@"gov.llnl.mp.keychain" code:-1002 userInfo:userInfo];
        CFRelease(errMsg);
    }
    
    return result;
}

- (OSStatus)addP12CertificateToKeychain:(NSString *)aCertPath certPassword:(NSString *)aPassword
{
    OSStatus result = noErr;
    CFArrayRef outItems = NULL;
    
    NSData *certData = [NSData dataWithContentsOfFile:aCertPath];
    
    SecKeyImportExportFlags importFlags = kSecKeyImportOnlyOne;
    SecKeyImportExportParameters importParameters;
    importParameters.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
    importParameters.flags = importFlags;
    importParameters.passphrase = (__bridge CFStringRef)aPassword;
    importParameters.accessRef = accessRef;
    importParameters.keyUsage = CSSM_KEYUSE_ANY;
    importParameters.keyAttributes = CSSM_KEYATTR_SENSITIVE | CSSM_KEYATTR_EXTRACTABLE;
    
    SecExternalFormat inputFormat = kSecFormatPKCS12;
    SecExternalItemType itemType = kSecItemTypeUnknown;
    
    result = SecKeychainItemImport((__bridge CFDataRef)certData,  // CFDataRef importedData
                                   NULL,                          // CFStringRef fileNameOrExtension
                                   &inputFormat,                  // SecExternalFormat *inputFormat
                                   &itemType,                     // SecExternalItemType *itemType
                                   0,                             // SecItemImportExportFlags flags (Unused)
                                   &importParameters,             // const SecKeyImportExportParameters *keyParams
                                   keychainItem,                  // SecKeychainRef importKeychain
                                   &outItems);                    // CFArrayRef *outItems
    
    if (noErr != result) {
        CFStringRef errMsg = SecCopyErrorMessageString(result, NULL);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:(__bridge NSString *)errMsg forKey:NSLocalizedDescriptionKey];
        self.error = nil;
        self.error = [NSError errorWithDomain:@"gov.llnl.mp.keychain" code:-1002 userInfo:userInfo];
        CFRelease(errMsg);
    }
    
    return result;
}

//
// Store Info in Keychain as Dictionary
//
- (OSStatus)addDictionaryToKeychainWithKey:(NSString *)aKey dictionary:(NSDictionary *)aDict error:(NSError **)err
{
    return [self addDictionaryToKeychainWithKeyReplaceIfExists:aKey dictionary:aDict replace:self.overWriteKeyChainData error:err];
}

- (OSStatus)addDictionaryToKeychainWithKeyReplaceIfExists:(NSString *)aKey dictionary:(NSDictionary *)aDict
                                                  replace:(BOOL)aReplace error:(NSError **)err
{
    // serialize dict
    NSData *serializedDictionary = [NSKeyedArchiver archivedDataWithRootObject:aDict];
    // encrypt in keychain
    // first, delete potential existing entries with this key (it won't auto update)
    OSStatus status = 0;
    if ([self itemInKeychain:aKey status:status]) {
        if (aReplace) {
            [self deleteFromKeychainWithKey:aKey];
        } else {
            NSLog(@"Item already exists in keychain. Item will not be replaced.");
            return errSecDuplicateItem;
        }
    }
    
    // setup keychain storage properties
    SecAccessRef kAccess = [self createDefaultAccessRef:NULL];
    // (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly,
    NSDictionary *storageQuery = @{
                                   (__bridge id)kSecAttrAccount:    aKey,
                                   (__bridge id)kSecValueData:      serializedDictionary,
                                   (__bridge id)kSecClass:          (__bridge id)kSecClassGenericPassword,
                                   (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlocked,
                                   (__bridge id)kSecUseKeychain:    (__bridge id)keychainItem,
                                   (__bridge id)kSecAttrAccess:     (__bridge id)kAccess,
                                   };
    
    OSStatus osStatus = SecItemAdd((__bridge CFDictionaryRef)storageQuery, nil);
    if(osStatus != noErr) {
        // do someting with error
        if (err != NULL) {
            *err = [self errorForOSStatus:osStatus];
        }
    }
    [self lockKeychain];
    return osStatus;
}

- (NSDictionary *)dictionaryFromKeychainWithKey:(NSString *)aKey error:(NSError **)err
{
    // setup keychain query properties
    NSDictionary *readQuery = @{
                                (__bridge id)kSecAttrAccount:   aKey,
                                (__bridge id)kSecReturnData:    (id)kCFBooleanTrue,
                                (__bridge id)kSecClass:         (__bridge id)kSecClassGenericPassword,
                                (__bridge id)kSecUseKeychain:   (__bridge id)keychainItem
                                };
    
    CFDataRef serializedDictionary = NULL;
    OSStatus osStatus = SecItemCopyMatching((__bridge CFDictionaryRef)readQuery, (CFTypeRef *)&serializedDictionary);
    if(osStatus == noErr) {
        // deserialize dictionary
        NSData *data = (__bridge NSData *)serializedDictionary;
        NSDictionary *storedDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        return storedDictionary;
    } else if (osStatus == errSecItemNotFound) {
        NSLog(@"%@",[self errorForOSStatus:osStatus].localizedDescription);
        return nil;
    } else {
        if (err != NULL) {
            NSLog(@"%@",[self errorForOSStatus:osStatus].localizedDescription);
            *err = [self errorForOSStatus:osStatus];
        }
        return nil;
    }
}

- (BOOL)itemInKeychain:(NSString *)aKey status:(OSStatus)aStatus;
{
    OSStatus err;
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  aKey, (__bridge id)kSecAttrAccount,
                                  (__bridge id)kCFBooleanTrue, (__bridge id)kSecReturnAttributes,
                                  (__bridge id)kSecMatchLimitAll, (__bridge id)kSecMatchLimit,
                                  (__bridge id)keychainItem, (__bridge id)kSecUseKeychain,
                                  nil];
    
    NSArray *secItemClasses = [NSArray arrayWithObjects: (__bridge id)kSecClassGenericPassword, nil];
    
    for (id secItemClass in secItemClasses)
    {
        [query setObject:secItemClass forKey:(__bridge id)kSecClass];
        CFTypeRef result = NULL;
        err = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        //NSLog(@"%@", (__bridge id)result);
        if (result != NULL) CFRelease(result);
    }
    
    if (err == noErr) {
        return TRUE;
    } else {
        return FALSE;
    }
}

- (NSString *)serviceLabelForServer
{
    return [NSString stringWithFormat:@"Server (%@)",[self clientUUID]];
}

- (NSString *)serviceLabelForClient
{
    return [NSString stringWithFormat:@"Client (%@)",[self clientUUID]];
}

//
// I cheated, this was way quicker ;-)
//
- (int)addCAToSystemKeychain:(NSData *)aCACert
{
    NSString *caFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mpCA.crt"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:caFile]) {
        [[NSFileManager defaultManager] removeItemAtPath:caFile error:NULL];
    }
    [aCACert writeToFile:caFile atomically:NO];
    NSString *cmd = [NSString stringWithFormat:@"/usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain %@", caFile];
    int result = -1;
    result = system([cmd UTF8String]);
    return result;
}

- (NSString *)passwordForGenericService:(NSString*)service forAccount:(NSString*)account
{
    int err, errFind;
    char *passData;
    UInt32 passLength;
    SecKeychainItemRef itemRef = nil;
    SecKeychainStatus keychainStatus;
    err = SecKeychainGetStatus(keychainItem,&keychainStatus);
    /*
     NSLog(@"unlocked: %@", (keychainStatus & kSecUnlockStateStatus) ? @"YES" : @"NO");
     NSLog(@"    read: %@", (keychainStatus & kSecReadPermStatus) ? @"YES" : @"NO");
     NSLog(@"   write: %@", (keychainStatus & kSecWritePermStatus) ? @"YES" : @"NO");
     */
    
    SecKeychainSetUserInteractionAllowed(FALSE);
    
    errFind = SecKeychainFindGenericPassword(keychainItem,
                                             (UInt32)strlen([service UTF8String]),[service UTF8String],
                                             (UInt32)strlen([account UTF8String]), [account UTF8String],
                                             &passLength, (void**)&passData, &itemRef);
    if (errFind == CSSM_OK) {
        NSString __strong *pass = [[NSString alloc] initWithCStringNoCopy:passData length:passLength freeWhenDone:YES];
        SecKeychainItemFreeContent(NULL, passData);
        return pass;
    } else {
        CFStringRef errMsg = SecCopyErrorMessageString(errFind, NULL);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:(__bridge NSString *)errMsg forKey:NSLocalizedDescriptionKey];
        self.error = nil;
        self.error = [NSError errorWithDomain:@"gov.llnl.mp.keychain" code:-1005 userInfo:userInfo];
        CFRelease(errMsg);
        return nil;
    }
}

- (OSStatus)lockKeychain
{
    return SecKeychainLock(keychainItem);
}

#pragma mark - Private

/* Client Info for Keychain
 * uuid + modelinfo MD5(result)
 */
- (NSString *)clientInfo
{
    NSMutableString *client = [NSMutableString new];
    [client appendString:[self clientUUID]];
    [client appendFormat:@" %@",[self modelInfo]];
    return [self md5HexDigest:client];
    //return @"123456";
}

- (NSString *)md5HexDigest:(NSString*)input
{
    const char* str = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%03x",result[i]];
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

- (SecAccessRef)createDefaultAccessRef:(NSError **)err
{
    OSStatus result;
    SecTrustedApplicationRef me;
    SecTrustedApplicationRef MPAgent = NULL;
    SecTrustedApplicationRef MPAgentExec = NULL;
    SecTrustedApplicationRef MPWorker = NULL;
    SecTrustedApplicationRef MPCatalog = NULL;
    SecTrustedApplicationRef SelfPatch = NULL;
    SecTrustedApplicationRef MPClientStatus = NULL;
    SecTrustedApplicationRef MPLoginAgent = NULL;
    
    result = SecTrustedApplicationCreateFromPath(NULL, &me);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/MPAgent", &MPAgent);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/MPAgentExec", &MPAgentExec);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/MPWorker", &MPWorker);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/MPCatalog.app", &MPCatalog);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/Self Patch.app", &SelfPatch);
    result = SecTrustedApplicationCreateFromPath("/Library/MacPatch/Client/MPClientStatus.app", &MPClientStatus);
    result = SecTrustedApplicationCreateFromPath("/Library/PrivilegedHelperTools/MPLoginAgent.app", &MPLoginAgent);
    
    NSArray *trustedApplications = [NSArray arrayWithObjects:(__bridge_transfer id)me, (__bridge_transfer id)MPAgent,
                                    (__bridge_transfer id)MPAgentExec, (__bridge_transfer id)MPWorker,(__bridge_transfer id)MPCatalog,
                                    (__bridge_transfer id)SelfPatch,(__bridge_transfer id)MPClientStatus,(__bridge_transfer id)MPLoginAgent,nil];
    
    SecAccessRef accessObj = NULL;
    result = SecAccessCreate((__bridge CFStringRef)_accessLabel, (__bridge CFArrayRef)trustedApplications, &accessObj);
    if (noErr != result) {
        if (err != NULL) {
            *err = [self errorForOSStatus:result];
        }
        return nil;
    }
    
    return accessObj;
}

- (SecAccessRef)createAccessRef:(NSError **)err
{
    OSStatus result;
    SecAccessRef access = NULL;
    NSArray *trustedApplications = nil;
    
    
    SecTrustedApplicationRef myself;
    result = SecTrustedApplicationCreateFromPath(NULL, &myself);
    
    if (result)
        return nil;
    
    //trustedApplications = [NSArray arrayWithObjects:(__bridge id)myself, nil];
    trustedApplications = [NSArray new];
    result = SecAccessCreate((__bridge CFStringRef)_accessLabel,(__bridge CFArrayRef)trustedApplications, &access);
    
    if (result) {
        if (err != NULL) {
            *err = [self errorForOSStatus:result];
        }
        return nil;
    }
    
    return access;
}

- (OSStatus)deleteFromKeychainWithKey:(NSString *)aKey
{
    OSStatus itemStatus = 0;
    BOOL res = [self itemInKeychain:aKey status:itemStatus];
    if (res) {
        NSLog(@"OSStatus: %@",[self errorForOSStatus:itemStatus]);
    }
    
    OSStatus    osStatus;
    NSDictionary *deletableItemsQuery = @{
                                          (__bridge id)kSecAttrAccount:        aKey,
                                          (__bridge id)kSecClass:              (__bridge id)kSecClassGenericPassword,
                                          (__bridge id)kSecMatchLimit:         (__bridge id)kSecMatchLimitAll,
                                          (__bridge id)kSecReturnAttributes:   (id)kCFBooleanTrue,
                                          (__bridge id)kSecUseKeychain:        (__bridge id)keychainItem
                                          };
    
    osStatus = SecItemDelete((CFDictionaryRef)deletableItemsQuery);
    if (osStatus != noErr) {
        NSLog(@"deleteFromKeychainWithKey :%d",osStatus);
    }
    
    return osStatus;
}

#pragma mark Error codes

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message
{
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: message};
    return [NSError errorWithDomain:@"MPKeychainDomain" code:code userInfo:userInfo];
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
