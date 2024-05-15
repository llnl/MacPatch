//
//	Agent.m
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

#import "Agent.h"

NSString *const kAgentDescriptionField  = @"Description";

NSString *const kAgentClientGroup       = @"client_group";
NSString *const kAgentGroupId           = @"client_group_id";
NSString *const kAgentClientGroupOld    = @"clientGroup";
NSString *const kAgentGroupIdOld        = @"group_id";

NSString *const kAgentPatchClient       = @"allow_client";		//*
NSString *const kAgentPatchGroup        = @"patch_group";		//*
NSString *const kAgentPatchServer       = @"allow_server";		//*
NSString *const kAgentPatchState        = @"patch_state";		//*
NSString *const kAgentReboot            = @"allow_reboot";		//*
NSString *const kAgentSwDistGroup       = @"software_group";	//*

NSString *const kAgentSwDistGroupAdd   		= @"inherited_software_group";
NSString *const kAgentSwDistGroupAddID  	= @"inherited_software_group_id";
NSString *const kAgentSwDistGroupAddOld   	= @"swDistGroupAdd";
NSString *const kAgentSwDistGroupAddIDOld 	= @"swDistGroupAddID";

NSString *const kAgentSwDistGroupID     = @"software_group_id";	//*
NSString *const kAgentVerifySignatures  = @"verify_signatures";	//*
NSString *const kAgentPreStagePatches   = @"pre_stage_patches";	//*

@interface Agent ()
@end

@implementation Agent

/**
 * Instantiate the instance using the passed dictionary values to set the properties values
 */

-(instancetype)initWithDictionary:(NSDictionary *)dictionary
{	
	self = [super init];
	if(![dictionary[kAgentDescriptionField] isKindOfClass:[NSNull class]]){
		self.descriptionField = dictionary[kAgentDescriptionField];
	}

	if(![dictionary[kAgentClientGroupOld] isKindOfClass:[NSNull class]]){
		self.clientGroup = dictionary[kAgentClientGroupOld];
	}
	
	if(![dictionary[kAgentClientGroup] isKindOfClass:[NSNull class]]){
		self.clientGroup = dictionary[kAgentClientGroup];
	}

	if(![dictionary[kAgentGroupIdOld] isKindOfClass:[NSNull class]]){
		self.groupId = dictionary[kAgentGroupIdOld];
	}
	
	if(![dictionary[kAgentGroupId] isKindOfClass:[NSNull class]]){
		self.groupId = dictionary[kAgentGroupId];
	}

	if(![dictionary[kAgentPatchClient] isKindOfClass:[NSNull class]]){
		self.patchClient = [dictionary[kAgentPatchClient] integerValue];
	}

	if(![dictionary[kAgentPatchGroup] isKindOfClass:[NSNull class]]){
		self.patchGroup = dictionary[kAgentPatchGroup];
	}

	if(![dictionary[kAgentPatchServer] isKindOfClass:[NSNull class]]){
		self.patchServer = [dictionary[kAgentPatchServer] integerValue];
	}

	if(![dictionary[kAgentPatchState] isKindOfClass:[NSNull class]]){
		self.patchState = [dictionary[kAgentPatchState] integerValue];
	}

	if(![dictionary[kAgentReboot] isKindOfClass:[NSNull class]]){
		self.reboot = [dictionary[kAgentReboot] integerValue];
	}

	if(![dictionary[kAgentSwDistGroup] isKindOfClass:[NSNull class]]){
		self.swDistGroup = dictionary[kAgentSwDistGroup];
	}

	if(![dictionary[kAgentSwDistGroupAddOld] isKindOfClass:[NSNull class]]){
		self.swDistGroupAdd = dictionary[kAgentSwDistGroupAddOld];
	}
	
	if(![dictionary[kAgentSwDistGroupAdd] isKindOfClass:[NSNull class]]){
		self.swDistGroupAdd = dictionary[kAgentSwDistGroupAdd];
	}

	if(![dictionary[kAgentSwDistGroupAddIDOld] isKindOfClass:[NSNull class]]){
		self.swDistGroupAddID = dictionary[kAgentSwDistGroupAddIDOld];
	}
	
	if(![dictionary[kAgentSwDistGroupAddID] isKindOfClass:[NSNull class]]){
		self.swDistGroupAddID = dictionary[kAgentSwDistGroupAddID];
	}

	if(![dictionary[kAgentSwDistGroupID] isKindOfClass:[NSNull class]]){
		self.swDistGroupID = dictionary[kAgentSwDistGroupID];
	}
    
    if(![dictionary[kAgentVerifySignatures] isKindOfClass:[NSNull class]]){
        self.verifySignatures = [dictionary[kAgentVerifySignatures] integerValue];
    }
    
    if(![dictionary[kAgentPreStagePatches] isKindOfClass:[NSNull class]]){
        self.preStagePatches = [dictionary[kAgentPreStagePatches] integerValue];
    }

	return self;
}


