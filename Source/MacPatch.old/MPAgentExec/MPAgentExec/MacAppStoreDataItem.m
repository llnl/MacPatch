//
//  MacAppStoreData
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

#import "MacAppStoreDataItem.h"

static NSString *kItemName                  = @"itemName";
static NSString *kItemVersion               = @"itemVersion";
static NSString *kItemCFBundleIdentifier    = @"itemCFBundleIdentifier";
static NSString *kAppStorePurchaseDate      = @"appStorePurchaseDate";
static NSString *kAppStoreCategory          = @"appStoreCategory";
static NSString *kAppStoreReceiptType       = @"appStoreReceiptType";
static NSString *kAppStoreIsAppleSigned     = @"appStoreIsAppleSigned";
static NSString *kItemUseCount              = @"itemUseCount";

@interface MacAppStoreDataItem ()

- (void)processDataItem:(NSMetadataItem *)item;

@end

@implementation MacAppStoreDataItem

@synthesize itemName = _itemName;
@synthesize itemVersion = _itemVersion;
@synthesize itemCFBundleIdentifier = _itemCFBundleIdentifier;
@synthesize appStorePurchaseDate = _appStorePurchaseDate;
@synthesize appStoreCategory = _appStoreCategory;
@synthesize appStoreReceiptType = _appStoreReceiptType;
@synthesize appStoreIsAppleSigned = _appStoreIsAppleSigned;
@synthesize itemUseCount = _itemUseCount;

- (id)init
{
    self = [super init];
    if (self)
    {
        self.itemName = @"NA";
        self.itemVersion = @"NA";
        self.itemCFBundleIdentifier = @"NA";
        self.appStorePurchaseDate = @"NA";
        self.appStoreCategory = @"NA";
        self.appStoreReceiptType = @"NA";
        self.appStoreIsAppleSigned = @"0";
        self.itemUseCount = @"0";
    }
    return self;
}

- (id)initWithNSMetadataItem:(NSMetadataItem *)metaDataItem
{
    self = [super init];
    if (self)
    {
        self.itemName = @"NA";
        self.itemVersion = @"NA";
        self.itemCFBundleIdentifier = @"NA";
        self.appStorePurchaseDate = @"NA";
        self.appStoreCategory = @"NA";
        self.appStoreReceiptType = @"NA";
        self.appStoreIsAppleSigned = @"0";
        self.itemUseCount = @"0";
        [self processDataItem:metaDataItem];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];

    [mutableDict setValue:self.itemName forKeyPath:kItemName];
    [mutableDict setValue:self.itemVersion forKeyPath:kItemVersion];
    [mutableDict setValue:self.itemCFBundleIdentifier forKeyPath:kItemCFBundleIdentifier];
    [mutableDict setValue:self.appStorePurchaseDate forKeyPath:kAppStorePurchaseDate];
    [mutableDict setValue:self.appStoreCategory forKeyPath:kAppStoreCategory];
    [mutableDict setValue:self.appStoreReceiptType forKeyPath:kAppStoreReceiptType];
    [mutableDict setValue:self.appStoreIsAppleSigned forKeyPath:kAppStoreIsAppleSigned];
    [mutableDict setValue:self.itemUseCount forKeyPath:kItemUseCount];

    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (void)processDataItem:(NSMetadataItem *)item
{
    /* Not Used Yet
    NSArray *keyAlts = @[kItemVersion, kItemVersion, kItemCFBundleIdentifier, kAppStorePurchaseDate,
                         kAppStoreCategory, kAppStoreReceiptType ,kAppStoreIsAppleSigned ,kItemUseCount];
    NSArray *keys = @[@"kMDItemDisplayName", @"kMDItemVersion", @"kMDItemCFBundleIdentifier", @"kMDItemAppStorePurchaseDate",
                      @"kMDItemAppStoreCategory", @"kMDItemAppStoreReceiptType", @"kMDItemAppStoreIsAppleSigned", @"kMDItemUseCount"];
     */

    if ([item valueForAttribute:@"kMDItemDisplayName"]) {
        _itemName = [item valueForAttribute:@"kMDItemDisplayName"];
    }
    if ([item valueForAttribute:@"kMDItemVersion"]) {
        _itemVersion = [item valueForAttribute:@"kMDItemVersion"];
    }
    if ([item valueForAttribute:@"kMDItemCFBundleIdentifier"]) {
        _itemCFBundleIdentifier = [item valueForAttribute:@"kMDItemCFBundleIdentifier"];
    }
    if ([item valueForAttribute:@"kMDItemAppStorePurchaseDate"]) {
        _appStorePurchaseDate = [item valueForAttribute:@"kMDItemAppStorePurchaseDate"];
    }
    if ([item valueForAttribute:@"kMDItemAppStoreCategory"]) {
        _appStoreCategory = [item valueForAttribute:@"kMDItemAppStoreCategory"];
    }
    if ([item valueForAttribute:@"kMDItemAppStoreReceiptType"]) {
        _appStoreReceiptType = [item valueForAttribute:@"kMDItemAppStoreReceiptType"];
    }
    if ([item valueForAttribute:@"kMDItemAppStoreIsAppleSigned"]) {
        _appStoreIsAppleSigned = [item valueForAttribute:@"kMDItemAppStoreIsAppleSigned"];
    }
    if ([item valueForAttribute:@"kMDItemUseCount"]) {
        _itemUseCount = [item valueForAttribute:@"kMDItemUseCount"];
    }
}

@end
