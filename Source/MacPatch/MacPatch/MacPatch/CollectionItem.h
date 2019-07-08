//
//  CollectionItem.h
//  TestViews
//
//  Created by Heizer, Charles on 12/12/12.
//  Copyright (c) 2012 LLNL. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface CollectionItem : NSCollectionViewItem
{
    long long		maxValLong;
	long long		curValLong;
}

@property (nonatomic, assign) IBOutlet NSDictionary    *rowData;
@property (nonatomic, assign) IBOutlet NSProgressIndicator *progressBar;
@property (nonatomic, assign) IBOutlet NSButton *actionButton;
@property (nonatomic, assign) IBOutlet NSImageView *rebootImage;
@property (nonatomic, assign) IBOutlet NSTextField *swReootTextFlag;
@property (nonatomic, assign) IBOutlet NSImageView *swIcon;
@property (nonatomic, assign) IBOutlet NSTextField *swTitle;
@property (nonatomic, assign) IBOutlet NSTextField *swCompany;
@property (nonatomic, assign) IBOutlet NSTextField *swVersion;
@property (nonatomic, assign) IBOutlet NSTextField *swSize;
@property (nonatomic, assign) IBOutlet NSTextField *swInstallBy;
@property (nonatomic, assign) IBOutlet NSTextField *swDescription;
@property (nonatomic, assign) IBOutlet NSTextField *swActionStatusText;

- (id)copyWithZone:(NSZone *)zone;
- (void)setRepresentedObject:(id)object;
- (void)awakeFromNib;

- (IBAction)runInstall:(id)sender;
- (void)installSoftware;

@end
