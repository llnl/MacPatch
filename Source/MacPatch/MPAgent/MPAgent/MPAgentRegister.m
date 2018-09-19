//
//  MPAgentRegister.m
//  MPAgent
//
//  Created by Heizer, Charles on 8/8/14.
//  Copyright (c) 2018 LLNL. All rights reserved.
//

#import "MPAgentRegister.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MacPatch.h"
#import "MPAgent.h"
#import "MPCrypto.h"

#define AUTO_REG_KEY    @"999999999"
#define SRV_PUB_KEY     @"/Library/Application Support/MacPatch/.keys/ServerPub.pem"

#undef  ql_component
#define ql_component lcl_cMPAgentRegister

@interface MPAgentRegister ()
{
    MPAgent *agent;
}
@end

@implementation MPAgentRegister

@synthesize clientKey           = _clientKey;
@synthesize registrationKey     = _registrationKey;
@synthesize hostName            = _hostName;

// CEH - Web Services
- (id)init
{
    self = [super init];
    if (self)
    {
        agent = [MPAgent sharedInstance];
        self.hostName = (__bridge NSString *)SCDynamicStoreCopyLocalHostName(NULL);
        self.registrationKey = AUTO_REG_KEY;
        self.clientKey = [[NSProcessInfo processInfo] globallyUniqueString];
        self.overWriteKeyChainData = NO;
    }
    return self;
}

- (BOOL)clientIsRegistered
{
    BOOL result = FALSE;
    NSError *err = nil;
    
    // Get Client Key
    MPSimpleKeychain *skc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_KEYCHAIN_FILE];
    MPKeyItem *clientKeyItem = [skc retrieveKeyItemForService:kMPClientService error:&err];
    if (err) {
        logit(lcl_vError,@"%@",err.localizedDescription);
        return FALSE;
    }
    
    // Gen SHA1 Digest
    err = nil;
    MPCrypto *mpc = [[MPCrypto alloc] init];
    NSString *keyHash = [mpc getHashFromStringForType:clientKeyItem.secret type:@"SHA1"];
    if (err) {
        logit(lcl_vError,@"%@",err.localizedDescription);
        return FALSE;
    }
    
    // Query WebService for answer
    MPRESTfull *mprest = [[MPRESTfull alloc] initWithClientID:agent.g_cuuid];
    result = [mprest getAgentRegistrationStatusUsingKey:keyHash error:&err];
    if (err) {
        logit(lcl_vError,@"%@",err.localizedDescription);
        return FALSE;
    }
    
    return result;
}

- (BOOL)clientIsRegisteredWithValidData
{
    // This is Not Complete
    return FALSE;
    NSError *err = nil;
    
    MPSimpleKeychain *skc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_KEYCHAIN_FILE];
    MPKeyItem *srvKeyItem = [skc retrieveKeyItemForService:kMPServerService error:&err];
    if (err) {
        NSLog(@"%@",err.localizedDescription);
        return FALSE;
    }
    NSLog(@"Server Key Data: %@",srvKeyItem.toDictionary);
    
    err = nil;
    MPKeyItem *clientKeyItem = [skc retrieveKeyItemForService:kMPClientService error:&err];
    if (err) {
        NSLog(@"%@",err.localizedDescription);
        return FALSE;
    }
    NSLog(@"Client Key Data: %@",clientKeyItem.toDictionary);
    
    return TRUE;
}

- (int)registerClient:(NSError **)error
{
    return [self registerClient:nil error:error];
}

- (int)registerClient:(NSString *)aRegKey error:(NSError **)error
{
    if ([self clientIsRegistered]) {
        qlwarning(@"Agent is already registered.");
        return 1;
    }
    
    int res = 0;
    NSError *err = nil;
    
    NSDictionary *regDict = [self generateRegistrationData:&err];
    qldebug(@"[regDict]: %@", regDict);
    if (err) {
        if (error != NULL) {
            *error = err;
        } else {
            qlerror(@"%@",err.localizedDescription);
        }
        return 1;
    }
    
    err = nil;
    [self postRegistrationToServer:regDict regKey:aRegKey error:&err];
    if (err) {
        if (error != NULL) {
            *error = err;
        } else {
            qlerror(@"%@",err.localizedDescription);
        }
        return 1;
    }
    
    return res;
}

- (int)unregisterClient:(NSError **)error
{
    return [self unregisterClient:error];
}

