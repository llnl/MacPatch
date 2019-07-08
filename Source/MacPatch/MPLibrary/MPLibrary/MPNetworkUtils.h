//
//  MPNetworkUtils.h
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

#import <Cocoa/Cocoa.h>


@interface MPNetworkUtils : NSObject 
{
	NSDictionary *hostConfig;
}

@property (nonatomic, strong) NSDictionary *hostConfig;

- (BOOL)isHostReachable:(NSString *)aHost;
- (BOOL)isHostURLReachable:(NSString *)aURL;
- (BOOL)isURLValid:(NSString *)aURL returnCode:(int)aReturnCode;
- (BOOL)isServerReachable:(NSString *)aHost port:(int)aPort connection:(NSString *)aHTTP;
- (BOOL)isPortReachable:(int)aPort host:(NSString *)aHost;
- (BOOL)pingURLHostWithPort:(NSString *)aHost port:(int)aPort scheme:(NSString *)aScheme;
- (BOOL)pingHostWithPort:(NSString *)aHost port:(int)aPort;

- (id)initWithDefaults:(NSDictionary *)aDictionary;

- (NSDictionary *)mpHostConfig;
- (NSDictionary *)mpHostConfig:(NSDictionary *)aDefaults;
- (NSDictionary *)mpHostConfigUsingFile:(NSString *)aDefaultsFile;

@end
