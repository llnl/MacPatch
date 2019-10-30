//
//  History.m
//  FMDBme
//
//  Created by Charles Heizer on 10/23/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import "History.h"

NSString *const kHistoryID = @"id";
NSString *const kHistoryType = @"type";
NSString *const kHistoryName = @"name";
NSString *const kHistoryUUID = @"uuid";
NSString *const kHistoryAction = @"action";
NSString *const kHistoryResultCode = @"result_code";
NSString *const kHistoryErrorMsg = @"errorMsg";
NSString *const kHistoryCDate = @"cdate";


@interface History ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation History

@synthesize id = _id;
@synthesize type = _type;
@synthesize name = _name;
@synthesize uuid = _uuid;
@synthesize action = _action;
@synthesize result_code = _result_code;
@synthesize error_msg = _error_msg;
@synthesize cdate = _cdate;

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
		self.id = [self objectOrNilForKey:kHistoryID fromDictionary:dict];
		self.type = [[self objectOrNilForKey:kHistoryType fromDictionary:dict] intValue];
		self.name = [self objectOrNilForKey:kHistoryName fromDictionary:dict];
		self.uuid = [self objectOrNilForKey:kHistoryUUID fromDictionary:dict];
		self.action = [self objectOrNilForKey:kHistoryAction fromDictionary:dict];
		self.result_code = [[self objectOrNilForKey:kHistoryResultCode fromDictionary:dict] intValue];
		self.error_msg = [self objectOrNilForKey:kHistoryErrorMsg fromDictionary:dict];
		self.cdate = [self objectOrNilForKey:kHistoryCDate fromDictionary:dict];
    }
    
    return self;
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
	[mutableDict setValue:self.id forKey:kHistoryID];
	[mutableDict setValue:[NSNumber numberWithLong:self.type] forKey:kHistoryType];
	[mutableDict setValue:self.name forKey:kHistoryName];
	[mutableDict setValue:self.uuid forKey:kHistoryUUID];
	[mutableDict setValue:self.action forKey:kHistoryAction];
	[mutableDict setValue:[NSNumber numberWithLong:self.result_code] forKey:kHistoryResultCode];
	[mutableDict setValue:self.error_msg forKey:kHistoryErrorMsg];
	[mutableDict setValue:self.cdate forKey:kHistoryCDate];

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

	self.id = [decoder decodeObjectForKey:kHistoryID];
	self.type = [decoder decodeIntegerForKey:kHistoryType];
	self.name = [decoder decodeObjectForKey:kHistoryName];
	self.uuid = [decoder decodeObjectForKey:kHistoryUUID];
	self.action = [decoder decodeObjectForKey:kHistoryAction];
	self.result_code = [decoder decodeIntegerForKey:kHistoryResultCode];
	self.error_msg = [decoder decodeObjectForKey:kHistoryErrorMsg];
	self.cdate = [decoder decodeObjectForKey:kHistoryCDate];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	[encoder encodeObject:self.id forKey:kHistoryID];
	[encoder encodeInteger:self.type forKey:kHistoryType];
	[encoder encodeObject:self.name forKey:kHistoryName];
	[encoder encodeObject:self.uuid forKey:kHistoryUUID];
	[encoder encodeObject:self.action forKey:kHistoryAction];
	[encoder encodeInteger:self.result_code forKey:kHistoryResultCode];
	[encoder encodeObject:self.error_msg forKey:kHistoryErrorMsg];
	[encoder encodeObject:self.cdate forKey:kHistoryCDate];
}

- (id)copyWithZone:(NSZone *)zone
{
    History *copy = [[History alloc] init];
    
    if (copy)
	{
        copy.id = [self.id copyWithZone:zone];
        copy.type = self.type;
        copy.name = [self.name copyWithZone:zone];
        copy.uuid = [self.uuid copyWithZone:zone];
        copy.action = [self.action copyWithZone:zone];
        copy.result_code = self.result_code;
		copy.error_msg = [self.error_msg copyWithZone:zone];
		copy.cdate = [self.cdate copyWithZone:zone];
    }
    
    return copy;
}
@end
