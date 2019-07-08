//
//  MPKeychain.h
//  MPLibrary
//
//  Created by Heizer, Charles on 8/14/14.
//
//

#import <Foundation/Foundation.h>

@interface MPKeychain : NSObject
{
    SecKeychainRef  keychainItem;
    SecAccessRef    accessRef;
    NSString        *accessLabel;
    NSError         *error;
}

@property (nonatomic, assign) BOOL overWriteKeyChainData;
@property (nonatomic, strong) NSString *accessLabel;
@property (nonatomic, strong) NSError *error;

- (id)initWithKeychainFile:(NSString *)aKeychain;
- (id)initWithKeychainFile:(NSString *)aKeychain accessLabel:(NSString *)aAccessLabel;

// Set SecItems
- (OSStatus)addPassword:(NSString *)aPassword username:(NSString *)aUserName serviceName:(NSString *)aServiceName;
- (OSStatus)addPasswordItemToKeychain:(NSString *)aPassword username:(NSString *)aUserName serviceName:(NSString *)aServiceName;
- (OSStatus)addP12CertificateToKeychain:(NSString *)aCertPath certPassword:(NSString *)aPassword;

// Dictionary Items
- (OSStatus)addDictionaryToKeychainWithKey:(NSString *)aKey dictionary:(NSDictionary *)aDict error:(NSError **)err;
- (OSStatus)addDictionaryToKeychainWithKeyReplaceIfExists:(NSString *)aKey dictionary:(NSDictionary *)aDict replace:(BOOL)aReplace error:(NSError **)err;
- (NSDictionary *)dictionaryFromKeychainWithKey:(NSString *)aKey error:(NSError **)err;

- (OSStatus)addCAToSystemKeychain:(NSData *)aCACert;

// Get SecItems
- (NSString *)passwordForGenericService:(NSString*)service forAccount:(NSString*)account;

// Misc
- (OSStatus)lockKeychain;
- (BOOL)itemInKeychain:(NSString *)aKey status:(OSStatus)aStatus;

- (NSString *)serviceLabelForServer;
- (NSString *)serviceLabelForClient;

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message;
- (NSError *)errorForOSStatus:(OSStatus)OSStatus;
@end
