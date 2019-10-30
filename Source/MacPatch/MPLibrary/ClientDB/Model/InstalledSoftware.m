//
//  InstalledSoftware.m
//  FMDBme
//
//  Created by Charles Heizer on 10/24/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import "InstalledSoftware.h"

NSString *const kSWItemID = @"id";
NSString *const kSWItemName = @"name";
NSString *const kSWItemSUUID = @"suuid";
NSString *const kSWItemTUUID = @"tuuid";
NSString *const kSWItemUninstall = @"uninstall";
NSString *const kSWItemHasUninstall = @"has_uninstall";
NSString *const kSWItemJsonData = @"json_data";
NSString *const kSWItemInstallDate = @"install_date";


@interface InstalledSoftware ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation InstalledSoftware

@synthesize id = _id;
@synthesize name = _name;
@synthesize suuid = _suuid;
@synthesize tuuid = _tuuid;
@synthesize uninstall = _uninstall;
@synthesize has_uninstall = _has_uninstall;
@synthesize json_data = _json_data;
@synthesize install_date = _install_date;

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
		self.id = [self objectOrNilForKey:kSWItemID fromDictionary:dict];
		self.name = [self objectOrNilForKey:kSWItemName fromDictionary:dict];
		self.suuid = [self objectOrNilForKey:kSWItemSUUID fromDictionary:dict];
		self.tuuid = [self objectOrNilForKey:kSWItemTUUID fromDictionary:dict];
		self.uninstall = [self objectOrNilForKey:kSWItemUninstall fromDictionary:dict];
		self.has_uninstall = [[self objectOrNilForKey:kSWItemHasUninstall fromDictionary:dict] integerValue];
		self.json_data = [self objectOrNilForKey:kSWItemJsonData fromDictionary:dict];
		self.install_date = [self objectOrNilForKey:kSWItemInstallDate fromDictionary:dict];
    }
    
    return self;
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
	[mutableDict setValue:self.id forKey:kSWItemID];
	[mutableDict setValue:self.name forKey:kSWItemName];
	[mutableDict setValue:self.suuid forKey:kSWItemSUUID];
	[mutableDict setValue:self.tuuid forKey:kSWItemTUUID];
	[mutableDict setValue:self.uninstall forKey:kSWItemUninstall];
	[mutableDict setValue:[NSNumber numberWithLong:self.has_uninstall] forKey:kSWItemHasUninstall];
	[mutableDict setValue:self.json_data forKey:kSWItemJsonData];
	[mutableDict setValue:self.install_date forKey:kSWItemInstallDate];

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

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (!self) {
        return nil;
    }

	self.id = [decoder decodeObjectForKey:kSWItemID];
	self.name = [decoder decodeObjectForKey:kSWItemName];
	self.suuid = [decoder decodeObjectForKey:kSWItemSUUID];
	self.tuuid = [decoder decodeObjectForKey:kSWItemTUUID];
	self.uninstall = [decoder decodeObjectForKey:kSWItemUninstall];
	self.has_uninstall = [decoder decodeIntegerForKey:kSWItemHasUninstall];
	self.json_data = [decoder decodeObjectForKey:kSWItemJsonData];
	self.install_date = [decoder decodeObjectForKey:kSWItemInstallDate];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[encoder encodeObject:self.id forKey:kSWItemID];
	[encoder encodeObject:self.name forKey:kSWItemName];
	[encoder encodeObject:self.suuid forKey:kSWItemSUUID];
	[encoder encodeObject:self.tuuid forKey:kSWItemTUUID];
	[encoder encodeObject:self.uninstall forKey:kSWItemUninstall];
	[encoder encodeInteger:self.has_uninstall forKey:kSWItemHasUninstall];
	[encoder encodeObject:self.json_data forKey:kSWItemJsonData];
	[encoder encodeObject:self.install_date forKey:kSWItemInstallDate];
}

- (id)copyWithZone:(NSZone *)zone
{
    InstalledSoftware *copy = [[InstalledSoftware alloc] init];
    
    if (copy)
	{
        copy.id = [self.id copyWithZone:zone];
        copy.name = self.name;
        copy.suuid = [self.suuid copyWithZone:zone];
        copy.tuuid = [self.tuuid copyWithZone:zone];
        copy.uninstall = [self.uninstall copyWithZone:zone];
        copy.has_uninstall = self.has_uninstall;
		copy.json_data = [self.json_data copyWithZone:zone];
		copy.install_date = [self.install_date copyWithZone:zone];
    }
    
    return copy;
}

@end
