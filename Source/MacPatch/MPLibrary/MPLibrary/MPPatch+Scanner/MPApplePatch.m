//
//  MPApplePatch.m
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

#import "MPApplePatch.h"

@interface MPApplePatch ()

@property (nonatomic, strong, readwrite) NSString *type;

@end

@implementation MPApplePatch

@synthesize cuuid;
@synthesize patch;
@synthesize type;
@synthesize description;
@synthesize size;
@synthesize recommended;
@synthesize restart;
@synthesize version;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict
{
	return [[self alloc] initWithDictionary:dict];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
	self = [super init];
	
	// This check serves to make sure that a non-NSDictionary object
	// passed into the model class doesn't break the parsing.
	if(self && [dict isKindOfClass:[NSDictionary class]])
	{
		self.cuuid			= [self objectOrNilForKey:@"cuuid" fromDictionary:dict];
		self.patch			= [self objectOrNilForKey:@"patch" fromDictionary:dict];
		self.description 	= [self objectOrNilForKey:@"description" fromDictionary:dict];
		self.size 			= [self objectOrNilForKey:@"size" fromDictionary:dict];
		self.recommended 	= [self objectOrNilForKey:@"recommended" fromDictionary:dict];
		self.restart	 	= [self objectOrNilForKey:@"restart" fromDictionary:dict];
		self.version	 	= [self objectOrNilForKey:@"version" fromDictionary:dict];
		[self setType:@"Apple"];
	}
	
	return self;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        [self setCuuid:@""];
        [self setPatch:@""];
        [self setDescription:@""];
        [self setSize:@""];
        [self setRecommended:@""];
        [self setRestart:@""];
        [self setVersion:@""];
		[self setType:@"Apple"];
    }
    return self;
}

- (NSDictionary *)patchAsDictionary
{
    // cuuid, patch, type, description, size, recommended, restart, version
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:self.cuuid forKey:@"cuuid"];
    [p setObject:self.patch forKey:@"patch"];
    [p setObject:self.type forKey:@"type"];
    [p setObject:self.description forKey:@"description"];
    [p setObject:self.size forKey:@"size"];
    [p setObject:self.recommended forKey:@"recommended"];
    [p setObject:self.restart forKey:@"restart"];
    [p setObject:self.version forKey:@"version"];
	
    return [NSDictionary dictionaryWithDictionary:p];
}

#pragma mark - Helper Method
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict
{
	return [self objectOrNilForKey:aKey defaultValue:@"NA" fromDictionary:dict];
}

- (id)objectOrNilForKey:(id)aKey defaultValue:(NSString *)defaultValue fromDictionary:(NSDictionary *)dict
{
	id object = [dict objectForKey:aKey];
	
	NSString *_default = @"NA";
	if (defaultValue != NULL) {
		_default = defaultValue;
	}
	
	if (!object) {
		return _default;
	}
	
	return [object isEqual:[NSNull null]] ? _default : object;
}

#pragma mark - NSCoding Methods

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	
	self.cuuid			= [aDecoder decodeObjectForKey:@"cuuid"];
	self.patch			= [aDecoder decodeObjectForKey:@"patch"];
	self.description 	= [aDecoder decodeObjectForKey:@"description"];
	self.size 			= [aDecoder decodeObjectForKey:@"size"];
	self.recommended 	= [aDecoder decodeObjectForKey:@"recommended"];
	self.restart	 	= [aDecoder decodeObjectForKey:@"restart"];
	self.version	 	= [aDecoder decodeObjectForKey:@"version"];
	self.type			= [aDecoder decodeObjectForKey:@"type"];
	
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:self.cuuid forKey:@"cuuid"];
	[aCoder encodeObject:self.patch forKey:@"patch"];
	[aCoder encodeObject:self.description forKey:@"description"];
	[aCoder encodeObject:self.size forKey:@"size"];
	[aCoder encodeObject:self.recommended forKey:@"recommended"];
	[aCoder encodeObject:self.restart forKey:@"restart"];
	[aCoder encodeObject:self.version forKey:@"version"];
	[aCoder encodeObject:self.type forKey:@"type"];
}

- (id)copyWithZone:(NSZone *)zone
{
	MPApplePatch *copy = [[MPApplePatch alloc] init];
	if (copy)
	{
		copy.cuuid 			= [self.cuuid copyWithZone:zone];
		copy.patch 			= [self.patch copyWithZone:zone];
		copy.description 	= [self.description copyWithZone:zone];
		copy.size 			= [self.size copyWithZone:zone];
		copy.recommended 	= [self.recommended copyWithZone:zone];
		copy.restart 		= [self.restart copyWithZone:zone];
		copy.version 		= [self.version copyWithZone:zone];
		copy.type 			= [self.type copyWithZone:zone];
	}
	return copy;
}
@end
