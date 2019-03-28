//
//  MPCustomPatch.m
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

#import "MPCustomPatch.h"

@interface MPCustomPatch ()

@property (nonatomic, strong, readwrite) NSString *type;

@end

@implementation MPCustomPatch

@synthesize cuuid;
@synthesize patch;
@synthesize type;
@synthesize patchDescription;
@synthesize size;
@synthesize recommended;
@synthesize restart;
@synthesize version;
@synthesize patch_id;
@synthesize bundleID;

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
		//self.patchDescription 	= [self objectOrNilForKey:@"description" fromDictionary:dict];
		self.patchDescription 	= [self objectOrNilForKey:@"patch" fromDictionary:dict];
		self.size 			= [self objectOrNilForKey:@"size" fromDictionary:dict];
		self.recommended 	= [self objectOrNilForKey:@"recommended" fromDictionary:dict];
		self.restart	 	= [self objectOrNilForKey:@"restart" fromDictionary:dict];
		self.version	 	= [self objectOrNilForKey:@"version" fromDictionary:dict];
		self.patch_id	 	= [self objectOrNilForKey:@"patch_id" fromDictionary:dict];
		self.bundleID		= [self objectOrNilForKey:@"bundleID" fromDictionary:dict];
		
		[self setType:@"Third"];
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
        [self setType:@"Third"];
		[self setPatchDescription:@""];
        [self setSize:@"0"];
        [self setRecommended:@"Y"];
        [self setRestart:@""];
        [self setVersion:@""];
        [self setPatch_id:@""];
        [self setBundleID:@""];
    }
    return self;
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

- (NSDictionary *)patchAsDictionary
{
    // cuuid, patch, type, description, size, recommended, restart, patch_id, version, bundleID
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:self.cuuid forKey:@"cuuid"];
    [p setObject:self.patch forKey:@"patch"];
    [p setObject:self.type forKey:@"type"];
    [p setObject:self.patchDescription forKey:@"patchDescription"];
    [p setObject:self.size forKey:@"size"];
    [p setObject:self.recommended forKey:@"recommended"];
    [p setObject:self.restart forKey:@"restart"];
    [p setObject:self.version forKey:@"version"];
    [p setObject:self.patch_id forKey:@"patch_id"];
    [p setObject:self.bundleID forKey:@"bundleID"];
    return [NSDictionary dictionaryWithDictionary:p];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	
	self.cuuid			= [aDecoder decodeObjectForKey:@"cuuid"];
	self.patch			= [aDecoder decodeObjectForKey:@"patch"];
	self.patchDescription 	= [aDecoder decodeObjectForKey:@"patchDescription"];
	self.size 			= [aDecoder decodeObjectForKey:@"size"];
	self.recommended 	= [aDecoder decodeObjectForKey:@"recommended"];
	self.restart	 	= [aDecoder decodeObjectForKey:@"restart"];
	self.version	 	= [aDecoder decodeObjectForKey:@"version"];
	self.patch_id	 	= [aDecoder decodeObjectForKey:@"patch_id"];
	self.bundleID	 	= [aDecoder decodeObjectForKey:@"bundleID"];
	self.type			= [aDecoder decodeObjectForKey:@"type"];
	
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:self.cuuid forKey:@"cuuid"];
	[aCoder encodeObject:self.patch forKey:@"patch"];
	[aCoder encodeObject:self.patchDescription forKey:@"patchDescription"];
	[aCoder encodeObject:self.size forKey:@"size"];
	[aCoder encodeObject:self.recommended forKey:@"recommended"];
	[aCoder encodeObject:self.restart forKey:@"restart"];
	[aCoder encodeObject:self.version forKey:@"version"];
	[aCoder encodeObject:self.patch_id forKey:@"patch_id"];
	[aCoder encodeObject:self.bundleID forKey:@"bundleID"];
	[aCoder encodeObject:self.type forKey:@"type"];
}

- (id)copyWithZone:(NSZone *)zone
{
	MPCustomPatch *copy = [[MPCustomPatch alloc] init];
	if (copy)
	{
		copy.cuuid 			= [self.cuuid copyWithZone:zone];
		copy.patch 			= [self.patch copyWithZone:zone];
		copy.patchDescription 	= [self.patchDescription copyWithZone:zone];
		copy.size 			= [self.size copyWithZone:zone];
		copy.recommended 	= [self.recommended copyWithZone:zone];
		copy.restart 		= [self.restart copyWithZone:zone];
		copy.version 		= [self.version copyWithZone:zone];
		copy.patch_id 		= [self.patch_id copyWithZone:zone];
		copy.bundleID 		= [self.bundleID copyWithZone:zone];
		copy.type 			= [self.type copyWithZone:zone];
	}
	return copy;
}


@end
