//
//  PowerProfile.h
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

@interface PowerProfile : NSObject

@property (nonatomic, strong) NSString *profileName;
@property (nonatomic, strong) NSString *wake_On_LAN;
@property (nonatomic, strong) NSString *standby_Enabled;
@property (nonatomic, strong) NSString *display_Sleep_Uses_Dim;
@property (nonatomic, strong) NSString *standby_Delay;
@property (nonatomic, strong) NSString *hibernate_File;
@property (nonatomic, strong) NSString *darkWakeBackgroundTasks;
@property (nonatomic, strong) NSString *gpuSwitch;
@property (nonatomic, strong) NSString *prioritizeNetworkReachabilityOverSleep;
@property (nonatomic, strong) NSString *disk_Sleep_Timer;
@property (nonatomic, strong) NSString *system_Sleep_Timer;
@property (nonatomic, strong) NSString *hibernate_Mode;
@property (nonatomic, strong) NSString *autoPowerOff_Delay;
@property (nonatomic, strong) NSString *display_Sleep_Timer;
@property (nonatomic, strong) NSString *autoPowerOff_Enabled;
@property (nonatomic, strong) NSString *ttySPreventSleep;
@property (nonatomic, strong) NSString *wake_On_AC_Change;
@property (nonatomic, strong) NSString *reduceBrightness;
@property (nonatomic, strong) NSString *wake_On_Clamshell_Open;

- (id)initWithProfileName:(NSString *)aProfileName;
- (NSDictionary *)dictionaryRepresentation;
- (NSDictionary *)parseWithDictionary:(NSDictionary *)aDictionary;

@end
