//
//  MPSystemInfo.h
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

@interface MPSystemInfo : NSObject

// MP Client Info
+ (NSString *)clientUUID;

// Networking
+ (NSString *)getActiveInterface __deprecated;
+ (NSString *)getMacAddressForActiveInterface __deprecated;
+ (NSString *)getMacAddressForInterface:(NSString *)bsdIfName __deprecated;
+ (NSString *)getIPAddress __deprecated;
+ (NSString *)getIPAddressForInterface:(NSString *)bsdIfName __deprecated;

// NEW Network collection methods
+ (NSString *)getMacAddressForInterfaceUsingC:(NSString *)interface;
// Will Return Interface, MAC address, IP Address
+ (NSDictionary *)activeInterfaceData;

// System Info
+ (NSDictionary *)consoleUserData;
+ (NSDictionary *)hostAndComputerNames;
+ (NSDictionary *)osVersionInfo;
+ (NSDictionary *)osVersionOctets;
+ (NSString *)hostArchitectureType;

+ (BOOL)hostNeedsReboot;

// Client Info
+ (NSDictionary *)getMPApplicationVersions;

// BSD Process List
+ (NSArray *)bsdProcessList;

@end
