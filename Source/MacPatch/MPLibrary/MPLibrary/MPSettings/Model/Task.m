//
//	Task.m
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

#import "Task.h"

NSString *const kTaskDescriptionField = @"Description";
NSString *const kTaskActive = @"active";
NSString *const kTaskCmd = @"cmd";
NSString *const kTaskData = @"data";
NSString *const kTaskEnddate = @"enddate";
NSString *const kTaskGroupId = @"group_id";
NSString *const kTaskInterval = @"interval";
NSString *const kTaskLasterror = @"lasterror";
NSString *const kTaskLastreturncode = @"lastreturncode";
NSString *const kTaskLastrun = @"lastrun";
NSString *const kTaskName = @"name";
NSString *const kTaskStartdate = @"startdate";
NSString *const kTaskTid = @"tid";
NSString *const kTaskTidrev = @"tidrev";
NSString *const kTaskType = @"type";

@interface Task ()
@end
@implementation Task




/**
 * Instantiate the instance using the passed dictionary values to set the properties values
 */

-(instancetype)initWithDictionary:(NSDictionary *)dictionary
{
	self = [super init];
	if(![dictionary[kTaskDescriptionField] isKindOfClass:[NSNull class]]){
		self.descriptionField = dictionary[kTaskDescriptionField];
	}

	if(![dictionary[kTaskActive] isKindOfClass:[NSNull class]]){
		self.active = [dictionary[kTaskActive] integerValue];
	}

	if(![dictionary[kTaskCmd] isKindOfClass:[NSNull class]]){
		self.cmd = dictionary[kTaskCmd];
	}

	if(![dictionary[kTaskData] isKindOfClass:[NSNull class]]){
		self.data = dictionary[kTaskData];
	}

	if(![dictionary[kTaskEnddate] isKindOfClass:[NSNull class]]){
		self.enddate = dictionary[kTaskEnddate];
	}

	if(![dictionary[kTaskGroupId] isKindOfClass:[NSNull class]]){
		self.groupId = dictionary[kTaskGroupId];
	}

	if(![dictionary[kTaskInterval] isKindOfClass:[NSNull class]]){
		self.interval = dictionary[kTaskInterval];
	}

	if(![dictionary[kTaskLasterror] isKindOfClass:[NSNull class]]){
		self.lasterror = dictionary[kTaskLasterror];
	}

	if(![dictionary[kTaskLastreturncode] isKindOfClass:[NSNull class]]){
		self.lastreturncode = dictionary[kTaskLastreturncode];
	}

	if(![dictionary[kTaskLastrun] isKindOfClass:[NSNull class]]){
		self.lastrun = dictionary[kTaskLastrun];
	}

	if(![dictionary[kTaskName] isKindOfClass:[NSNull class]]){
		self.name = dictionary[kTaskName];
	}

	if(![dictionary[kTaskStartdate] isKindOfClass:[NSNull class]]){
		self.startdate = dictionary[kTaskStartdate];
	}

	if(![dictionary[kTaskTid] isKindOfClass:[NSNull class]]){
		self.tid = [dictionary[kTaskTid] integerValue];
	}

	if(![dictionary[kTaskTidrev] isKindOfClass:[NSNull class]]){
		self.tidrev = [dictionary[kTaskTidrev] integerValue];
	}

	if(![dictionary[kTaskType] isKindOfClass:[NSNull class]]){
		self.type = [dictionary[kTaskType] integerValue];
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
		dictionary[kTaskDescriptionField] = self.descriptionField;
	}
	dictionary[kTaskActive] = @(self.active);
	if(self.cmd != nil){
		dictionary[kTaskCmd] = self.cmd;
	}
	if(self.data != nil){
		dictionary[kTaskData] = self.data;
	}
	if(self.enddate != nil){
		dictionary[kTaskEnddate] = self.enddate;
	}
	if(self.groupId != nil){
		dictionary[kTaskGroupId] = self.groupId;
	}
	if(self.interval != nil){
		dictionary[kTaskInterval] = self.interval;
	}
	if(self.lasterror != nil){
		dictionary[kTaskLasterror] = self.lasterror;
	}
	if(self.lastreturncode != nil){
		dictionary[kTaskLastreturncode] = self.lastreturncode;
	}
	if(self.lastrun != nil){
		dictionary[kTaskLastrun] = self.lastrun;
	}
	if(self.name != nil){
		dictionary[kTaskName] = self.name;
	}
	if(self.startdate != nil){
		dictionary[kTaskStartdate] = self.startdate;
	}
	dictionary[kTaskTid] = @(self.tid);
	dictionary[kTaskTidrev] = @(self.tidrev);
	dictionary[kTaskType] = @(self.type);
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
	if(self.descriptionField != nil){
		[aCoder encodeObject:self.descriptionField forKey:kTaskDescriptionField];
	}
	[aCoder encodeObject:@(self.active) forKey:kTaskActive];
    
    if(self.cmd != nil){
		[aCoder encodeObject:self.cmd forKey:kTaskCmd];
	}
	if(self.data != nil){
		[aCoder encodeObject:self.data forKey:kTaskData];
	}
	if(self.enddate != nil){
		[aCoder encodeObject:self.enddate forKey:kTaskEnddate];
	}
	if(self.groupId != nil){
		[aCoder encodeObject:self.groupId forKey:kTaskGroupId];
	}
	if(self.interval != nil){
		[aCoder encodeObject:self.interval forKey:kTaskInterval];
	}
	if(self.lasterror != nil){
		[aCoder encodeObject:self.lasterror forKey:kTaskLasterror];
	}
	if(self.lastreturncode != nil){
		[aCoder encodeObject:self.lastreturncode forKey:kTaskLastreturncode];
	}
	if(self.lastrun != nil){
		[aCoder encodeObject:self.lastrun forKey:kTaskLastrun];
	}
	if(self.name != nil){
		[aCoder encodeObject:self.name forKey:kTaskName];
	}
	if(self.startdate != nil){
		[aCoder encodeObject:self.startdate forKey:kTaskStartdate];
	}
	[aCoder encodeObject:@(self.tid) forKey:kTaskTid];
    [aCoder encodeObject:@(self.tidrev) forKey:kTaskTidrev];
    [aCoder encodeObject:@(self.type) forKey:kTaskType];
}

