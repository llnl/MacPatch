//
//  MPAsus.h
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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

/*
	MPAsus, is the class to collect and install Apple Software Updates data 
*/

#import <Cocoa/Cocoa.h>

@class MPNetworkUtils;
@class MPServerConnection;

@interface MPAsus : NSObject 
{
    MPServerConnection  *mpServerConnection;
    MPNetworkUtils      *mpNetworkUtils;
	NSArray             *catalogURLArray;
	
@private
	NSDictionary	*defaults;
	NSString		*patchGroup;
	BOOL			allowClient;
	BOOL			allowServer;
	
	// Run Install task
	NSPipe *install_pipe;
	NSFileHandle *fh_installTask;
}

@property (nonatomic, strong) NSDictionary *defaults;
@property (nonatomic, strong) NSString *patchGroup;
@property (nonatomic, assign) BOOL allowClient;
@property (nonatomic, assign) BOOL allowServer;


- (id)initWithServerConnection:(MPServerConnection *)srvObj;

- (NSArray *)scanForCustomUpdates;
- (NSArray *)scanForCustomUpdateUsingBundleID:(NSString *)aBundleID;

- (NSArray *)scanForAppleUpdates;
- (NSString *)getSizeFromDescription:(NSString *)aDesc;
- (NSString *)getRecommendedFromDescription:(NSString *)aDesc;

- (void)scanAppleSoftwareUpdates:(NSArray *)approvedUpdates;
- (void)installAppleSoftwareUpdates:(NSArray *)approvedUpdates;
- (BOOL)installAppleSoftwareUpdates:(NSArray *)approvedUpdates isSelfCheck:(BOOL)aSelfCheck;

- (BOOL)downloadAppleUpdate:(NSString *)updateName;

- (NSArray *)installResultsToDictArray:(NSArray *)aInstalledPatches type:(NSString *)aType;

// Third Party Updates Installs
-(NSString *)downloadUpdate:(NSString *)aURL error:(NSError **)err;
-(int)installPkg:(NSString *)pkgPath error:(NSError **)err;
-(int)installPkg:(NSString *)pkgPath target:(NSString *)aTarget error:(NSError **)err;
-(NSString *)installPkgWithResult:(NSString *)pkgPath target:(NSString *)aTarget error:(NSError **)err;

-(NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs error:(NSError **)err;
-(NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs environment:(NSDictionary *)aEnv error:(NSError **)err;

// Helper Methods
-(NSString *)createTempDirFromURL:(NSString *)aURL;
-(int)unzip:(NSString *)aZipFilePath error:(NSError **)err;
-(int)unzip:(NSString *)aZipFilePath targetPath:(NSString *)aTargetPath error:(NSError **)err;

- (void)readInstallTaskData:(NSNotification *)aNotification;
- (void)installTaskEnded:(NSNotification *)aNotification;

@end
