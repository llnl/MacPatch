//
//  MPNetServer.m
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import "MPNetServer.h"

#undef  ql_component
#define ql_component lcl_cMPNetServer

@interface MPNetServer ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation MPNetServer

@synthesize host;
@synthesize port;
@synthesize useHTTPS;
@synthesize allowSelfSigned;
@synthesize useTLSAuth;
@synthesize serverType;

enum {
    kMPMasterServer = 0,
    kMPDistributionServer = 1,
    kMPProxyServer = 2
};
typedef NSUInteger MPServerType;


+ (MPNetServer *)serverObjectWithDictionary:(NSDictionary *)dict
{
    MPNetServer *instance = [[MPNetServer alloc] initWithDictionary:dict];
    return instance;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        self.host = @"localhost";
        self.port = 2600;
        self.useHTTPS = YES;
        self.allowSelfSigned = NO;
        self.useTLSAuth = NO;
        self.serverType = 1; //Distribution Server
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    self = [super init];

    // This check serves to make sure that a non-NSDictionary object
    // passed into the model class doesn't break the parsing.
    if(self && [dict isKindOfClass:[NSDictionary class]]) {
        self.host = [self objectOrNilForKey:@"host" fromDictionary:dict];
        self.port = [[self objectOrNilForKey:@"port" fromDictionary:dict] integerValue];
        self.useHTTPS = [[self objectOrNilForKey:@"useHTTPS" fromDictionary:dict] boolValue];
        self.allowSelfSigned = [[self objectOrNilForKey:@"allowSelfSigned" fromDictionary:dict] boolValue];
        self.useTLSAuth = [[self objectOrNilForKey:@"useTLSAuth" fromDictionary:dict] boolValue];
        self.serverType = [[self objectOrNilForKey:@"serverType" fromDictionary:dict] integerValue];
    }

    return self;
}

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict
{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? nil : object;
}

- (NSDictionary *)serverAsDictionary
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [d setObject:self.host forKey:@"host"];
    [d setObject:[NSNumber numberWithInt:(int)self.port] forKey:@"port"];
    [d setObject:[NSNumber numberWithBool:self.useHTTPS] forKey:@"useHTTPS"];
    [d setObject:[NSNumber numberWithBool:self.allowSelfSigned] forKey:@"allowSelfSigned"];
    [d setObject:[NSNumber numberWithBool:self.useTLSAuth] forKey:@"useTLSAuth"];
    [d setObject:[NSNumber numberWithInt:(int)self.serverType] forKey:@"serverType"];
    return [NSDictionary dictionaryWithDictionary:d];
}

@end
