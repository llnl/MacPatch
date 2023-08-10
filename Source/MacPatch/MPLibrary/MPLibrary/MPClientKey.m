//
//  MPClientKey.m
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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

#import "MPClientKey.h"
#import "Constants.h"
#import "MPSimpleKeychain.h"
#import "MPKeyItem.h"

static MPClientKey *_instance;

@implementation MPClientKey

+ (MPClientKey *)sharedInstance
{
    @synchronized(self)
    {
        if (_instance == nil) {
            _instance = [[super allocWithZone:NULL] init];
        }
    }
    return _instance;
}

#pragma mark Singleton Methods

+ (id)allocWithZone:(NSZone *)zone
{
    return [self sharedInstance];
}


- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (NSString *)clientKey
{
    NSError *err = nil;
    MPSimpleKeychain *skc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_KEYCHAIN_FILE];
    MPKeyItem *keyItem = [skc retrieveKeyItemForService:kMPClientService error:&err];
    if (err) {
        logit(lcl_vWarning,@"getClientKey: %@",err.localizedDescription);
        return @"NA";
    }
    
    return keyItem.secret;
}

@end