/**
 * Returns all the available property values in the form of NSDictionary object where the key is the approperiate json key and the value is the value of the corresponding property
 */
-(NSDictionary *)toDictionary
{
	NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
	
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
	if(self.descriptionField != nil){
		[aCoder encodeObject:self.descriptionField forKey:kAgentDescriptionField];
	}
	
    if(self.clientGroup != nil){
		[aCoder encodeObject:self.clientGroup forKey:kAgentClientGroup];
	}
	
    if(self.groupId != nil){
		[aCoder encodeObject:self.groupId forKey:kAgentGroupId];
	}
	
    [aCoder encodeObject:@(self.patchClient) forKey:kAgentPatchClient];
    
    if(self.patchGroup != nil){
		[aCoder encodeObject:self.patchGroup forKey:kAgentPatchGroup];
	}
	
    [aCoder encodeObject:@(self.patchServer) forKey:kAgentPatchServer];
    [aCoder encodeObject:@(self.patchState) forKey:kAgentPatchState];
    [aCoder encodeObject:@(self.reboot) forKey:kAgentReboot];
    
    if(self.swDistGroup != nil){
		[aCoder encodeObject:self.swDistGroup forKey:kAgentSwDistGroup];
	}
    
    if(self.swDistGroupAdd != nil){
		[aCoder encodeObject:self.swDistGroupAdd forKey:kAgentSwDistGroupAdd];
	}
	
    if(self.swDistGroupAddID != nil){
		[aCoder encodeObject:self.swDistGroupAddID forKey:kAgentSwDistGroupAddID];
	}
	
    if(self.swDistGroupID != nil){
		[aCoder encodeObject:self.swDistGroupID forKey:kAgentSwDistGroupID];
	}

    [aCoder encodeObject:@(self.verifySignatures) forKey:kAgentVerifySignatures];
    [aCoder encodeObject:@(self.preStagePatches) forKey:kAgentPreStagePatches];
}

/**
 * Implementation of NSCoding initWithCoder: method
 */
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	self.descriptionField = [aDecoder decodeObjectForKey:kAgentDescriptionField];
	self.clientGroup = [aDecoder decodeObjectForKey:kAgentClientGroup];
	self.groupId = [aDecoder decodeObjectForKey:kAgentGroupId];
	self.patchClient = [[aDecoder decodeObjectForKey:kAgentPatchClient] integerValue];
	self.patchGroup = [aDecoder decodeObjectForKey:kAgentPatchGroup];
	self.patchServer = [[aDecoder decodeObjectForKey:kAgentPatchServer] integerValue];
	self.patchState = [[aDecoder decodeObjectForKey:kAgentPatchState] integerValue];
	self.reboot = [[aDecoder decodeObjectForKey:kAgentReboot] integerValue];
	self.swDistGroup = [aDecoder decodeObjectForKey:kAgentSwDistGroup];
	self.swDistGroupAdd = [aDecoder decodeObjectForKey:kAgentSwDistGroupAdd];
	self.swDistGroupAddID = [aDecoder decodeObjectForKey:kAgentSwDistGroupAddID];
	self.swDistGroupID = [aDecoder decodeObjectForKey:kAgentSwDistGroupID];
    self.verifySignatures = [[aDecoder decodeObjectForKey:kAgentVerifySignatures] integerValue];
    self.preStagePatches = [[aDecoder decodeObjectForKey:kAgentPreStagePatches] integerValue];
	return self;

}

/**
 * Implementation of NSCopying copyWithZone: method
 */
- (instancetype)copyWithZone:(NSZone *)zone
{
	Agent *copy = [Agent new];
	copy.descriptionField = [self.descriptionField copy];
	copy.clientGroup = [self.clientGroup copy];
	copy.groupId = [self.groupId copy];
	copy.patchClient = self.patchClient;
	copy.patchGroup = [self.patchGroup copy];
	copy.patchServer = self.patchServer;
	copy.patchState = self.patchState;
	copy.reboot = self.reboot;
	copy.swDistGroup = [self.swDistGroup copy];
	copy.swDistGroupAdd = [self.swDistGroupAdd copy];
	copy.swDistGroupAddID = [self.swDistGroupAddID copy];
	copy.swDistGroupID = [self.swDistGroupID copy];
    copy.verifySignatures = self.verifySignatures;
    copy.preStagePatches = self.preStagePatches;
	return copy;
}

@end
