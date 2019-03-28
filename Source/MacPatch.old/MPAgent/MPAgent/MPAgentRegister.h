//
//  MPAgentRegister.h
//  MPAgent
//
//  Created by Heizer, Charles on 8/8/14.
//  Copyright (c) 2018 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MPWebServices;

@interface MPAgentRegister : NSObject

@property (nonatomic, strong) NSString *clientKey;
@property (nonatomic, strong) NSString *registrationKey;
@property (nonatomic, strong) NSString *hostName;
@property (nonatomic, assign) BOOL overWriteKeyChainData;


- (BOOL)clientIsRegistered;

- (int)registerClient:(NSError **)error;
- (int)registerClient:(NSString *)aRegKey error:(NSError **)error;

- (int)unregisterClient:(NSError **)error;
- (int)unregisterClient:(NSString *)aRegKey error:(NSError **)error;

@end
