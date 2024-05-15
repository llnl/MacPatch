//
//  ConfigProfile.m
//  MPLibrary
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


#import "ConfigProfile.h"

NSString *const kProfileDisplayName  	= @"ProfileDisplayName";
NSString *const kProfileIdentifier      = @"ProfileIdentifier";
NSString *const kProfileInstallDate     = @"ProfileInstallDate";
NSString *const kProfileItems       	= @"ProfileItems";
NSString *const kProfileOrganization    = @"ProfileOrganization";
NSString *const kProfileType       		= @"ProfileType";
NSString *const kProfileUUID            = @"ProfileUUID";
NSString *const kProfileRemovalDisallowed = @"ProfileRemovalDisallowed";
NSString *const kProfileVerificationState = @"ProfileVerificationState";
NSString *const kProfileVersion  		= @"ProfileVersion";


@implementation ConfigProfile

/**
 * Instantiate the instance using the passed dictionary values to set the properties values
 */

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
	self = [super init];
	if(![dictionary[kProfileDisplayName] isKindOfClass:[NSNull class]]){
		self.displayName = dictionary[kProfileDisplayName];
	}
	
	if(![dictionary[kProfileIdentifier] isKindOfClass:[NSNull class]]){
		self.identifier = dictionary[kProfileIdentifier];
	}
	
	if(![dictionary[kProfileInstallDate] isKindOfClass:[NSNull class]]){
		self.installDate = [dictionary[kProfileInstallDate] stringByReplacingOccurrencesOfString:@" +0000" withString:@""];
	}
	
	if(![dictionary[kProfileItems] isKindOfClass:[NSNull class]]){
		self.payloads = dictionary[kProfileItems];
	}
	
	if(![dictionary[kProfileOrganization] isKindOfClass:[NSNull class]]){
		self.organization = dictionary[kProfileOrganization];
	}
	
	if(![dictionary[kProfileType] isKindOfClass:[NSNull class]]){
		self.type = dictionary[kProfileType];
	}
	
	if(![dictionary[kProfileUUID] isKindOfClass:[NSNull class]]){
		self.uuid = dictionary[kProfileUUID];
	}
	
	if(![dictionary[kProfileRemovalDisallowed] isKindOfClass:[NSNull class]]){
		self.removalDisallowed = dictionary[kProfileRemovalDisallowed];
	}
	
	if(![dictionary[kProfileVerificationState] isKindOfClass:[NSNull class]]){
		self.verificationState = dictionary[kProfileVerificationState];
	}
	
	if(![dictionary[kProfileVersion] isKindOfClass:[NSNull class]]){
		self.version = dictionary[kProfileVersion];
	}
	
	return self;
}


/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
-(NSDictionary *)toDictionary
{
	NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
	/*
	if(self.descriptionField != nil){
		dictionary[kAgentDescriptionField] = self.descriptionField;
	}
	
	if(self.clientGroup != nil){
		dictionary[kAgentClientGroup] = self.clientGroup;
	}
	
	if(self.groupId != nil){
		dictionary[kAgentGroupId] = self.groupId;
	}
	dictionary[kAgentPatchClient] = @(self.patchClient);
	
	if(self.patchGroup != nil){
		dictionary[kAgentPatchGroup] = self.patchGroup;
	}
	
	dictionary[kAgentPatchServer] = @(self.patchServer);
	dictionary[kAgentPatchState] = @(self.patchState);
	dictionary[kAgentReboot] = @(self.reboot);
	
	if(self.swDistGroup != nil){
		dictionary[kAgentSwDistGroup] = self.swDistGroup;
	}
	
	if(self.swDistGroupAdd != nil){
		dictionary[kAgentSwDistGroupAdd] = self.swDistGroupAdd;
	}
	
	if(self.swDistGroupAddID != nil){
		dictionary[kAgentSwDistGroupAddID] = self.swDistGroupAddID;
	}
	
	if(self.swDistGroupID != nil){
		dictionary[kAgentSwDistGroupID] = self.swDistGroupID;
	}
	
	dictionary[kAgentVerifySignatures] = @(self.verifySignatures);
	dictionary[kAgentPreStagePatches] = @(self.preStagePatches);
	*/
	return dictionary;
}


- (NSDictionary *)defaultData
{
	return nil;
}

/**
 * Implementation of NSCoding encoding method
 */
/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	if(self.displayName != nil) [aCoder encodeObject:self.displayName forKey:kProfileDisplayName];
	if(self.identifier != nil) [aCoder encodeObject:self.identifier forKey:kProfileIdentifier];
	if(self.installDate != nil) [aCoder encodeObject:self.installDate forKey:kProfileInstallDate];
	if(self.payloads != nil) [aCoder encodeObject:self.payloads forKey:kProfileItems];
	if(self.organization != nil) [aCoder encodeObject:self.organization forKey:kProfileOrganization];
	if(self.type != nil) [aCoder encodeObject:self.type forKey:kProfileType];
	if(self.uuid != nil) [aCoder encodeObject:self.uuid forKey:kProfileUUID];
	if(self.removalDisallowed != nil) [aCoder encodeObject:self.removalDisallowed forKey:kProfileRemovalDisallowed];
	if(self.verificationState != nil) [aCoder encodeObject:self.verificationState forKey:kProfileVerificationState];
	if(self.version != nil) [aCoder encodeObject:self.version forKey:kProfileVersion];
}

/**
 * Implementation of NSCoding initWithCoder: method
 */
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	
	self.displayName = [aDecoder decodeObjectForKey:kProfileDisplayName];
	self.identifier = [aDecoder decodeObjectForKey:kProfileIdentifier];
	self.installDate = [aDecoder decodeObjectForKey:kProfileInstallDate];
	self.payloads = [aDecoder decodeObjectForKey:kProfileItems];
	self.organization = [aDecoder decodeObjectForKey:kProfileOrganization];
	self.type = [aDecoder decodeObjectForKey:kProfileType];
	self.uuid = [aDecoder decodeObjectForKey:kProfileUUID];
	self.removalDisallowed = [aDecoder decodeObjectForKey:kProfileRemovalDisallowed];
	self.verificationState = [aDecoder decodeObjectForKey:kProfileVerificationState];
	self.version = [aDecoder decodeObjectForKey:kProfileVersion];
	
	return self;
}

/**
 * Implementation of NSCopying copyWithZone: method
 */
- (instancetype)copyWithZone:(NSZone *)zone
{
	ConfigProfile *copy = [ConfigProfile new];
	copy.displayName = [self.displayName copy];
	copy.identifier = [self.identifier copy];
	copy.installDate = [self.installDate copy];
	copy.payloads = [self.payloads copy];
	copy.organization = [self.organization copy];
	copy.type = [self.type copy];
	copy.uuid = [self.uuid copy];
	copy.removalDisallowed = [self.removalDisallowed copy];
	copy.verificationState = [self.verificationState copy];
	copy.version = [self.version copy];
	return copy;
}

@end
