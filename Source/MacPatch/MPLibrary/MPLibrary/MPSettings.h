//
//  MPSettings.h
//  MPLibrary
//
//  Created by Charles Heizer on 6/12/17.
//
//

#import <Foundation/Foundation.h>

@class Agent;

@interface MPSettings : NSObject

@property (nonatomic, strong, readonly) NSString *ccuid;
@property (nonatomic, strong, readonly) NSString *serialno;
@property (nonatomic, strong, readonly) NSString *osver;
@property (nonatomic, strong, readonly) NSString *ostype;
@property (nonatomic, strong, readonly) NSString *agentVer;
@property (nonatomic, strong, readonly) NSString *clientVer;

@property (nonatomic, strong, readonly) Agent *agent;
@property (nonatomic, strong, readonly) NSArray *servers;
@property (nonatomic, strong, readonly) NSArray *suservers;
@property (nonatomic, strong, readonly) NSArray *tasks;


+ (MPSettings *)sharedInstance;

- (BOOL)refresh;
- (BOOL)settings;
- (BOOL)compareAndUpdateSettings:(NSDictionary *)remoteSettingsRevs;

@end
