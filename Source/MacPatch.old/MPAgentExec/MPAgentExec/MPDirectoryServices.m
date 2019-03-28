//
//  MPDirectoryServices.m
//  MPAgentExec
//
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

#import "MPDirectoryServices.h"
#import <OpenDirectory/OpenDirectory.h>

#undef  ql_component
#define ql_component lcl_cMPDirectoryServices

@implementation MPDirectoryServices

@synthesize searchNode = _searchNode;

- (id)init
{
    return [self initWithSearchNode:@"/Search/Computers"];
}

- (id)initWithSearchNode:(NSString *)searchNodeName
{
    self = [super init];
    if (self)
    {
        odSession = [ODSession defaultSession];
        NSError *err = nil;
        [self setMyOdNode:searchNodeName];
        odNode = [ODNode nodeWithSession:odSession name:searchNodeName error:&err];
        if (err) {
            NSLog(@"Error initializing OpenDirectory node %@. Error returned %@", searchNodeName, err);
        }
    }
    return self;
}

- (NSString *)myOdName
{
    return [odNode nodeName];
}

- (void)setMyOdNode:(NSString *)nodeName
{
    if ([nodeName isEqualToString:[odNode nodeName]]) {//In case the node is already the default
        return;
    }
    NSError *err = nil;
    NSArray *allowedNodes = [odSession nodeNamesAndReturnError:&err];
    if (!err) {
        if ([allowedNodes containsObject:nodeName]) {
            odNode = [ODNode nodeWithSession:odSession name:nodeName error:&err];
        }
    }
    if (err) {
        NSLog(@"Error initializing new OpenDirectory node %@. Error returned is %@", nodeName, err);
    }
}

- (NSDictionary *)computerInfo:(NSString *)aComp
{
    NSError *error = nil;
    ODQuery *odQuery = [ODQuery queryWithNode:odNode
                               forRecordTypes:kODRecordTypeComputers
                                    attribute:@"dsAttrTypeStandard:RecordName"
                                    matchType:kODMatchBeginsWith
                                  queryValues:aComp
                             returnAttributes:nil
                               maximumResults:0
                                        error:&error];

    ODRecord *record;
    NSArray *attrs = [NSArray arrayWithObjects:@"dsAttrTypeNative:distinguishedName",@"dsAttrTypeNative:cn",
                      @"dsAttrTypeStandard:DNSName",@"dsAttrTypeNative:llnlHosts",@"dsAttrTypeStandard:AppleMetaNodeLocation",
                      @"dsAttrTypeStandard:AppleMetaRecordName",@"dsAttrTypeStandard:RecordType",nil];
    error = nil;
    NSArray *qResults = [odQuery resultsAllowingPartial:NO error:&error];
    if (error) {
        NSLog(@"Error on getting results. %@",error.localizedDescription);
        return nil;
    }

    NSMutableDictionary *_result = [[NSMutableDictionary alloc] init];
    if ([qResults count] > 0)
    {
        record = nil;
        for (record in qResults)
        {
            error = nil;
            NSDictionary *allValues = [record recordDetailsForAttributes:attrs error:&error];
            for (NSString *key in [allValues allKeys])
            {
                NSString *val = [[allValues objectForKey:key] componentsJoinedByString:@";"];
                [_result setObject:val forKey:key];
            }
        }
    } else {
        NSLog(@"No results found!");
    }

    return (NSDictionary *)_result;
}

@end
