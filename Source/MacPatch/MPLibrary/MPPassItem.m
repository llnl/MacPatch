//
//  MPPassItem.m
/*
Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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

#import "MPPassItem.h"

NSString *const kMPUserName = @"userName";
NSString *const kMPUserPass = @"userPass";

@implementation MPPassItem

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    self = [super init];
    
    if(![dictionary[kMPUserName] isKindOfClass:[NSNull class]]){
        self.userName = dictionary[kMPUserName];
    }
    
    if(![dictionary[kMPUserPass] isKindOfClass:[NSNull class]]){
        self.userPass = dictionary[kMPUserPass];
    }
    
    
    return self;
}

- (NSDictionary *)toDictionary
{
    NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
    if(self.userName != nil){
        dictionary[kMPUserName] = self.userName;
    }
	
    if(self.userPass != nil){
        dictionary[kMPUserPass] = self.userPass;
    }
    
    return dictionary;
}

/*
  Implementation of NSCoding encoding method
*/
- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if(self.userName != nil){
        [aCoder encodeObject:self.userName forKey:kMPUserName];
    }
    if(self.userPass != nil){
        [aCoder encodeObject:self.userPass forKey:kMPUserPass];
    }
}

/*
  Implementation of NSCoding initWithCoder: method
*/
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    self.userName = [aDecoder decodeObjectForKey:kMPUserName];
    self.userPass = [aDecoder decodeObjectForKey:kMPUserPass];
    return self;
}

/*
  Implementation of NSCopying copyWithZone: method
*/
- (instancetype)copyWithZone:(NSZone *)zone
{
    MPPassItem *copy = [MPPassItem new];
    
    copy.userName = [self.userName copy];
    copy.userPass = [self.userPass copy];
    
    return copy;
}

@end
