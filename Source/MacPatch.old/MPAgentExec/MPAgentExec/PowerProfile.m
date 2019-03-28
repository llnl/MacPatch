//
//  PowerProfile.m
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

#import "PowerProfile.h"

static NSString *kPROFILE_NAME = @"ProfileName";
static NSString *kWAKE_ON_LAN = @"Wake_On_LAN";
static NSString *kSTANDBY_ENABLED = @"Standby_Enabled";
static NSString *kDISPLAY_SLEEP_USES_DIM = @"Sisplay_Sleep_Uses_Dim";
static NSString *kSTANDBY_DELAY = @"Standby_Delay";
static NSString *kHIBERNATE_FILE = @"Hibernate_File";
static NSString *kDARK_WAKE_BACKGROUND_TASKS = @"DarkWakeBackgroundTasks";
static NSString *kGPU_SWITCH = @"GPUSwitch";
static NSString *kPRIORITIZE_NETWORK_REACHABILITY_OVER_SLEEP = @"PrioritizeNetworkReachabilityOverSleep";
static NSString *kDISK_SLEEP_TIMER = @"Disk_Sleep_Timer";
static NSString *kSYSTEM_SLEEP_TIMER = @"System_Sleep_Timer";
static NSString *kHIBERNATE_MODE = @"Hibernate_Mode";
static NSString *kAUTO_POWER_OFF_DELAY = @"AutoPowerOff_Delay";
static NSString *kDISPLAY_SLEEP_TIMER = @"Display_Sleep_Timer";
static NSString *kAUTO_POWER_OFF_ENABLED = @"AutoPowerOff_Enabled";
static NSString *kTTYS_PREVENT_SLEEP = @"TTYSPreventSleep";
static NSString *kWAKE_ON_AC_CHANGE = @"Wake_On_AC_Change";
static NSString *kREDUCE_BRIGHTNESS = @"ReduceBrightness";
static NSString *kWAKE_ON_CLAMSHELLOPEN = @"Wake_On_Clamshell_Open";


@implementation PowerProfile

@synthesize profileName = _profileName;
@synthesize wake_On_LAN = _wake_On_LAN;
@synthesize standby_Enabled = _standby_Enabled;
@synthesize display_Sleep_Uses_Dim = _display_Sleep_Uses_Dim;
@synthesize standby_Delay = _standby_Delay;
@synthesize hibernate_File = _hibernate_File;
@synthesize darkWakeBackgroundTasks = _darkWakeBackgroundTasks;
@synthesize gpuSwitch = _gpuSwitch;
@synthesize prioritizeNetworkReachabilityOverSleep = _prioritizeNetworkReachabilityOverSleep;
@synthesize disk_Sleep_Timer = _disk_Sleep_Timer;
@synthesize system_Sleep_Timer = _system_Sleep_Timer;
@synthesize hibernate_Mode = _hibernate_Mode;
@synthesize autoPowerOff_Delay = _autoPowerOff_Delay;
@synthesize display_Sleep_Timer = _display_Sleep_Timer;
@synthesize autoPowerOff_Enabled = _autoPowerOff_Enabled;
@synthesize ttySPreventSleep = _ttySPreventSleep;
@synthesize wake_On_AC_Change = _wake_On_AC_Change;
@synthesize reduceBrightness = _reduceBrightness;
@synthesize wake_On_Clamshell_Open = _wake_On_Clamshell_Open;

- (id)init
{
    self = [super init];
    if (self)
    {
        self.profileName = @"NA";
        self.wake_On_LAN = @"NA";
        self.standby_Enabled = @"NA";
        self.display_Sleep_Uses_Dim = @"NA";
        self.standby_Delay = @"NA";
        self.hibernate_File = @"NA";
        self.darkWakeBackgroundTasks = @"NA";
        self.gpuSwitch = @"NA";
        self.prioritizeNetworkReachabilityOverSleep = @"NA";
        self.disk_Sleep_Timer = @"NA";
        self.system_Sleep_Timer = @"NA";
        self.hibernate_Mode = @"NA";
        self.autoPowerOff_Delay = @"NA";
        self.display_Sleep_Timer = @"NA";
        self.autoPowerOff_Enabled = @"NA";
        self.ttySPreventSleep = @"NA";
        self.wake_On_AC_Change = @"NA";
        self.reduceBrightness = @"NA";
        self.wake_On_Clamshell_Open = @"NA";
    }
    return self;
}

