//
//  MPServerEntry.h
//  MPAgentExec
//
//  Created by Heizer, Charles on 9/15/14.
//  Copyright (c) 2014 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MPServerEntry : NSObject

@property (nonatomic, strong) NSString *host;
@property (nonatomic, strong) NSString *port;
@property (nonatomic, strong) NSString *serverType;
@property (nonatomic, strong) NSString *useHTTPS;
@property (nonatomic, strong) NSString *useTLSAuth;
@property (nonatomic, strong) NSString *allowSelfSigned;
@property (nonatomic, strong) NSString *order;

- (id)initWithServerDictionary:(NSDictionary *)aServerItem index:(NSString *)idx;
- (NSDictionary *)dictionaryRepresentation;
- (NSDictionary *)parseWithDictionary:(NSDictionary *)aDictionary index:(NSString *)idx;

@end
