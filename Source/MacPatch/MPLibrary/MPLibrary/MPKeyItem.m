//
//  MPKeyItem.m
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

#import "MPKeyItem.h"

NSString *const kRootClassPrivateKey = @"privateKey";
NSString *const kRootClassPublicKey = @"publicKey";
NSString *const kRootClassSecret = @"secret";

@interface MPKeyItem ()
@end

@implementation MPKeyItem

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    self = [super init];
    
    if(![dictionary[kRootClassPrivateKey] isKindOfClass:[NSNull class]]){
        self.privateKey = dictionary[kRootClassPrivateKey];
    }
    
    if(![dictionary[kRootClassPublicKey] isKindOfClass:[NSNull class]]){
        self.publicKey = dictionary[kRootClassPublicKey];
    }
    
    if(![dictionary[kRootClassSecret] isKindOfClass:[NSNull class]]){
        self.secret = dictionary[kRootClassSecret];
    }
    
    return self;
}

- (NSDictionary *)toDictionary
{
    NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
    if(self.privateKey != nil){
        dictionary[kRootClassPrivateKey] = self.privateKey;
    }
    if(self.publicKey != nil){
        dictionary[kRootClassPublicKey] = self.publicKey;
    }
    if(self.secret != nil){
        dictionary[kRootClassSecret] = self.secret;
    }
    return dictionary;
    
}

/*
  Implementation of NSCoding encoding method
*/
- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if(self.privateKey != nil){
        [aCoder encodeObject:self.privateKey forKey:kRootClassPrivateKey];
    }
    if(self.publicKey != nil){
        [aCoder encodeObject:self.publicKey forKey:kRootClassPublicKey];
    }
    if(self.secret != nil){
        [aCoder encodeObject:self.secret forKey:kRootClassSecret];
    }
    
}

/*
  Implementation of NSCoding initWithCoder: method
*/
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    self.privateKey = [aDecoder decodeObjectForKey:kRootClassPrivateKey];
    self.publicKey = [aDecoder decodeObjectForKey:kRootClassPublicKey];
    self.secret = [aDecoder decodeObjectForKey:kRootClassSecret];
    return self;
    
}

/*
  Implementation of NSCopying copyWithZone: method
*/
- (instancetype)copyWithZone:(NSZone *)zone
{
    MPKeyItem *copy = [MPKeyItem new];
    
    copy.privateKey = [self.privateKey copy];
    copy.publicKey = [self.publicKey copy];
    copy.secret = [self.secret copy];
    
    return copy;
}
@end
