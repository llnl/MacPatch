//
//  SWInstallItem.m
//
//  Created by   on 12/16/14
//  Copyright (c) 2014 __MyCompanyName__. All rights reserved.
//

#import "SWInstallItem.h"


NSString *const kSWInstallItemSwuuid = @"swuuid";
NSString *const kSWInstallItemMdate = @"mdate";
NSString *const kSWInstallItemName = @"name";
NSString *const kSWInstallItemHasUninstall = @"hasUninstall";
NSString *const kSWInstallItemJsonData = @"jsonData";


@interface SWInstallItem ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation SWInstallItem

@synthesize swuuid = _swuuid;
@synthesize mdate = _mdate;
@synthesize name = _name;
@synthesize hasUninstall = _hasUninstall;
@synthesize jsonData = _jsonData;


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
            self.swuuid = [self objectOrNilForKey:kSWInstallItemSwuuid fromDictionary:dict];
            self.mdate = [self objectOrNilForKey:kSWInstallItemMdate fromDictionary:dict];
            self.name = [self objectOrNilForKey:kSWInstallItemName fromDictionary:dict];
            self.hasUninstall = [[self objectOrNilForKey:kSWInstallItemHasUninstall fromDictionary:dict] doubleValue];
            self.jsonData = [self objectOrNilForKey:kSWInstallItemJsonData fromDictionary:dict];

    }
    
    return self;
    
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
    [mutableDict setValue:self.swuuid forKey:kSWInstallItemSwuuid];
    [mutableDict setValue:self.mdate forKey:kSWInstallItemMdate];
    [mutableDict setValue:self.name forKey:kSWInstallItemName];
    [mutableDict setValue:[NSNumber numberWithDouble:self.hasUninstall] forKey:kSWInstallItemHasUninstall];
    [mutableDict setValue:self.jsonData forKey:kSWInstallItemJsonData];

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

    self.swuuid = [aDecoder decodeObjectForKey:kSWInstallItemSwuuid];
    self.mdate = [aDecoder decodeObjectForKey:kSWInstallItemMdate];
    self.name = [aDecoder decodeObjectForKey:kSWInstallItemName];
    self.hasUninstall = [aDecoder decodeDoubleForKey:kSWInstallItemHasUninstall];
    self.jsonData = [aDecoder decodeObjectForKey:kSWInstallItemJsonData];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{

    [aCoder encodeObject:_swuuid forKey:kSWInstallItemSwuuid];
    [aCoder encodeObject:_mdate forKey:kSWInstallItemMdate];
    [aCoder encodeObject:_name forKey:kSWInstallItemName];
    [aCoder encodeDouble:_hasUninstall forKey:kSWInstallItemHasUninstall];
    [aCoder encodeObject:_jsonData forKey:kSWInstallItemJsonData];
}

- (id)copyWithZone:(NSZone *)zone
{
    SWInstallItem *copy = [[SWInstallItem alloc] init];
    
    if (copy) {

        copy.swuuid = [self.swuuid copyWithZone:zone];
        copy.mdate = [self.mdate copyWithZone:zone];
        copy.name = [self.name copyWithZone:zone];
        copy.hasUninstall = self.hasUninstall;
        copy.jsonData = [self.jsonData copyWithZone:zone];
    }
    
    return copy;
}


@end
