//
//  AgentData.h
//  TestSecureArchive
//
//  Created by Charles Heizer on 10/6/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AgentData : NSObject

@property (nonatomic, strong, readonly) NSData    *serverPublicKey;
@property (nonatomic, strong, readonly) NSData    *agentPublicKey;
@property (nonatomic, strong, readonly) NSData    *agentPrivateKey;
@property (nonatomic, strong, readonly) NSString  *clientKey;

- (NSString *)getClientKey;
- (NSData *)getServerPublicKey;
- (NSData *)getAgentPublicKey;
- (NSData *)getAgentPrivateKey;

- (void)setClientKey:(NSString *)aKey;
- (void)setServerPublicKey:(NSData *)aKey;
- (void)setAgentPublicKey:(NSData *)aKey;
- (void)setAgentPrivateKey:(NSData *)aKey;

- (BOOL)generateAgentData;

@end
