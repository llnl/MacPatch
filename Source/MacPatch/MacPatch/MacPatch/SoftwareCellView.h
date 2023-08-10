//
//  SoftwareCellView.h
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

#import <Cocoa/Cocoa.h>
#import "SYFlatButton.h"

@interface SoftwareCellView : NSTableCellView
{
    long long				maxValLong;
    long long				curValLong;
	
	
	//Tile * __weak **grid;
}
@property (nonatomic, strong) NSURL         *mp_SOFTWARE_DATA_DIR;
@property (nonatomic, strong) NSDictionary  *rowData;
@property (nonatomic, strong) NSArray		*serverArray;
@property (nonatomic, assign) BOOL 			isAppInstalled;
@property (nonatomic, assign) BOOL          isLocalAppInstalled;

@property (nonatomic, strong) IBOutlet NSProgressIndicator *progressBar;
@property (nonatomic, strong) IBOutlet SYFlatButton *actionButton;
@property (nonatomic, strong) IBOutlet NSImageView *installedStateImage;
@property (nonatomic, strong) IBOutlet NSImageView *errorImage;
@property (nonatomic, strong) IBOutlet NSTextField *swRebootTextFlag;
@property (nonatomic, strong) IBOutlet NSImageView *swIcon;
@property (nonatomic, strong) IBOutlet NSTextField *swTitle;
@property (nonatomic, strong) IBOutlet NSTextField *swCompany;
@property (nonatomic, strong) IBOutlet NSTextField *swVersion;
@property (nonatomic, strong) IBOutlet NSTextField *swSize;
@property (nonatomic, strong) IBOutlet NSTextField *swInstallBy;
@property (nonatomic, strong) IBOutlet NSTextField *swDescription;
@property (nonatomic, strong) IBOutlet NSTextField *swActionStatusText;


- (IBAction)runInstall:(id)sender;

@end
