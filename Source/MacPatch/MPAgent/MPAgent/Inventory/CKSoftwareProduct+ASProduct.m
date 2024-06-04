//
//  CKSoftwareProduct+ASProduct.m
//  MyAppStore
//
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

#import "CKSoftwareProduct+ASProduct.h"
#import "NSDate+Helper.h"

@implementation CKSoftwareProduct (CKSoftwareProduct)

static id ObjectOrNA(id object)
{
    return object ?: @"NA";
}

- (NSDictionary *)productAsDictionary
{
    NSDictionary *_product = @{
                               @"expectedStoreVersion":ObjectOrNA([self.expectedStoreVersion stringValue]),
                               @"expectedBundleVersion":ObjectOrNA(self.expectedBundleVersion),
                               @"isLegacyApp":self.isLegacyApp ? @"YES":@"NO",
                               @"isMachineLicensed":self.expectedStoreVersion ? @"YES":@"NO",
                               @"vppLicenseCancellationReason":ObjectOrNA(self.vppLicenseCancellationReason),
                               @"vppLicenseRenewalDate":ObjectOrNA([NSDate stringFromDate:self.vppLicenseRenewalDate withFormat:@"yyyy-MM-dd"]),
                               @"vppLicenseExpirationDate":ObjectOrNA([NSDate stringFromDate:self.vppLicenseExpirationDate withFormat:@"yyyy-MM-dd"]),
                               @"vppLicenseOrganizationName":ObjectOrNA(self.vppLicenseOrganizationName),
                               @"vppLicenseRevoked":self.vppLicenseRevoked ? @"YES":@"NO",
                               @"isVPPLicensed":self.isVPPLicensed ? @"YES":@"NO",
                               @"installed":self.installed ? @"YES":@"NO",
                               @"versionIdentifier":ObjectOrNA([self.versionIdentifier stringValue]),
                               @"itemIdentifier":ObjectOrNA([self.itemIdentifier stringValue]),
                               @"receiptType":ObjectOrNA(self.receiptType),
                               @"bundlePath":ObjectOrNA(self.bundlePath),
                               @"bundleVersion":ObjectOrNA(self.bundleVersion),
                               @"bundleIdentifier":ObjectOrNA(self.bundleIdentifier),
                               @"accountIdentifier":ObjectOrNA(self.accountIdentifier),
                               @"accountOpaqueDSID":ObjectOrNA(self.accountOpaqueDSID)
                               };
    return _product;
}
- (NSString *)productAsJSONString
{
    NSError *error = nil;
    NSString *jsonString = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self productAsDictionary]
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
