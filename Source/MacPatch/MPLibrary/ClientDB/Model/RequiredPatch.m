//
//  RequiredPatch.m
//  FMDBme
//
//  Created by Charles Heizer on 10/25/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import "RequiredPatch.h"

NSString *const kPatchItemID		= @"id";
NSString *const kPatchItemType 		= @"type";
NSString *const kPatchItemPatchID 	= @"patch_id";
NSString *const kPatchItemPatch 	= @"patch";
NSString *const kPatchItemVersion 	= @"patch_version";
NSString *const kPatchItemReboot 	= @"patch_reboot";
NSString *const kPatchItemData 		= @"patch_data";
NSString *const kPatchItemScanDate 	= @"patch_scandate";


@interface RequiredPatch ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation RequiredPatch

@synthesize id = _id;
@synthesize type = _type;
@synthesize patch_id = _patch_id;
@synthesize patch = _patch;
@synthesize patch_version = _patch_version;
@synthesize patch_reboot = _patch_reboot;
@synthesize patch_data = _patch_data;
@synthesize patch_scandate = _patch_scandate;


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
		self.id = [self objectOrNilForKey:kPatchItemID fromDictionary:dict];
		self.type = [self objectOrNilForKey:kPatchItemType fromDictionary:dict];
		self.patch_id = [self objectOrNilForKey:kPatchItemPatchID fromDictionary:dict];
		self.patch = [self objectOrNilForKey:kPatchItemPatch fromDictionary:dict];
		self.patch_version = [self objectOrNilForKey:kPatchItemVersion fromDictionary:dict];
		self.patch_reboot = [[self objectOrNilForKey:kPatchItemReboot fromDictionary:dict] integerValue];
		self.patch_data = [self objectOrNilForKey:kPatchItemData fromDictionary:dict];
		self.patch_scandate = [self objectOrNilForKey:kPatchItemScanDate fromDictionary:dict];
    }
    
    return self;
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
	[mutableDict setValue:self.id forKey:kPatchItemID];
	[mutableDict setValue:self.type forKey:kPatchItemType];
	[mutableDict setValue:self.patch_id forKey:kPatchItemPatchID];
	[mutableDict setValue:self.patch forKey:kPatchItemPatch];
	[mutableDict setValue:self.patch_version forKey:kPatchItemVersion];
	[mutableDict setValue:[NSNumber numberWithLong:self.patch_reboot] forKey:kPatchItemReboot];
	[mutableDict setValue:self.patch_data forKey:kPatchItemData];
	[mutableDict setValue:self.patch_scandate forKey:kPatchItemScanDate];
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
	
	self.id = [decoder decodeObjectForKey:kPatchItemID];
	self.type = [decoder decodeObjectForKey:kPatchItemType];
	self.patch_id = [decoder decodeObjectForKey:kPatchItemPatchID];
	self.patch =[decoder decodeObjectForKey:kPatchItemPatch];
	self.patch_version = [decoder decodeObjectForKey:kPatchItemVersion];
	self.patch_reboot = [decoder decodeIntegerForKey:kPatchItemReboot];
	self.patch_data = [decoder decodeObjectForKey:kPatchItemData];
	self.patch_scandate = [decoder decodeObjectForKey:kPatchItemScanDate];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[encoder encodeObject:self.id forKey:kPatchItemID];
	[encoder encodeObject:self.type forKey:kPatchItemType];
	[encoder encodeObject:self.patch_id forKey:kPatchItemPatchID];
	[encoder encodeObject:self.patch forKey:kPatchItemPatch];
	[encoder encodeObject:self.patch_version forKey:kPatchItemVersion];
	[encoder encodeInteger:self.patch_reboot forKey:kPatchItemReboot];
	[encoder encodeObject:self.patch_data forKey:kPatchItemData];
	[encoder encodeObject:self.patch_scandate forKey:kPatchItemScanDate];
}

- (id)copyWithZone:(NSZone *)zone
{
    RequiredPatch *copy = [[RequiredPatch alloc] init];
    
    if (copy)
	{
        copy.id = [self.id copyWithZone:zone];
        copy.type = [self.type copyWithZone:zone];
        copy.patch_id = [self.patch_id copyWithZone:zone];
        copy.patch = [self.patch copyWithZone:zone];
        copy.patch_version = [self.patch_version copyWithZone:zone];
        copy.patch_reboot = self.patch_reboot;
		copy.patch_data = [self.patch_data copyWithZone:zone];
		copy.patch_scandate = [self.patch_scandate copyWithZone:zone];
    }
    
    return copy;
}

@end
