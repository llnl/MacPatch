//
//  MPCustomPatch.m
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
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

NSString *const kThirdPatchCUUID = @"cuuid";
NSString *const kThirdPatchPatch = @"patch";
NSString *const kThirdPatchType = @"type";
NSString *const kThirdPatchDescription = @"description";
NSString *const kThirdPatchSize = @"size";
NSString *const kThirdPatchRecommended = @"recommended";
NSString *const kThirdPatchRestartRequired = @"restart";
NSString *const kThirdPatchVersion = @"version";
NSString *const kThirdPatchID = @"patch_id";
NSString *const kThirdPatchBundle = @"bundleID";

@interface MPCustomPatch ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

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
        [self setCuuid:[self cuuid]];
        self.patch = [self objectOrNilForKey:kThirdPatchPatch fromDictionary:dict];
        self.type = [self objectOrNilForKey:kThirdPatchType fromDictionary:dict];
        self.patchDescription = [self objectOrNilForKey:kThirdPatchDescription fromDictionary:dict];
        NSString *xSize = [self objectOrNilForKey:kThirdPatchSize fromDictionary:dict];
        self.size = [xSize stringByReplacingOccurrencesOfString:@"K" withString:@""];
        self.recommended = [self objectOrNilForKey:kThirdPatchRecommended fromDictionary:dict];
        self.restart = [self objectOrNilForKey:kThirdPatchRestartRequired fromDictionary:dict];
        self.version = [self objectOrNilForKey:kThirdPatchVersion fromDictionary:dict];
        self.patch_id = [self objectOrNilForKey:kThirdPatchID fromDictionary:dict];
        self.bundleID = [self objectOrNilForKey:kThirdPatchBundle fromDictionary:dict];
    }
    
    return self;
}

- (NSDictionary *)asDictionary
{
    // cuuid, patch, type, description, size, recommended, restart, version
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:self.cuuid forKey:kThirdPatchCUUID];
    [p setObject:self.patch forKey:kThirdPatchPatch];
    [p setObject:self.type forKey:kThirdPatchType];
    [p setObject:self.patchDescription forKey:kThirdPatchDescription];
    [p setObject:self.size forKey:kThirdPatchSize];
    [p setObject:self.recommended forKey:kThirdPatchRecommended];
    [p setObject:self.restart forKey:kThirdPatchRestartRequired];
    [p setObject:self.version forKey:kThirdPatchVersion];
    [p setObject:self.patch_id forKey:kThirdPatchID];
    [p setObject:self.bundleID forKey:kThirdPatchBundle];
    
    return [NSDictionary dictionaryWithDictionary:p];
}

#pragma mark - Helper Method
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict
{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? @"NA" : object;
}

- (void)parsePatchDictionary:(NSDictionary *)aDictionary
{
    [self setPatch:[aDictionary objectForKey:@"patch"]];
    [self setType:@"Third"];
    [self setPatchDescription:[aDictionary objectForKey:@"description"]];
    NSString *xSize = [[aDictionary objectForKey:@"size"] stringByReplacingOccurrencesOfString:@"K" withString:@""];
    [self setSize:xSize];
    [self setRecommended:[aDictionary objectForKey:@"recommended"]];
    [self setRestart:[aDictionary objectForKey:@"restart"]];
    [self setVersion:[aDictionary objectForKey:@"version"]];
    [self setPatch_id:[aDictionary objectForKey:@"patch_id"]];
    [self setBundleID:[aDictionary objectForKey:@"bundleID"]];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@", [self asDictionary]];
}

- (NSString *)cuuid
{
    NSString *result = NULL;
    io_struct_inband_t iokit_entry;
    uint32_t bufferSize = 4096; // this signals the longest entry we will take
    io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
    IORegistryEntryGetProperty(ioRegistryRoot, kIOPlatformUUIDKey, iokit_entry, &bufferSize);
    result = [NSString stringWithCString:iokit_entry encoding:NSASCIIStringEncoding];
    
    IOObjectRelease((unsigned int) iokit_entry);
    IOObjectRelease(ioRegistryRoot);
    
    return result;
}

#pragma mark - NSCoding Methods

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    
    self.cuuid = [aDecoder decodeObjectForKey:kThirdPatchCUUID];
    self.patch = [aDecoder decodeObjectForKey:kThirdPatchPatch];
    self.type = [aDecoder decodeObjectForKey:kThirdPatchType];
    self.patchDescription = [aDecoder decodeObjectForKey:kThirdPatchDescription];
    self.size = [aDecoder decodeObjectForKey:kThirdPatchSize];
    self.recommended = [aDecoder decodeObjectForKey:kThirdPatchRecommended];
    self.restart = [aDecoder decodeObjectForKey:kThirdPatchRestartRequired];
    self.version = [aDecoder decodeObjectForKey:kThirdPatchVersion];
    self.patch_id = [aDecoder decodeObjectForKey:kThirdPatchID];
    self.bundleID = [aDecoder decodeObjectForKey:kThirdPatchBundle];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:cuuid forKey:kThirdPatchCUUID];
    [aCoder encodeObject:patch forKey:kThirdPatchPatch];
    [aCoder encodeObject:type forKey:kThirdPatchType];
    [aCoder encodeObject:patchDescription forKey:kThirdPatchDescription];
    [aCoder encodeObject:size forKey:kThirdPatchSize];
    [aCoder encodeObject:recommended forKey:kThirdPatchRecommended];
    [aCoder encodeObject:restart forKey:kThirdPatchRestartRequired];
    [aCoder encodeObject:version forKey:kThirdPatchVersion];
    [aCoder encodeObject:patch_id forKey:kThirdPatchID];
    [aCoder encodeObject:bundleID forKey:kThirdPatchBundle];
}

- (id)copyWithZone:(NSZone *)zone
{
    MPCustomPatch *copy = [[MPCustomPatch alloc] init];
    
    if (copy)
    {
        copy.cuuid = [self.cuuid copyWithZone:zone];
        copy.patch = [self.patch copyWithZone:zone];
        copy.type = [self.type copyWithZone:zone];
        copy.patchDescription = [self.patchDescription copyWithZone:zone];
        copy.size = [self.size copyWithZone:zone];
        copy.recommended = [self.recommended copyWithZone:zone];
        copy.restart = [self.restart copyWithZone:zone];
        copy.version = [self.version copyWithZone:zone];
        copy.patch_id = [self.patch_id copyWithZone:zone];
        copy.bundleID = [self.bundleID copyWithZone:zone];
    }
    
    return copy;
}

@end
