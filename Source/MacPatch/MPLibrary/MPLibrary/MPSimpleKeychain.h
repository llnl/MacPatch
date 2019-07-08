//
//  MPSimpleKeychain.h
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

#import <Foundation/Foundation.h>

@class MPKeyItem;

typedef NS_ENUM(NSUInteger, ServiceType) {
    kMPServerService = 0, // Client[uuid]
    kMPClientService = 1 // Server[uuid]
};

@interface MPSimpleKeychain : NSObject

// Primary Keychain Access Methods
- (id)initWithKeychainFile:(NSString *)aKeyChainFile;
- (OSStatus)createKeyChain:(NSString *)aKeyChainFile;
- (OSStatus)unlockKeyChain:(NSString *)aKeyChainFile;
- (OSStatus)lockKeyChain:(NSString *)aKeyChainFile;
- (OSStatus)deleteKeyChain;

// Save MPKeyItem in Keychain
- (BOOL)saveKeyItemWithService:(MPKeyItem *)aPasswordObj service:(ServiceType)aService error:(NSError **)error;
- (BOOL)saveKeyItemWithServiceAndAccount:(MPKeyItem *)aPasswordObj service:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error;

// Retrieve MPKeyItem in Keychain
- (MPKeyItem *)retrieveKeyItemForService:(ServiceType)aService error:(NSError **)error;
- (MPKeyItem *)retrieveKeyItemForServiceAndAccount:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error;
- (MPKeyItem *)retrieveKeyItemForServiceAndAccountWithKeychainItem:(ServiceType)aService account:(NSString *)aAccount keychainItem:(SecKeychainItemRef *)item error:(NSError **)error;

// Update MPKeyItem in Keychain
- (BOOL)updateKeyItemWithService:(MPKeyItem *)aPasswordObj service:(ServiceType)aService error:(NSError **)error;
- (BOOL)updateKeyItemWithServiceAndAccount:(MPKeyItem *)aPasswordObj service:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error;

// Delete MPKeyItem in Keychain
- (BOOL)deleteKeyItemWithService:(ServiceType)aService error:(NSError **)error;
- (BOOL)deleteKeyItemWithServiceAndAccount:(ServiceType)aService account:(NSString *)aAccount error:(NSError **)error;

- (NSError *)errorForOSStatus:(OSStatus)OSStatus;
@end
