//
//  MPFileCheck.h
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


@interface MPFileCheck : NSObject {
	NSString *filePath;
}

- (NSString *)filePath;
- (void)setFilePath:(NSString *)aFilePath;

-(id)initWithFilePath:(NSString *)aPath;
-(BOOL)queryFile:(NSString *)action param:(NSString *)aParam;
-(BOOL)queryFile:(NSString *)aPath action:(NSString *)aAction param:(NSString *)aParam;

// Helpers
-(BOOL)fExists:(NSString *)aFile;
-(BOOL)fExists:(NSString *)aFile param:(NSString *)aParam;

-(BOOL)compareFileDate:(NSString *)aFile date:(NSString *)aDate operator:(NSString *)aOper;
-(NSDate *)dateWithSQLString:(NSString *)dateAndTime;

-(BOOL)checkFileVersion:(NSString *)localFilePath patchFileVer:(NSString *)aPatchFileVer operator:(NSString *)aOp;
-(BOOL)compareVersion:(NSString *)leftVersion operator:(NSString *)aOp compareTo:(NSString *)rightVersion;
-(NSDictionary *)getSWVers;

-(BOOL)checkFileHash:(NSString *)localFilePath fileHash:(NSString *)hash;
-(BOOL)checkFileHash:(NSString *)localFilePath fileHash:(NSString *)hash hashType:(NSString *)type;

- (BOOL)checkPlistKeyValue:(NSString *)localFilePath key:(NSString *)aKey value:(NSString *)aVal operator:(NSString *)aOp;

@end
