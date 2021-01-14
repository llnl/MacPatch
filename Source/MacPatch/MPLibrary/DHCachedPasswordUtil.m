//
//  DHCachedPasswordUtil.m
//  MPLibrary
//
//  Created by Hoit, Daniel S. on 3/2/17.
//  Copyright © 2017 SMSG Mac Team. All rights reserved.
//

#import "DHCachedPasswordUtil.h"
#define SecondsFrom1601To1970 11644473600

@implementation DHCachedPasswordUtil

+ (BOOL)onlineAuthenticationAvailable
{
    ODNode *authNode = [ODNode nodeWithSession:[ODSession defaultSession] type:kODNodeTypeAuthentication error:nil];
    NSArray *unreachable = [authNode unreachableSubnodeNamesAndReturnError:nil];
    NSArray *allNodes = [authNode subnodeNamesAndReturnError:nil];
    NSMutableSet *reachable = [NSMutableSet setWithArray:allNodes];
    [reachable minusSet:[NSSet setWithArray:unreachable]];
    
    if ([reachable isEqualToSet:[NSSet setWithObject:@"/Local/Default"]]) {
        return NO;
    } else {
        return YES;
    }
}


- (id)init
{
    return [self initWithNode:@"/Search"];
}
- (id)initWithNode:(NSString *)nodeName
{
    self = [super init];
    if (self) {
        
        self.mySession = [ODSession defaultSession];
        NSError *err = nil;
        self.myNode = [ODNode nodeWithSession:self.mySession name:nodeName error:&err];
        if (err) {
            NSLog(@"Error initializing OpenDirectory node %@. Error returned %@", nodeName, err);
        }
    }
    
    return self;
    
}

- (BOOL)checkPassword:(NSString *)pass forUserWithName:(NSString *)userName
{
    NSError *theError = nil;
    BOOL returnVal = FALSE;
    NSArray *usersWithName = [self usersWithName:userName];
    for (ODRecord *theUser in usersWithName) {
        //if ([self userIsNetworkUserAccount:theUser]) {
		returnVal = [theUser verifyPassword:pass error:&theError];
		if (returnVal == TRUE ) {
			//Cache
			[self.myNode passwordContentCheck:pass forRecordName:userName error:&theError];
		}
        //}
    }
    if (theError) {
        NSLog(@"Error verifying user password with the directory node: %@.", theError);
    }
    return returnVal;
}

- (NSArray *)usersWithName:(NSString *)userName
{
    NSError *theError = nil;
    ODQuery *findMe = [ODQuery queryWithNode:self.myNode
                              forRecordTypes:kODRecordTypeUsers
                                   attribute:kODAttributeTypeRecordName
                                   matchType:kODMatchEqualTo
                                 queryValues:userName
                            returnAttributes:kODAttributeTypeStandardOnly
                              maximumResults:0
                                       error:&theError
                       ];
    NSArray *results = nil;
    if (!theError) {
         results = [findMe resultsAllowingPartial:NO error:&theError];
    }
    if (theError) {
        NSLog(@"Error finding user accounts: %@", theError);
    }
    return results;
}

- (BOOL)userIsNetworkUserAccount:(ODRecord *)userAcct
{
    NSError *theError = nil;
    NSDictionary *allValues = [userAcct recordDetailsForAttributes:@[kODAttributeTypeMetaNodeLocation,kODAttributeTypeRecordName] error:&theError];
    if (theError) {
        NSLog(@"Error getting MetaNodeLocation for user account: %@", theError);
        return NO;
    }
    if ([[allValues[kODAttributeTypeMetaNodeLocation] lastObject] isEqualToString:@"/Local/Default"]) {
        return NO;
    } else {
        return YES;
    }
}

- (NSDate *)smbPasswordLastSetDateForUser:(ODRecord *)userAcct
{
    NSError *theError = nil;
    NSDictionary *allValues = [userAcct recordDetailsForAttributes:@[kODAttributeTypeSMBPWDLastSet,kODAttributeTypeRecordName] error:&theError];
    if (theError) {
        NSLog(@"Error getting SMBPasswordLastSetDate for user account: %@", theError);
        return nil;
    }
    NSNumber *smbTicks = [allValues[kODAttributeTypeSMBPWDLastSet] lastObject];
    
    NSDate *msEpoch = [NSDate dateWithTimeIntervalSince1970:-SecondsFrom1601To1970];
    NSDate *passwordLastSet = [msEpoch dateByAddingTimeInterval:([smbTicks doubleValue]/10000000)];

    return passwordLastSet;
}

@end
