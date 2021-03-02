//
//	Suserver.m
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "Suserver.h"

NSString *const kSuserverCatalogURL     = @"CatalogURL";
NSString *const kSuserverOsmajor        = @"osmajor";
NSString *const kSuserverOsminor        = @"osminor";
NSString *const kSuserverServerType     = @"serverType";

@interface Suserver ()
@end

@implementation Suserver

/**
 * Instantiate the instance using the passed dictionary values to set the properties values
 */

-(instancetype)initWithDictionary:(NSDictionary *)dictionary
{
	self = [super init];
	if(![dictionary[kSuserverCatalogURL] isKindOfClass:[NSNull class]]){
		self.catalogURL = dictionary[kSuserverCatalogURL];
	}

	if(![dictionary[kSuserverOsmajor] isKindOfClass:[NSNull class]]){
		self.osmajor = [dictionary[kSuserverOsmajor] integerValue];
	}

	if(![dictionary[kSuserverOsminor] isKindOfClass:[NSNull class]]){
		self.osminor = [dictionary[kSuserverOsminor] integerValue];
	}

	if(![dictionary[kSuserverServerType] isKindOfClass:[NSNull class]]){
		self.serverType = [dictionary[kSuserverServerType] integerValue];
	}

	return self;
}


/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
-(NSDictionary *)toDictionary
{
	NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
	if(self.catalogURL != nil){
		dictionary[kSuserverCatalogURL] = self.catalogURL;
	}
	dictionary[kSuserverOsmajor] = @(self.osmajor);
	dictionary[kSuserverOsminor] = @(self.osminor);
	dictionary[kSuserverServerType] = @(self.serverType);
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
	if(self.catalogURL != nil){
		[aCoder encodeObject:self.catalogURL forKey:kSuserverCatalogURL];
	}
	[aCoder encodeObject:@(self.osmajor) forKey:kSuserverOsmajor];
    [aCoder encodeObject:@(self.osminor) forKey:kSuserverOsminor];
    [aCoder encodeObject:@(self.serverType) forKey:kSuserverServerType];
}

/**
 * Implementation of NSCoding initWithCoder: method
 */
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	self.catalogURL = [aDecoder decodeObjectForKey:kSuserverCatalogURL];
	self.osmajor = [[aDecoder decodeObjectForKey:kSuserverOsmajor] integerValue];
	self.osminor = [[aDecoder decodeObjectForKey:kSuserverOsminor] integerValue];
	self.serverType = [[aDecoder decodeObjectForKey:kSuserverServerType] integerValue];
	return self;

}

/**
 * Implementation of NSCopying copyWithZone: method
 */
- (instancetype)copyWithZone:(NSZone *)zone
{
	Suserver *copy = [Suserver new];

	copy.catalogURL = [self.catalogURL copy];
	copy.osmajor = self.osmajor;
	copy.osminor = self.osminor;
	copy.serverType = self.serverType;

	return copy;
}
@end
