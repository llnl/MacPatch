//
//  MPInstaller.h
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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

typedef NS_ENUM(NSInteger, MPAppInstallType)
{
	kAppMoveTo  = 0,
	kAppCopyTo = 1
};

@interface MPInstaller : NSObject

@property (nonatomic, assign, readonly) BOOL taskIsRunning;
@property (nonatomic, assign, readonly) int taskResult;

/**
 Installs all packages from a given path
 
 @param aPath directory containing package(s)
 @param aEnv installer environment string
 @return int (0 = Sucess)
 */
- (int)installPkgFromPath:(NSString *)aPath environment:(NSString *)aEnv;
/**
 Insatlls package from a given path to root of the disk
 */
- (int)installPkgToRoot:(NSString *)pkgPath;
/**
 Insatlls package from a given path to root of the disk
 Can specify installer environment variables string (Use NULL if empty)
 */
- (int)installPkgToRoot:(NSString *)pkgPath env:(NSString *)aEnv;
/**
 Insatlls package from a given path to a specific disk target
 Can specify installer environment variables string (Use NULL if empty)
 */
- (int)installPkg:(NSString *)pkgPath target:(NSString *)aTarget env:(NSString *)aEnv;


/**
 Installs a .App to /Application from a given path

 @param aDir location of .App to be moved to /Applciations
 @param installType see MPAppInstallType Copy or Move
 @return int
 */
- (int)installDotAppFrom:(NSString *)aDir action:(MPAppInstallType)installType;

- (int)installPkgFromDMG:(NSString *)dmgPath environment:(NSString *)aEnv;
- (int)installDotAppFromDMG:(NSString *)dmgPath;

// Notifications
- (void)taskDataAvailable:(NSNotification *)aNotification;
- (void)taskCompleted:(NSNotification *)aNotification;

@end
