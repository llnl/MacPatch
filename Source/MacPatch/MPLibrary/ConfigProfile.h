//
//  ConfigProfile.h
//  MPLibrary
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


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConfigProfile : NSObject

@property (nonatomic, strong) NSString *displayName;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *installDate;
@property (nonatomic, strong) NSArray *payloads;
@property (nonatomic, strong) NSString *organization;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, strong) NSString *removalDisallowed;
@property (nonatomic, strong) NSString *verificationState;
@property (nonatomic, strong) NSString *version;


- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)toDictionary;
- (NSDictionary *)defaultData;

@end

NS_ASSUME_NONNULL_END
