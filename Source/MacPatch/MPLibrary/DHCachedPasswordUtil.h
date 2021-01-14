//
//  DHCachedPasswordUtil.h
//  MPLibrary
//
//  Created by Hoit, Daniel S. on 3/2/17.
//  Copyright © 2017 SMSG Mac Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OpenDirectory/OpenDirectory.h>

NS_ASSUME_NONNULL_BEGIN

@interface DHCachedPasswordUtil : NSObject

@property (strong) ODSession *mySession;
@property (strong) ODNode *myNode;

/*
 Check to see if Network OD nodes are available.
 */
+ (BOOL)onlineAuthenticationAvailable;
- (id)init;
/*
 Check (and cache) password for user name. Returns false if password does not authenticate user.
 */
- (BOOL)checkPassword:(NSString *)pass forUserWithName:(NSString *)userName;

- (NSArray *)usersWithName:(NSString *)name;
- (BOOL)userIsNetworkUserAccount:(ODRecord *)userAcct;
- (NSDate *)smbPasswordLastSetDateForUser:(ODRecord *)userAcct;

@end

NS_ASSUME_NONNULL_END
