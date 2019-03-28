//
//  AppLaunchObject.m
//  MPClientStatus
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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

#import "AppLaunchObject.h"

@interface AppLaunchObject (Private)

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;
- (NSString *)stringOrNAForKey:(id)aKey fromDictionary:(NSDictionary *)dict;
- (NSString *)stringOrZeroForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation AppLaunchObject

@synthesize appName;
@synthesize appPath;
@synthesize appVersion;

+ (AppLaunchObject *)appLaunchObjectWithDictionary:(NSDictionary *)dict
{
    AppLaunchObject *instance = [[AppLaunchObject alloc] initWithDictionary:dict];
    return instance;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        self.appName = @"NA";
        self.appPath = @"NA";
        self.appVersion = @"0";
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
    self = [super init];

    // This check serves to make sure that a non-NSDictionary object
    // passed into the model class doesn't break the parsing.
    if(self && [dict isKindOfClass:[NSDictionary class]]) {
        self.appName = [self stringOrNAForKey:@"NSApplicationName" fromDictionary:dict];
        self.appPath = [self stringOrNAForKey:@"NSApplicationPath" fromDictionary:dict];
        self.appVersion = [self stringOrZeroForKey:@"CFBundleShortVersionString" fromDictionary:dict];
    }

    return self;
}

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict
{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? nil : object;
}

- (NSString *)stringOrNAForKey:(id)aKey fromDictionary:(NSDictionary *)dict
{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? @"NA" : object;
}

- (NSString *)stringOrZeroForKey:(id)aKey fromDictionary:(NSDictionary *)dict
{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? @"0" : object;
}

- (NSDictionary *)appLaunchObjectAsDictionary
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    [d setObject:self.appName forKey:@"appName"];
    [d setObject:self.appPath forKey:@"appPath"];
    [d setObject:self.appVersion forKey:@"appVersion"];
    return [NSDictionary dictionaryWithDictionary:d];
}

@end
