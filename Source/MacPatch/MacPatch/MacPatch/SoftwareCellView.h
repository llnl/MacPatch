//
//  SoftwareCellView.h
/*
Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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
#import "SYFlatButton.h"

@protocol SoftwareCellViewDelegate <NSObject>
@optional
- (void)softwareCellViewDidStartInstall:(nonnull id)cell rowData:(nonnull NSDictionary *)rowData;
- (void)softwareCellView:(nonnull id)cell didUpdateProgress:(double)progress status:(nonnull NSString *)status rowData:(nonnull NSDictionary *)rowData;
- (void)softwareCellViewDidFinish:(nonnull id)cell success:(BOOL)success errorMessage:(nullable NSString *)message rowData:(nonnull NSDictionary *)rowData;
@end

@interface SoftwareCellView : NSTableCellView
{
    long long				maxValLong;
    long long				curValLong;
	
	
	//Tile * __weak **grid;
}
@property (nonatomic, weak, nullable) id<SoftwareCellViewDelegate> delegate;

@property (nonatomic, strong, nonnull) NSURL         *mp_SOFTWARE_DATA_DIR;
@property (nonatomic, strong, nullable) NSDictionary  *rowData;
@property (nonatomic, strong, nullable) NSArray		*serverArray;
@property (nonatomic, assign) BOOL 			isAppInstalled;
@property (nonatomic, assign) BOOL          isLocalAppInstalled;

@property (nonatomic, strong, nullable) IBOutlet NSProgressIndicator *progressBar;
@property (nonatomic, strong, nullable) IBOutlet SYFlatButton *actionButton;
@property (nonatomic, strong, nullable) IBOutlet NSImageView *installedStateImage;
@property (nonatomic, strong, nullable) IBOutlet NSImageView *errorImage;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swRebootTextFlag;
@property (nonatomic, strong, nullable) IBOutlet NSImageView *swIcon;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swTitle;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swCompany;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swVersion;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swSize;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swInstallBy;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swDescription;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *swActionStatusText;


- (IBAction)runInstall:(nullable id)sender;
- (void)configureCellUI;

@end
