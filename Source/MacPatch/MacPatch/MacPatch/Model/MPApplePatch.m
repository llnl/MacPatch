//
//  MPApplePatch.m
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

#import "MPApplePatch.h"

NSString *const kApplePatchCUUID = @"cuuid";
NSString *const kApplePatchPatch = @"patch";
NSString *const kApplePatchType = @"type";
NSString *const kApplePatchDescription = @"description";
NSString *const kApplePatchSize = @"size";
NSString *const kApplePatchRecommended = @"recommended";
NSString *const kApplePatchRestartRequired = @"restart";
NSString *const kApplePatchVersion = @"version";

@interface MPApplePatch ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation MPApplePatch

@synthesize cuuid;
@synthesize patch;
@synthesize type;
@synthesize patchDescription;
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
        [self setCuuid:[self cuuid]];
        self.patch = [self objectOrNilForKey:kApplePatchPatch fromDictionary:dict];
        self.type = [self objectOrNilForKey:kApplePatchType fromDictionary:dict];
        self.patchDescription = [self objectOrNilForKey:kApplePatchDescription fromDictionary:dict];
        NSString *xSize = [self objectOrNilForKey:kApplePatchSize fromDictionary:dict];
        self.size = [xSize stringByReplacingOccurrencesOfString:@"K" withString:@""];
        self.recommended = [self objectOrNilForKey:kApplePatchRecommended fromDictionary:dict];
        self.restart = [self objectOrNilForKey:kApplePatchRestartRequired fromDictionary:dict];
        self.version = [self objectOrNilForKey:kApplePatchVersion fromDictionary:dict];
    }
    
    return self;
}

- (NSDictionary *)asDictionary
{
    // cuuid, patch, type, description, size, recommended, restart, version
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:self.cuuid forKey:kApplePatchCUUID];
    [p setObject:self.patch forKey:kApplePatchPatch];
    [p setObject:self.type forKey:kApplePatchType];
    [p setObject:self.patchDescription forKey:kApplePatchDescription];
    [p setObject:self.size forKey:kApplePatchSize];
    [p setObject:self.recommended forKey:kApplePatchRecommended];
    [p setObject:self.restart forKey:kApplePatchRestartRequired];
    [p setObject:self.version forKey:kApplePatchVersion];
    
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
    [self setType:@"Apple"];
    [self setPatchDescription:[aDictionary objectForKey:@"description"]];
    NSString *xSize = [[aDictionary objectForKey:@"size"] stringByReplacingOccurrencesOfString:@"K" withString:@""];
    [self setSize:xSize];
    [self setRecommended:[aDictionary objectForKey:@"recommended"]];
    [self setRestart:[aDictionary objectForKey:@"restart"]];
    [self setVersion:[aDictionary objectForKey:@"version"]];
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
    
    self.cuuid = [aDecoder decodeObjectForKey:kApplePatchCUUID];
    self.patch = [aDecoder decodeObjectForKey:kApplePatchPatch];
    self.type = [aDecoder decodeObjectForKey:kApplePatchType];
    self.patchDescription = [aDecoder decodeObjectForKey:kApplePatchDescription];
    self.size = [aDecoder decodeObjectForKey:kApplePatchSize];
    self.recommended = [aDecoder decodeObjectForKey:kApplePatchRecommended];
    self.restart = [aDecoder decodeObjectForKey:kApplePatchRestartRequired];
    self.version = [aDecoder decodeObjectForKey:kApplePatchVersion];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:cuuid forKey:kApplePatchCUUID];
    [aCoder encodeObject:patch forKey:kApplePatchPatch];
    [aCoder encodeObject:type forKey:kApplePatchType];
    [aCoder encodeObject:patchDescription forKey:kApplePatchDescription];
    [aCoder encodeObject:size forKey:kApplePatchSize];
    [aCoder encodeObject:recommended forKey:kApplePatchRecommended];
    [aCoder encodeObject:restart forKey:kApplePatchRestartRequired];
    [aCoder encodeObject:version forKey:kApplePatchVersion];
}

- (id)copyWithZone:(NSZone *)zone
{
    MPApplePatch *copy = [[MPApplePatch alloc] init];
    
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
    }
    
    return copy;
}
@end
