//
//  HistoryItem.m
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

#import "HistoryItem.h"

NSString *const kHistoryItemErrorcode = @"errorcode";
NSString *const kHistoryItemMdate = @"mdate";
NSString *const kHistoryItemRawdata = @"rawdata";
NSString *const kHistoryItemType = @"type";
NSString *const kHistoryItemName = @"name";
NSString *const kHistoryItemAction = @"action";

@interface HistoryItem ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation HistoryItem

@synthesize errorcode = _errorcode;
@synthesize mdate = _mdate;
@synthesize rawdata = _rawdata;
@synthesize type = _type;
@synthesize name = _name;
@synthesize action = _action;


+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict
{
    return [[self alloc] initWithDictionary:dict];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    self = [super init];
    
    // This check serves to make sure that a non-NSDictionary object
    // passed into the model class doesn't break the parsing.
    if(self && [dict isKindOfClass:[NSDictionary class]]) {
            self.errorcode = [[self objectOrNilForKey:kHistoryItemErrorcode fromDictionary:dict] intValue];
            self.mdate = [self objectOrNilForKey:kHistoryItemMdate fromDictionary:dict];
            self.rawdata = [self objectOrNilForKey:kHistoryItemRawdata fromDictionary:dict];
            self.type = [self objectOrNilForKey:kHistoryItemType fromDictionary:dict];
            self.name = [self objectOrNilForKey:kHistoryItemName fromDictionary:dict];
            self.action = [[self objectOrNilForKey:kHistoryItemAction fromDictionary:dict] intValue];

    }
    
    return self;
    
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
    [mutableDict setValue:[NSNumber numberWithInt:self.errorcode] forKey:kHistoryItemErrorcode];
    [mutableDict setValue:self.mdate forKey:kHistoryItemMdate];
    [mutableDict setValue:self.rawdata forKey:kHistoryItemRawdata];
    [mutableDict setValue:self.type forKey:kHistoryItemType];
    [mutableDict setValue:self.name forKey:kHistoryItemName];
    [mutableDict setValue:[NSNumber numberWithInt:self.action] forKey:kHistoryItemAction];

    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (NSString *)description 
{
    return [NSString stringWithFormat:@"%@", [self dictionaryRepresentation]];
}

#pragma mark - Helper Method
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict
{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? nil : object;
}


#pragma mark - NSCoding Methods

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];

    self.errorcode = [aDecoder decodeIntForKey:kHistoryItemErrorcode];
    self.mdate = [aDecoder decodeObjectForKey:kHistoryItemMdate];
    self.rawdata = [aDecoder decodeObjectForKey:kHistoryItemRawdata];
    self.type = [aDecoder decodeObjectForKey:kHistoryItemType];
    self.name = [aDecoder decodeObjectForKey:kHistoryItemName];
    self.action = [aDecoder decodeIntForKey:kHistoryItemAction];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{

    [aCoder encodeInt:_errorcode forKey:kHistoryItemErrorcode];
    [aCoder encodeObject:_mdate forKey:kHistoryItemMdate];
    [aCoder encodeObject:_rawdata forKey:kHistoryItemRawdata];
    [aCoder encodeObject:_type forKey:kHistoryItemType];
    [aCoder encodeObject:_name forKey:kHistoryItemName];
    [aCoder encodeInt:_action forKey:kHistoryItemAction];
}

- (id)copyWithZone:(NSZone *)zone
{
    HistoryItem *copy = [[HistoryItem alloc] init];
    
    if (copy) {

        copy.errorcode = self.errorcode;
        copy.mdate = [self.mdate copyWithZone:zone];
        copy.rawdata = [self.rawdata copyWithZone:zone];
        copy.type = [self.type copyWithZone:zone];
        copy.name = [self.name copyWithZone:zone];
        copy.action = self.action;
    }
    
    return copy;
}


@end