- (int)unregisterClient:(NSString *)aRegKey error:(NSError **)error
{
    // CEH - Needs to be implemented
    //NSError *err = nil;
    //NSString *res = [mpws getRegisterAgent:aRegKey hostName:hostName clientKey:clientKey error:&err];
    //NSLog(@"%@",res);
    return 0;
}

#pragma mark - Private
- (BOOL)addServerPublicKeyFileToKeychain:(NSString *)aFilePath error:(NSError **)err
{
    NSFileManager *fm = [NSFileManager defaultManager];
    MPSimpleKeychain *skc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_KEYCHAIN_FILE];
    
    NSString *pubKeyStr;
    NSError  *error = nil;
    
    // Read Server Public Key to String to add to keychain
    if ([fm fileExistsAtPath:aFilePath]) {
        pubKeyStr = [NSString stringWithContentsOfFile:aFilePath encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            if (err != NULL) {
                *err = error;
            } else {
                printf("%s\n",[error.localizedDescription UTF8String]);
            }
            return NO;
        }
    } else {
        if (err != NULL) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Server Public key file was not found."};
            *err = [NSError errorWithDomain:@"MPAgentRegistrationDomain" code:99996 userInfo:userInfo];
        } else {
            printf("Error, file (%s) not found. \n",[aFilePath UTF8String]);
        }
        return NO;
    }
    
    // Create new MPKeyItem, add server public key
    // Add key item to keychain for server service
    MPKeyItem *kItem = [[MPKeyItem alloc] init];
    kItem.publicKey = pubKeyStr;
    error = nil;
    BOOL itemAdded = [skc saveKeyItemWithService:kItem service:kMPServerService error:&error];
    if (error) {
        if (err != NULL) *err = error;
        return NO;
    }
    
    if (itemAdded) {
        return YES;
    }
    
    return NO;
}

- (BOOL)addClientKeysToKeychain:(MPKeyItem *)aClientKeys error:(NSError **)err
{
    NSError *error = nil;
    MPSimpleKeychain *skc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_KEYCHAIN_FILE];
    
    // Make Sure the MPKeyItem is not nil
    if (!aClientKeys) {
        if (err != NULL) {
            *err = [skc errorForOSStatus:errSecBadReq];
        } else {
            printf("%s\n",[[skc errorForOSStatus:errSecBadReq].localizedDescription UTF8String]);
        }
        return NO;
    }

    // Add the keys to the Keychain
    OSStatus *result = [skc saveKeyItemWithService:aClientKeys service:kMPClientService error:&error];
    if (error) {
        if (err != NULL) {
            *err = error;
        } else {
            printf("%s\n",[error.localizedDescription UTF8String]);
        }
        return NO;
    }
    
    if (result != noErr)
    {
        if (err != NULL) {
            *err = [skc errorForOSStatus:result];
        } else {
            printf("%s\n",[[skc errorForOSStatus:result].localizedDescription UTF8String]);
        }
        return NO;
    }
    
    return YES;
}

- (MPKeyItem *)generateClientKeys:(NSError **)err
{
    NSError *error = nil;
    MPKeyItem *kItem = [[MPKeyItem alloc] init];
    MPCrypto *mpc = [[MPCrypto alloc] init];
    
    // Create New Client Key and set class instance with the new key
    NSString *cKey = [[NSProcessInfo processInfo] globallyUniqueString];
    [self setClientKey:cKey];
    
    // Generate a RSA keypair for the Agent using 2048 bit key size
    error = nil;
    int keyRes = [mpc generateRSAKeyPairOfSize:2048 error:&error];
    if (error || keyRes != 0) {
        if (err != NULL) *err = error;
        return nil;
    }
    
    // Put both keys in to a dictionary that will be stored in the
    // keychain for the client.
    error = nil;
    NSDictionary *clientKeys = [mpc rsaKeysForRegistration:&error];
    if (error) {
        if (err != NULL) *err = error;
        return nil;
    }
    
    kItem.publicKey = [clientKeys objectForKey:@"publicKey"];
    kItem.privateKey = [clientKeys objectForKey:@"privateKey"];
    kItem.secret = cKey;
    
    return [kItem copy];
}

