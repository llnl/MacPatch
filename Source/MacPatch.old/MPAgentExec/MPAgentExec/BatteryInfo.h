//
//  BatteryInfo.h
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

#import <Foundation/Foundation.h>

@interface BatteryInfo : NSObject

@property (nonatomic, strong) NSString *serialNumber;
@property (nonatomic, strong) NSString *manufacturer;
@property (nonatomic, strong) NSString *deviceName;
@property (nonatomic, strong) NSString *firmwareVersion;
@property (nonatomic, strong) NSString *chargeRemaining_mAh;
@property (nonatomic, strong) NSString *fullChargeCapacity_mAh;
@property (nonatomic, strong) NSString *designChargeCapacity_mAh;
@property (nonatomic, strong) NSString *fullyCharged;
@property (nonatomic, strong) NSString *charging;
@property (nonatomic, strong) NSString *cycleCount;
@property (nonatomic, strong) NSString *designCycleCount;
@property (nonatomic, strong) NSString *condition;
@property (nonatomic, strong) NSString *voltage_mV;
@property (nonatomic, assign) BOOL hasBatteryInstalled;

- (NSDictionary *)dictionaryRepresentation;

@end
