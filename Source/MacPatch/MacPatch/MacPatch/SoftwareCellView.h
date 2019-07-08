//
//  SoftwareCellView.h
//  TestTable
//
//  Created by Heizer, Charles on 12/18/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

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
@property (nonatomic, assign) BOOL 			isAppInstalled;

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