/**
 * Implementation of NSCoding initWithCoder: method
 */
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	self.descriptionField = [aDecoder decodeObjectForKey:kTaskDescriptionField];
	self.active = [[aDecoder decodeObjectForKey:kTaskActive] integerValue];
	self.cmd = [aDecoder decodeObjectForKey:kTaskCmd];
	self.data = [aDecoder decodeObjectForKey:kTaskData];
	self.enddate = [aDecoder decodeObjectForKey:kTaskEnddate];
	self.groupId = [aDecoder decodeObjectForKey:kTaskGroupId];
	self.interval = [aDecoder decodeObjectForKey:kTaskInterval];
	self.lasterror = [aDecoder decodeObjectForKey:kTaskLasterror];
	self.lastreturncode = [aDecoder decodeObjectForKey:kTaskLastreturncode];
	self.lastrun = [aDecoder decodeObjectForKey:kTaskLastrun];
	self.name = [aDecoder decodeObjectForKey:kTaskName];
	self.startdate = [aDecoder decodeObjectForKey:kTaskStartdate];
	self.tid = [[aDecoder decodeObjectForKey:kTaskTid] integerValue];
	self.tidrev = [[aDecoder decodeObjectForKey:kTaskTidrev] integerValue];
	self.type = [[aDecoder decodeObjectForKey:kTaskType] integerValue];
	return self;

}

/**
 * Implementation of NSCopying copyWithZone: method
 */
- (instancetype)copyWithZone:(NSZone *)zone
{
	Task *copy = [Task new];

	copy.descriptionField = [self.descriptionField copy];
	copy.active = self.active;
	copy.cmd = [self.cmd copy];
	copy.data = [self.data copy];
	copy.enddate = [self.enddate copy];
	copy.groupId = [self.groupId copy];
	copy.interval = [self.interval copy];
	copy.lasterror = [self.lasterror copy];
	copy.lastreturncode = [self.lastreturncode copy];
	copy.lastrun = [self.lastrun copy];
	copy.name = [self.name copy];
	copy.startdate = [self.startdate copy];
	copy.tid = self.tid;
	copy.tidrev = self.tidrev;
	copy.type = self.type;

	return copy;
}
@end
