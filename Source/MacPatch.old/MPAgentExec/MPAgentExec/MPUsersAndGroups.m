//
//  MPUsersAndGroups.m
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
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

#import "MPUsersAndGroups.h"
#import <OpenDirectory/OpenDirectory.h>
#import <OpenDirectory/ODQuery.h>

@interface MPUsersAndGroups ()

@property(nonatomic, strong, readwrite)NSArray *usrAttrs;
@property(nonatomic, strong, readwrite)NSArray *grpAttrs;

- (ODQuery *)queryRecordTypeWithAttributes:(id)inRecordTypeOrList attributes:(id)inReturnAttributeOrList error:(NSError **)error;
- (NSString *)valueForODAttribute:(ODRecord *)record attribute:(id)inODAttributeValue;

@end


@implementation MPUsersAndGroups

@synthesize usrAttrs;
@synthesize grpAttrs;

- (id)init
{
    self = [super init]; 
    [self setUsrAttrs:[NSArray arrayWithObjects:kODAttributeTypeFullName, kODAttributeTypeRecordName, kODAttributeTypeUniqueID, 
                       kODAttributeTypePrimaryGroupID, kODAttributeTypeUserShell, kODAttributeTypeNFSHomeDirectory, 
                       kODAttributeTypeUniqueID, kODAttributeTypeRecordType, kODAttributeTypeRecordName, nil]];
    
    [self setGrpAttrs:[NSArray arrayWithObjects:kODAttributeTypeRecordName, kODAttributeTypeRecordType, kODAttributeTypeFullName,
                       kODAttributeTypeGroupMembers, kODAttributeTypePrimaryGroupID, kODAttributeTypeGroupMembership, nil]];
    
    return self;
}

#pragma mark - Private Methods

- (ODQuery *)queryRecordTypeWithAttributes:(id)inRecordTypeOrList attributes:(id)inReturnAttributeOrList error:(NSError **)error
{
    ODQuery *_query = [ODQuery  queryWithNode: [ODNode nodeWithSession:nil type:kODNodeTypeLocalNodes error:NULL]
                               forRecordTypes: inRecordTypeOrList
                                    attribute: kODAttributeTypeRecordName
                                    matchType: kODMatchContains
                                  queryValues: nil
                             returnAttributes: inReturnAttributeOrList
                               maximumResults: 0
                                        error: error];
    
    return _query;
}

- (NSString *)valueForODAttribute:(ODRecord *)record attribute:(id)inODAttributeValue
{
    NSError *err = nil;;
    NSArray *attrArray = [record valuesForAttribute:inODAttributeValue error:&err];
    if (err) {
        return @"NA";
    }
    if (attrArray == nil) {
        return @"NA";
    }
    
    return [attrArray componentsJoinedByString:@","];
}

#pragma mark - Public Methods

- (NSArray *)getLocalUsers:(NSError **)error
{
    NSError *err = nil;
    ODQuery *usrQuery = [self queryRecordTypeWithAttributes:kODRecordTypeUsers attributes:[self usrAttrs] error:&err];
    
    if (err) {
        if (error != NULL) *error = err;
        return nil;
    }
    
    err = nil;
    NSArray *res = [usrQuery resultsAllowingPartial:NO error:&err];  
    
    if (err) {
        if (error != NULL) *error = err;
        return nil;
    }
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSMutableDictionary *d;
    for (id record in res) {
        d = [[NSMutableDictionary alloc] init];
        [d setObject:[record recordName] forKey:@"UserName"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeMetaNodeLocation] forKey:@"MetaNodeLocation"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeOriginalNodeName] forKey:@"OriginalNodeName"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeAuthenticationAuthority] forKey:@"AuthenticationAuthority"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeRecordType] forKey:@"RecordType"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeFullName] forKey:@"FullName"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeUniqueID] forKey:@"UserID"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypePrimaryGroupID] forKey:@"GroupID"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeNFSHomeDirectory] forKey:@"HomeDir"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeUserShell] forKey:@"UserShell"];
        [result addObject:[NSDictionary dictionaryWithDictionary:d]];
        d = nil;
    }
    
    return [NSArray arrayWithArray:result];
}

- (NSArray *)getLocalGroups:(NSError **)error
{
    NSError *err = nil;
    ODQuery *usrQuery = [self queryRecordTypeWithAttributes:kODRecordTypeGroups attributes:[self grpAttrs] error:&err];
    
    if (err) {
        if (error != NULL) *error = err;
        return nil;
    }
    
    err = nil;
    NSArray *res = [usrQuery resultsAllowingPartial:NO error:&err];  
    
    if (err) {
        if (error != NULL) *error = err;
        return nil;
    }
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NSMutableDictionary *d;
    for (id record in res) {
        d = [[NSMutableDictionary alloc] init];
        [d setObject:[record recordName] forKey:@"GroupName"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeMetaNodeLocation] forKey:@"MetaNodeLocation"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeRecordType] forKey:@"RecordType"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeFullName] forKey:@"FullName"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypePrimaryGroupID] forKey:@"GroupID"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeGroupMembers] forKey:@"GroupMembers"];
        [d setObject:[self valueForODAttribute:record attribute:kODAttributeTypeGroupMembership] forKey:@"GroupMembership"];
        [result addObject:[NSDictionary dictionaryWithDictionary:d]];
        d = nil;
    }
    
    return [NSArray arrayWithArray:result];
}

@end