- (NSDictionary *)generateRegistrationData:(NSError **)err
{
    MPSimpleKeychain *skc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_KEYCHAIN_FILE];
    
    NSError *error = nil;
    qldebug(@"Keychain: %@",MP_KEYCHAIN_FILE);
    if ([[NSFileManager defaultManager] fileExistsAtPath:MP_KEYCHAIN_FILE]) {
        [skc deleteKeyChain]; // Use Keychain tools to delete first
        [NSThread sleepForTimeInterval:1.0];
        [[NSFileManager defaultManager] removeItemAtPath:MP_KEYCHAIN_FILE error:NULL];
        [NSThread sleepForTimeInterval:2.0];
    }

    OSStatus kcStatus = [skc createKeyChain:MP_KEYCHAIN_FILE];
    if (kcStatus != noErr) {
        if (err != NULL) {
            *err = [skc errorForOSStatus:kcStatus];
        }
        return nil;
    }
    
    // Add Server Public Key to Keychain, for simplicity
    // Get the Server Public Key from the Server Data
    error = nil;
    MPKeyItem *srvKeyItem = [skc retrieveKeyItemForService:kMPServerService error:&error];
    if (error) {
        qldebug(@"%@",error.localizedDescription);
    }
    
    if (!srvKeyItem) {
        // srvKeyItem will be nil if not found, so we add it
        if ([[NSFileManager defaultManager] fileExistsAtPath:SRV_PUB_KEY])
        {
            error = nil;
            BOOL addServerKey = [self addServerPublicKeyFileToKeychain:SRV_PUB_KEY error:&error];
            
            if (error)
                if (err != NULL) *err = error;
            
            if (addServerKey == NO)
                return nil;
        }
        else
        {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Public key was not found on file system."};
            if (err != NULL) *err = [NSError errorWithDomain:@"MPAgentRegistrationDomain" code:99999 userInfo:userInfo];
            return nil;
        }
    }
    
    // Get the Key now that it has been added to keychain
    error = nil;
    srvKeyItem = [skc retrieveKeyItemForService:kMPServerService error:&error];
    if (error) {
        if (err != NULL) *err = error;
        return nil;
    }
    
    // Create the Client Keys then add to Keychain
    error = nil;
    MPKeyItem *clientKeyItem = [self generateClientKeys:&error];
    if (error) {
        if (err != NULL) *err = error;
        return nil;
    }
    
    error = nil;
    [self addClientKeysToKeychain:clientKeyItem error:&error];
    if (error) {
        if (err != NULL) *err = error;
        return nil;
    }
    
    
    // Encrypt the client key using the servers public key
    // also, SHA1 encode the client key. This will be used to
    // verify that we decoded the key properly and it matches.
    error = nil;
    MPCrypto *mpc = [[MPCrypto alloc] init];
    NSData *pubKeyData = [srvKeyItem.publicKey dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encodedKey = [mpc encryptStringUsingKey:clientKeyItem.secret key:[mpc getKeyRef:pubKeyData] error:&error];
    NSString *hashOfKey =[mpc getHashFromStringForType:clientKeyItem.secret type:@"SHA1"];
    if (error) {
        if (err != NULL) *err = error;
        return nil;
    }
    error = nil;
    [hashOfKey writeToFile:MP_AGENT_HASH atomically:NO encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        if (err != NULL) *err = error;
        return nil;
    }
    
    // Create the dictionary to send to Web service
    @try
    {
        MPClientInfo *ci = [[MPClientInfo alloc] init];
        NSDictionary *regInfo = @{ @"cuuid":      [agent g_cuuid],
                                   @"cKey":       [encodedKey copy],
                                   @"CPubKeyPem": clientKeyItem.publicKey,
                                   @"CPubKeyDer": @"NA",
                                   @"ClientHash": hashOfKey,
                                   @"HostName":   [agent g_hostName],
                                   @"SerialNo":   [agent g_serialNo],
                                   @"CheckIn":    [ci agentData]
                                   };
        return regInfo;
    }
    @catch (NSException *exception) {
        if (err != NULL) *err = [NSError errorWithDomain:@"MPAgentRegistrationDomain" code:9998 userInfo:exception.userInfo];
        return nil;
    }
    
    // Should not get here
    return nil;
}

- (BOOL)postRegistrationToServer:(NSDictionary *)aRegData regKey:(NSString *)regKey error:(NSError **)err
{
    BOOL result = NO;
    NSError *error = nil;
    MPRESTfull *rest = [[MPRESTfull alloc] initWithClientID:agent.g_cuuid];
    result = [rest postAgentRegistration:aRegData regKey:regKey error:&error];
    if (error) {
        if (err != NULL) *err = error;
        return NO;
    }
    return result;
}
@end
