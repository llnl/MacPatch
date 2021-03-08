//
//  MPAgentRegister.m
//  MPAgent
//
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

// Web Services
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
    
    @try
    {
        NSError *err = nil;
        
        // Get Client Key
        AgentData *agentData = [[AgentData alloc] init];
            
        NSString *cKey = [agentData getClientKey];
        if (!cKey) {
            logit(lcl_vError,@"Agent key data not found.");
            return FALSE;
        }
        
        // Gen SHA1 Digest
        err = nil;
        MPCrypto *mpc = [[MPCrypto alloc] init];
        NSString *keyHash = [mpc getHashFromStringForType:cKey type:@"SHA1"];
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
        
    } @catch (NSException *exception) {
        qlerror(@"%@",exception);
    }
    
	return result;
}

- (BOOL)clientIsRegisteredWithValidData
{
	AgentData *agentData = [[AgentData alloc] init];
	NSData *srvKey = [agentData getServerPublicKey];
	if (!srvKey) {
		printf("Error, missing server public key for agent.\n");
		return FALSE;
	}
	NSData *pubKey = [agentData getAgentPublicKey];
	NSData *priKey = [agentData getAgentPrivateKey];
	if (!pubKey || !priKey) {
		printf("Error, missing public or private key for agent.\n");
		return FALSE;
	}
	
	NSString *cKey = [agentData getClientKey];
	if (!cKey) {
		printf("Error, missing agent key data.\n");
		return FALSE;
	}
	
	return TRUE;
}

- (int)registerClient:(NSError **)error
{
    return [self registerClient:@"NA" error:error];
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
	NSFileManager *fm = [NSFileManager defaultManager];
	NSError *error = nil;
	AgentData *agentData = [[AgentData alloc] init];

	// Add Server Public Key to Keychain, for simplicity
	// Get the Server Public Key from the Server Data
	NSData *srvPubKey;
	if ([fm fileExistsAtPath:SRV_PUB_KEY])
	{
		error = nil;
		srvPubKey = [NSData dataWithContentsOfFile:SRV_PUB_KEY];
		[agentData setServerPublicKey:srvPubKey];
	}
	else
	{
		NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Public key was not found on file system."};
		if (err != NULL) *err = [NSError errorWithDomain:@"MPAgentRegistrationDomain" code:99999 userInfo:userInfo];
		return nil;
	}
	
	
	// Create the Client Keys then add to Keychain
	error = nil;
	MPKeyItem *clientKeyItem = [self generateClientKeys:&error];
	if (error) {
		if (err != NULL) *err = error;
		return nil;
	}
	
	[agentData setAgentPublicKey:[clientKeyItem.publicKey dataUsingEncoding:NSUTF8StringEncoding]];
	[agentData setAgentPrivateKey:[clientKeyItem.privateKey dataUsingEncoding:NSUTF8StringEncoding]];
	[agentData setClientKey:clientKeyItem.secret];
	
	
	// Encrypt the client key using the servers public key
	// also, SHA1 encode the client key. This will be used to
	// verify that we decoded the key properly and it matches.
	error = nil;
	MPCrypto *mpc = [[MPCrypto alloc] init];
	NSString *encodedKey = [mpc encryptStringUsingKey:clientKeyItem.secret key:[mpc getKeyRef:srvPubKey] error:&error];
	NSString *hashOfKey = [mpc getHashFromStringForType:clientKeyItem.secret type:@"SHA1"];
    qltrace(@"hashOfKey: (%@)",hashOfKey);
    
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
