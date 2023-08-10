//
//  MPServerEntry.m
//  MPAgent
//
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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

#import "MPServerEntry.h"

static NSString *kHOST = @"host";
static NSString *kPORT = @"port";
static NSString *kSERVER_TYPE = @"serverType";
static NSString *kUSEHTTPS = @"useHTTPS";
static NSString *kUSETLSAUTH = @"useTLSAuth";
static NSString *kALLOWSELFSIGNED = @"allowSelfSigned";
static NSString *kORDER = @"order";

@implementation MPServerEntry

@synthesize host = _host;
@synthesize port = _port;
@synthesize serverType = _serverType;
@synthesize useHTTPS = _useHTTPS;
@synthesize useTLSAuth = _useTLSAuth;
@synthesize allowSelfSigned = _allowSelfSigned;
@synthesize order = _order;

- (id)init
{
    self = [super init];
    if (self)
    {
        self.host = @"NA";
        self.port = @"NA";
        self.serverType = @"NA";
        self.useHTTPS = @"NA";
        self.useTLSAuth = @"NA";
        self.allowSelfSigned = @"NA";
        self.order = @"999";
    }
    return self;
}

- (id)initWithServerDictionary:(NSDictionary *)aServerItem index:(NSString *)idx;
{
    self = [super init];
    if (self)
    {
        [self parseWithDictionary:aServerItem index:idx];
        [self setOrder:idx];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
    [mutableDict setValue:self.host forKeyPath:kHOST];
    [mutableDict setValue:self.port forKeyPath:kPORT];
    [mutableDict setValue:self.serverType forKeyPath:kSERVER_TYPE];
    [mutableDict setValue:self.useHTTPS forKeyPath:kUSEHTTPS];
    [mutableDict setValue:self.useTLSAuth forKeyPath:kUSETLSAUTH];
    [mutableDict setValue:self.allowSelfSigned forKeyPath:kALLOWSELFSIGNED];
    [mutableDict setValue:self.order forKey:kORDER];
    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (NSDictionary *)parseWithDictionary:(NSDictionary *)aDictionary index:(NSString *)idx
{
    if (!aDictionary) {
        return [self dictionaryRepresentation];
    }

    for (NSString *key in aDictionary.allKeys) {
        if ([key isEqualToString:@"host"]) {
            self.host = [aDictionary objectForKey:@"host"];
            continue;
        }
        if ([key isEqualToString:@"port"]) {
            self.port = [[aDictionary objectForKey:@"port"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"serverType"])
        {
            if ([[aDictionary objectForKey:@"serverType"] isKindOfClass:[NSString class]]) {
                self.serverType = [aDictionary objectForKey:@"serverType"];
            } else if ([[aDictionary objectForKey:@"serverType"] isKindOfClass:[NSNumber class]]) {
                self.serverType = [[aDictionary objectForKey:@"serverType"] stringValue];
            } else {
                self.serverType = @"ERR";
            }

            continue;
        }
        if ([key isEqualToString:@"useHTTPS"])
        {
            if ([[aDictionary objectForKey:@"useHTTPS"] isKindOfClass:[NSString class]]) {
                self.useHTTPS = [aDictionary objectForKey:@"useHTTPS"];
            } else if ([[aDictionary objectForKey:@"useHTTPS"] isKindOfClass:[NSNumber class]]) {
                self.useHTTPS = [[aDictionary objectForKey:@"useHTTPS"] stringValue];
            } else {
                self.useHTTPS = @"ERR";
            }
            continue;
        }
        if ([key isEqualToString:@"useTLSAuth"])
        {
            if ([[aDictionary objectForKey:@"useTLSAuth"] isKindOfClass:[NSString class]]) {
                self.useTLSAuth = [aDictionary objectForKey:@"useTLSAuth"];
            } else if ([[aDictionary objectForKey:@"useTLSAuth"] isKindOfClass:[NSNumber class]]) {
                self.useTLSAuth = [[aDictionary objectForKey:@"useTLSAuth"] stringValue];
            } else {
                self.useTLSAuth = @"ERR";
            }
            continue;
        }
        if ([key isEqualToString:@"allowSelfSigned"])
        {
            if ([[aDictionary objectForKey:@"allowSelfSigned"] isKindOfClass:[NSString class]]) {
                self.allowSelfSigned = [aDictionary objectForKey:@"allowSelfSigned"];
            } else if ([[aDictionary objectForKey:@"allowSelfSigned"] isKindOfClass:[NSNumber class]]) {
                self.allowSelfSigned = [[aDictionary objectForKey:@"allowSelfSigned"] stringValue];
            } else {
                self.allowSelfSigned = @"ERR";
            }
            continue;
        }
    }

    self.order = idx;
    return [self dictionaryRepresentation];
}

@end
