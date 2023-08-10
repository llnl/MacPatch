//
//  AntiVirus.h
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

@interface AntiVirus : NSObject
{
    NSFileManager   *fm;
}

@property (nonatomic, strong) NSString *avType;
@property (nonatomic, strong) NSString *avApp;
@property (nonatomic, strong) NSDictionary *avAppInfo;
@property (nonatomic, strong) NSString *avDefsDate;
@property (nonatomic, strong) NSString *netDefsDate;
@property (nonatomic, strong) NSDictionary *l_Defaults;
@property (nonatomic, assign) BOOL isNewerSEPSW;

// Scan & Update
- (void)scanDefs __deprecated __deprecated_msg("use scanAVData instead.");
- (void)scanAVData;
- (void)scanAndUpdateDefs __deprecated __deprecated_msg("use scanAVDataAndUpdate instead.");
- (void)avScanAndUpdate:(BOOL)runUpdate __deprecated __deprecated_msg("use scanAVDataAndUpdate instead.");
- (void)scanAVDataAndUpdate:(BOOL)runUpdate;

// Collect
- (NSDictionary *)getAvAppInfo;
- (NSString *)getLocalDefsDate;
- (NSString *)parseNewDefsDateFormat:(NSString *)defsDate;

// Download & Update
- (NSString *)getLatestAVDefsDate __deprecated __deprecated_msg("use scanAVData instead.");
- (NSString *)getLatestAVDefsDateForType:(NSString *)avType;

- (NSString *)getAvUpdateURL;
- (int)downloadUnzipAndInstall:(NSString *)pkgURL;
- (int)runAVDefsUpdate;

@end
