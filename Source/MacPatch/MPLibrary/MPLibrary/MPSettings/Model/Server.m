//
//	Server.m
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

#import "Server.h"


NSString *const kServerHostname         = @"host";
NSString *const kServerPort             = @"port";
NSString *const kServerUseSSL           = @"useHTTPS";
NSString *const kServerAllowSelfSigned  = @"allowSelfSigned";
NSString *const kServerIsMaster         = @"serverType";
NSString *const kServerIsProxy          = @"serverType";

NSString *const kServerUseclientcert    = @"useclientcert";


@interface Server ()
@end

@implementation Server

/**
 * Instantiate the instance using the passed dictionary values to set the properties values
 */

-(instancetype)initWithDictionary:(NSDictionary *)dictionary
{
	self = [super init];
	if(![dictionary[kServerHostname] isKindOfClass:[NSNull class]]){
		self.host = dictionary[kServerHostname];
	}
    
    if(![dictionary[kServerPort] isKindOfClass:[NSNull class]]){
        self.port = [dictionary[kServerPort] integerValue];
    }
    
    if(![dictionary[kServerUseSSL] isKindOfClass:[NSNull class]]){
        self.usessl = [dictionary[kServerUseSSL] integerValue];
    }
    
    if(![dictionary[kServerAllowSelfSigned] isKindOfClass:[NSNull class]]){
        self.allowSelfSigned = [dictionary[kServerAllowSelfSigned] integerValue];
    }

	if(![dictionary[kServerIsProxy] isKindOfClass:[NSNull class]]){
        if ([dictionary[kServerIsProxy] integerValue] == 2)
            self.isProxy = 1;
	}
    
    if(![dictionary[kServerIsMaster] isKindOfClass:[NSNull class]]){
        if ([dictionary[kServerIsMaster] integerValue] == 1)
            self.isMaster = 1;
    }

	if(![dictionary[kServerUseclientcert] isKindOfClass:[NSNull class]]){
		self.useclientcert = [dictionary[kServerUseclientcert] integerValue];
	}

	return self;
}


/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
-(NSDictionary *)toDictionary
{
	NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
	if(self.host != nil){
		dictionary[kServerHostname] = self.host;
	}
	
	dictionary[kServerPort] = @(self.port);
    dictionary[kServerUseSSL] = @(self.usessl);
    dictionary[kServerAllowSelfSigned] = @(self.allowSelfSigned);
	dictionary[kServerUseclientcert] = @(self.useclientcert);
    
    if (self.isMaster == 1) {
        dictionary[kServerIsMaster] = @(1);
    } else {
        dictionary[kServerIsMaster] = @(0);
    }
    
    if (self.isProxy == 1) {
        dictionary[kServerIsMaster] = @(2);
    } else {
        dictionary[kServerIsMaster] = @(0);
    }
	
	return dictionary;

}

/**
 * Implementation of NSCoding encoding method
 */
/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	if(self.host != nil){
		[aCoder encodeObject:self.host forKey:kServerHostname];
	}
    [aCoder encodeObject:@(self.port) forKey:kServerPort];
    [aCoder encodeObject:@(self.usessl) forKey:kServerUseSSL];
    [aCoder encodeObject:@(self.allowSelfSigned) forKey:kServerAllowSelfSigned];
	[aCoder encodeObject:@(self.isProxy) forKey:kServerIsProxy];
    [aCoder encodeObject:@(self.isMaster) forKey:kServerIsMaster];
    [aCoder encodeObject:@(self.useclientcert) forKey:kServerUseclientcert];
}

/**
 * Implementation of NSCoding initWithCoder: method
 */
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	self.host            = [aDecoder decodeObjectForKey:kServerHostname];
    self.port            = [[aDecoder decodeObjectForKey:kServerPort] integerValue];
    self.usessl          = [[aDecoder decodeObjectForKey:kServerUseSSL] integerValue];
    self.allowSelfSigned = [[aDecoder decodeObjectForKey:kServerAllowSelfSigned] integerValue];
	self.isProxy         = [[aDecoder decodeObjectForKey:kServerIsProxy] integerValue];
    self.isMaster        = [[aDecoder decodeObjectForKey:kServerIsMaster] integerValue];
	self.useclientcert = [[aDecoder decodeObjectForKey:kServerUseclientcert] integerValue];
	return self;
}

/**
 * Implementation of NSCopying copyWithZone: method
 */
- (instancetype)copyWithZone:(NSZone *)zone
{
	Server *copy = [Server new];
	copy.host = [self.host copy];
    copy.port = self.port;
    copy.usessl = self.usessl;
    copy.allowSelfSigned = self.allowSelfSigned;
	copy.isProxy = self.isProxy;
	copy.isMaster = self.isMaster;
	copy.useclientcert = self.useclientcert;
	return copy;
}
@end
