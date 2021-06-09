//
//  MPAppStore.m
//  MyAppStore
//
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "MPAppStore.h"
#import "CKSoftwareProduct+ASProduct.h"

@implementation MPAppStore

- (NSArray *)installedProducts
{
    NSMutableArray *products = [NSMutableArray new];
    CKSoftwareMap *swm = [CKSoftwareMap sharedSoftwareMap];
    for (CKSoftwareProduct *p in [swm allProducts]) {
        [products addObject:[p productAsDictionary]];
    }
    return products;
}

- (NSString *)installedProductsAsJSON
{
    NSError *error = nil;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self installedProducts]
                                                       options:0
                                                         error:&error];
    if (! jsonData) {
        qlerror(@"Got an error: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    return jsonString;
}

- (NSArray *)availableUpdates
{
    NSMutableArray *products = [NSMutableArray new];
    CKUpdateController *updateController = [CKUpdateController sharedUpdateController];
    for (CKSoftwareProduct *p in [updateController availableUpdates]) {
        [products addObject:[p productAsDictionary]];
    }
    
    return products;
}

- (NSString *)availableUpdatesAsJSON
{
    NSError *error = nil;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self availableUpdates]
                                                       options:0
                                                         error:&error];
    if (! jsonData) {
        qlerror(@"Got an error: %@", error);
    } else {
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    return jsonString;
}
@end
