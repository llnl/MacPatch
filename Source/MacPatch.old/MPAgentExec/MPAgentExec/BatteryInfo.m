//
//  BatteryInfo.m
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

#import "BatteryInfo.h"
#import <IOKit/IOKitLib.h>

static NSString *kSERIAL_NUMBER = @"Serial_Number";
static NSString *kMANUFACTURER = @"Manufacturer";
static NSString *kDEVICE_NAME = @"DeviceName";
static NSString *kFIRMWARE_VERSION = @"Firmware_Version";
static NSString *kCHARGE_REMAINING_MAH = @"Charge_Remaining_mAh";
static NSString *kFULL_CHARGE_CAPACITY_MAH = @"Full_Charge_Capacity_mAh";
static NSString *kDESIGN_CHARGE_CAPACITY_MAH = @"Design_Charge_Capacity_mAh";
static NSString *kFULLY_CHARGED = @"Fully_Charged";
static NSString *kCHARGING = @"Charging";
static NSString *kCYCLE_COUNT = @"Cycle_Count";
static NSString *kDESIGN_CYCLE_COUNT = @"Design_Cycle_Count";
static NSString *kCONDITION = @"Condition";
static NSString *kVOLTAGE_MV = @"Voltage_mV";

@interface BatteryInfo ()

- (void)collectBatteryInfo;

@end

@implementation BatteryInfo

@synthesize serialNumber = _serialNumber;
@synthesize manufacturer = _manufacturer;
@synthesize deviceName = _deviceName;
@synthesize firmwareVersion = _firmwareVersion;
@synthesize chargeRemaining_mAh = _chargeRemaining_mAh;
@synthesize fullChargeCapacity_mAh = _fullChargeCapacity_mAh;
@synthesize designChargeCapacity_mAh = _designChargeCapacity_mAh;
@synthesize fullyCharged = _fullyCharged;
@synthesize charging = _charging;
@synthesize cycleCount = _cycleCount;
@synthesize designCycleCount = _designCycleCount;
@synthesize condition = _condition;
@synthesize voltage_mV = _voltage_mV;
@synthesize hasBatteryInstalled = _hasBatteryInstalled;

- (id)init
{
    self = [super init];
    if (self)
    {
        self.hasBatteryInstalled = NO;
        self.serialNumber = @"NA";
        self.manufacturer = @"NA";
        self.deviceName = @"NA";
        self.firmwareVersion = @"NA";
        self.chargeRemaining_mAh = @"NA";
        self.fullChargeCapacity_mAh = @"NA";
        self.designChargeCapacity_mAh = @"NA";
        self.fullyCharged = @"NA";
        self.charging = @"NA";
        self.cycleCount = @"0";
        self.designCycleCount = @"1000";
        self.condition = @"NA";
        self.voltage_mV = @"NA";
        [self collectBatteryInfo];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];

    [mutableDict setValue:self.serialNumber forKeyPath:kSERIAL_NUMBER];
    [mutableDict setValue:self.manufacturer forKeyPath:kMANUFACTURER];
    [mutableDict setValue:self.deviceName forKeyPath:kDEVICE_NAME];
    [mutableDict setValue:self.firmwareVersion forKeyPath:kFIRMWARE_VERSION];
    [mutableDict setValue:self.chargeRemaining_mAh forKeyPath:kCHARGE_REMAINING_MAH];
    [mutableDict setValue:self.fullChargeCapacity_mAh forKeyPath:kFULL_CHARGE_CAPACITY_MAH];
    [mutableDict setValue:self.designChargeCapacity_mAh forKeyPath:kDESIGN_CHARGE_CAPACITY_MAH];
    [mutableDict setValue:self.fullyCharged forKeyPath:kFULLY_CHARGED];
    [mutableDict setValue:self.charging forKeyPath:kCHARGING];
    [mutableDict setValue:self.cycleCount forKeyPath:kCYCLE_COUNT];
    [mutableDict setValue:self.designCycleCount forKeyPath:kDESIGN_CYCLE_COUNT];
    [mutableDict setValue:self.condition forKeyPath:kCONDITION];
    [mutableDict setValue:self.voltage_mV forKey:kVOLTAGE_MV];

    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (void)collectBatteryInfo
{
    CFStringRef ioPath = CFSTR("IOService:/AppleACPIPlatformExpert/SMB0/AppleECSMBusController/AppleSmartBatteryManager/AppleSmartBattery");
    CFMutableDictionaryRef properties;
    kern_return_t result;

    // go to battery entry!
    io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, CFStringGetCStringPtr(ioPath, kCFStringEncodingMacRoman));

    // read out properties
    result = IORegistryEntryCreateCFProperties(ioRegistryRoot, &properties, kCFAllocatorDefault,0);
    if (result != 0) {
        //NSLog(@"Error reading batter info.");
        return;
    } else {
        self.hasBatteryInstalled = YES;
    }

    // set variables to the values from the IOregistry
    NSDictionary *batteryData = [NSDictionary dictionaryWithDictionary:(__bridge NSDictionary *)properties];

    if ([batteryData objectForKey:@"BatterySerialNumber"])
        self.serialNumber = [batteryData objectForKey:@"BatterySerialNumber"];
    if ([batteryData objectForKey:@"Manufacturer"])
        self.manufacturer = [batteryData objectForKey:@"Manufacturer"];
    if ([batteryData objectForKey:@"DeviceName"])
        self.deviceName = [batteryData objectForKey:@"DeviceName"];
    if ([batteryData objectForKey:@"FirmwareSerialNumber"])
        self.firmwareVersion = [[batteryData objectForKey:@"FirmwareSerialNumber"] stringValue];
    if ([batteryData objectForKey:@"CurrentCapacity"])
        self.chargeRemaining_mAh = [[batteryData objectForKey:@"CurrentCapacity"] stringValue];
    if ([batteryData objectForKey:@"MaxCapacity"])
        self.fullChargeCapacity_mAh = [[batteryData objectForKey:@"MaxCapacity"] stringValue];
    if ([batteryData objectForKey:@"DesignCapacity"])
        self.designChargeCapacity_mAh = [[batteryData objectForKey:@"DesignCapacity"] stringValue];
    if ([batteryData objectForKey:@"FullyCharged"])
        self.fullyCharged = ([[batteryData objectForKey:@"FullyCharged"] boolValue] ? @"Yes" : @"No");
    if ([batteryData objectForKey:@"IsCharging"])
        self.charging = ([[batteryData objectForKey:@"IsCharging"] boolValue] ? @"Yes" : @"No");
    if ([batteryData objectForKey:@"CycleCount"])
        self.cycleCount = [[batteryData objectForKey:@"CycleCount"] stringValue];
    if ([batteryData objectForKey:@"DesignCycleCount9C"])
        self.designCycleCount = [[batteryData objectForKey:@"DesignCycleCount9C"] stringValue];
    if ([batteryData objectForKey:@"Voltage"])
        self.voltage_mV = [[batteryData objectForKey:@"Voltage"] stringValue];

}

@end