- (id)initWithProfileName:(NSString *)aProfileName
{
    self = [super init];
    if (self)
    {
        self.profileName = aProfileName;
        self.wake_On_LAN = @"NA";
        self.standby_Enabled = @"NA";
        self.display_Sleep_Uses_Dim = @"NA";
        self.standby_Delay = @"NA";
        self.hibernate_File = @"NA";
        self.darkWakeBackgroundTasks = @"NA";
        self.gpuSwitch = @"NA";
        self.prioritizeNetworkReachabilityOverSleep = @"NA";
        self.disk_Sleep_Timer = @"NA";
        self.system_Sleep_Timer = @"NA";
        self.hibernate_Mode = @"NA";
        self.autoPowerOff_Delay = @"NA";
        self.display_Sleep_Timer = @"NA";
        self.autoPowerOff_Enabled = @"NA";
        self.ttySPreventSleep = @"NA";
        self.wake_On_AC_Change = @"NA";
        self.reduceBrightness = @"NA";
        self.wake_On_Clamshell_Open = @"NA";
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];

    [mutableDict setValue:self.profileName forKeyPath:kPROFILE_NAME];
    [mutableDict setValue:self.wake_On_LAN forKeyPath:kWAKE_ON_LAN];
    [mutableDict setValue:self.standby_Enabled forKeyPath:kSTANDBY_ENABLED];
    [mutableDict setValue:self.display_Sleep_Uses_Dim forKeyPath:kDISPLAY_SLEEP_USES_DIM];
    [mutableDict setValue:self.standby_Delay forKeyPath:kSTANDBY_DELAY];
    [mutableDict setValue:self.hibernate_File forKeyPath:kHIBERNATE_FILE];
    [mutableDict setValue:self.darkWakeBackgroundTasks forKeyPath:kDARK_WAKE_BACKGROUND_TASKS];
    [mutableDict setValue:self.gpuSwitch forKeyPath:kGPU_SWITCH];
    [mutableDict setValue:self.prioritizeNetworkReachabilityOverSleep forKeyPath:kPRIORITIZE_NETWORK_REACHABILITY_OVER_SLEEP];
    [mutableDict setValue:self.disk_Sleep_Timer forKeyPath:kDISK_SLEEP_TIMER];
    [mutableDict setValue:self.system_Sleep_Timer forKeyPath:kSYSTEM_SLEEP_TIMER];
    [mutableDict setValue:self.hibernate_Mode forKeyPath:kHIBERNATE_MODE];
    [mutableDict setValue:self.autoPowerOff_Delay forKeyPath:kAUTO_POWER_OFF_DELAY];
    [mutableDict setValue:self.display_Sleep_Timer forKeyPath:kDISPLAY_SLEEP_TIMER];
    [mutableDict setValue:self.autoPowerOff_Enabled forKeyPath:kAUTO_POWER_OFF_ENABLED];
    [mutableDict setValue:self.ttySPreventSleep forKeyPath:kTTYS_PREVENT_SLEEP];
    [mutableDict setValue:self.wake_On_AC_Change forKeyPath:kWAKE_ON_AC_CHANGE];
    [mutableDict setValue:self.reduceBrightness forKeyPath:kREDUCE_BRIGHTNESS];
    [mutableDict setValue:self.wake_On_Clamshell_Open forKeyPath:kWAKE_ON_CLAMSHELLOPEN];

    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (NSDictionary *)parseWithDictionary:(NSDictionary *)aDictionary
{
    if (!aDictionary) {
        return [self dictionaryRepresentation];
    }

    for (NSString *key in aDictionary.allKeys) {
        if ([key isEqualToString:@"Wake On LAN"]) {
            self.wake_On_LAN = ([[aDictionary objectForKey:@"Wake On LAN"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"Standby Enabled"]) {
            self.standby_Enabled = ([[aDictionary objectForKey:@"Standby Enabled"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"Display Sleep Uses Dim"]) {
            self.display_Sleep_Uses_Dim = ([[aDictionary objectForKey:@"Display Sleep Uses Dim"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"Standby Delay"]) {
            self.standby_Delay = [[aDictionary objectForKey:@"Standby Delay"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"Hibernate File"]) {
            self.hibernate_File = [aDictionary objectForKey:@"Hibernate File"];
            continue;
        }
        if ([key isEqualToString:@"DarkWakeBackgroundTasks"]) {
            self.darkWakeBackgroundTasks = ([[aDictionary objectForKey:@"DarkWakeBackgroundTasks"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"GPUSwitch"]) {
            self.gpuSwitch = [[aDictionary objectForKey:@"GPUSwitch"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"PrioritizeNetworkReachabilityOverSleep"]) {
            self.standby_Enabled = ([[aDictionary objectForKey:@"PrioritizeNetworkReachabilityOverSleep"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"Disk Sleep Timer"]) {
            self.display_Sleep_Timer = [[aDictionary objectForKey:@"Disk Sleep Timer"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"System Sleep Timer"]) {
            self.system_Sleep_Timer = [[aDictionary objectForKey:@"System Sleep Timer"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"Hibernate Mode"]) {
            self.hibernate_Mode = [[aDictionary objectForKey:@"Hibernate Mode"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"AutoPowerOff Delay"]) {
            self.autoPowerOff_Delay = [[aDictionary objectForKey:@"AutoPowerOff Delay"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"Display Sleep Timer"]) {
            self.display_Sleep_Timer = [[aDictionary objectForKey:@"Display Sleep Timer"] stringValue];
            continue;
        }
        if ([key isEqualToString:@"AutoPowerOff Enabled"]) {
            self.autoPowerOff_Enabled = ([[aDictionary objectForKey:@"AutoPowerOff Enabled"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"TTYSPreventSleep"]) {
            self.ttySPreventSleep = ([[aDictionary objectForKey:@"TTYSPreventSleep"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"Wake On AC Change"]) {
            self.wake_On_AC_Change = ([[aDictionary objectForKey:@"Wake On AC Change"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"ReduceBrightness"]) {
            self.reduceBrightness = ([[aDictionary objectForKey:@"ReduceBrightness"] boolValue] ? @"Yes" :@"No");
            continue;
        }
        if ([key isEqualToString:@"Wake On Clamshell Open"]) {
            self.wake_On_Clamshell_Open = ([[aDictionary objectForKey:@"Wake On Clamshell Open"] boolValue] ? @"Yes" :@"No");
            continue;
        }
    }

    return [self dictionaryRepresentation];
}

@end
