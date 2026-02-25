//
//  MPAppStoreManager.m
//  MPAgent
//
//  Created by Heizer, Charles on 1/9/26.
//  Copyright © 2026 LLNL. All rights reserved.
//

#import "MPAppStoreManager.h"
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>

@interface MPAppStoreManager ()

@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, strong) NSMutableArray *installedAppBundleIDs;

@end

@implementation MPAppStoreManager

- (instancetype)init {
    
    self = [super init];
    if (self) {
        _semaphore = dispatch_semaphore_create(0);
        _installedAppBundleIDs = [NSMutableArray array];
    }
    return self;
}

- (void)getInstalledAppStoreApps {
    // First, get all installed applications
    NSArray *installedApps = [self getAllInstalledApps];
    
    NSLog(@"Found %lu installed applications", (unsigned long)installedApps.count);
    
    // Filter for App Store apps (those with receipt)
    NSMutableArray *appStoreApps = [NSMutableArray array];
    
    for (NSDictionary *appInfo in installedApps) {
        NSString *bundleID = appInfo[@"bundleID"];
        NSString *path = appInfo[@"path"];
        
        if ([self isAppStoreApp:path]) {
            [appStoreApps addObject:appInfo];
            [self.installedAppBundleIDs addObject:bundleID];
            
            NSLog(@"\n=== App Store App ===");
            NSLog(@"Name: %@", appInfo[@"name"]);
            NSLog(@"Bundle ID: %@", bundleID);
            NSLog(@"Version: %@", appInfo[@"version"]);
            NSLog(@"Path: %@", path);
        }
    }
    
    NSLog(@"\n\nTotal App Store apps found: %lu", (unsigned long)appStoreApps.count);
    
    // Optionally, verify receipts for each app
    for (NSDictionary *appInfo in appStoreApps) {
        [self verifyAppReceipt:appInfo[@"path"]];
    }
}

- (NSArray *)getAllInstalledApps {
    NSMutableArray *apps = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Check common application directories
    NSArray *appDirs = @[
        @"/Applications",
        @"/System/Applications",
        [@"~/Applications" stringByExpandingTildeInPath]
    ];
    
    for (NSString *appDir in appDirs) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:appDir error:nil];
        
        for (NSString *item in contents) {
            if ([item hasSuffix:@".app"]) {
                NSString *fullPath = [appDir stringByAppendingPathComponent:item];
                NSDictionary *appInfo = [self getAppInfo:fullPath];
                if (appInfo) {
                    [apps addObject:appInfo];
                }
            }
        }
    }
    
    return apps;
}

- (NSDictionary *)getAppInfo:(NSString *)appPath {
    NSBundle *bundle = [NSBundle bundleWithPath:appPath];
    if (!bundle) return nil;
    
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    NSString *displayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    NSString *bundleID = [bundle bundleIdentifier];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    
    if (!bundleID) return nil;
    
    return @{
        @"name": displayName ?: name ?: @"Unknown",
        @"bundleID": bundleID,
        @"version": version ?: @"Unknown",
        @"build": buildVersion ?: @"Unknown",
        @"path": appPath
    };
}

- (BOOL)isAppStoreApp:(NSString *)appPath {
    // Check for App Store receipt
    NSString *receiptPath = [appPath stringByAppendingPathComponent:@"Contents/_MASReceipt/receipt"];
    
    // Check if receipt exists
    BOOL hasReceipt = [[NSFileManager defaultManager] fileExistsAtPath:receiptPath];
    
    if (hasReceipt) {
        return YES;
    }
    
    // Alternative: Check for Mac App Store metadata
    NSString *metadataPath = [appPath stringByAppendingPathComponent:@"Contents/_MASReceipt"];
    BOOL hasMetadata = [[NSFileManager defaultManager] fileExistsAtPath:metadataPath];
    
    return hasMetadata;
}

- (void)verifyAppReceipt:(NSString *)appPath {
    NSString *receiptPath = [appPath stringByAppendingPathComponent:@"Contents/_MASReceipt/receipt"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:receiptPath]) {
        NSData *receiptData = [NSData dataWithContentsOfFile:receiptPath];
        
        if (receiptData) {
            NSLog(@"Receipt found for app at: %@", appPath);
            NSLog(@"Receipt size: %lu bytes", (unsigned long)receiptData.length);
            
            // You can parse the receipt here using ASN.1 parsing
            // or send it to Apple's verification servers
        }
    }
}

// MARK: - StoreKit Product Request (for fetching App Store metadata)

- (void)fetchAppStoreMetadata {
    if (self.installedAppBundleIDs.count == 0) {
        NSLog(@"No App Store apps to fetch metadata for");
        dispatch_semaphore_signal(self.semaphore);
        return;
    }
    
    // Note: SKProductsRequest is primarily for in-app purchases
    // For app metadata, you'd need to use iTunes Search API
    [self fetchMetadataFromiTunesAPI];
}

- (void)fetchMetadataFromiTunesAPI {
    // Build comma-separated bundle IDs
    NSString *bundleIDs = [self.installedAppBundleIDs componentsJoinedByString:@","];
    
    NSString *urlString = [NSString stringWithFormat:
        @"https://itunes.apple.com/lookup?bundleId=%@&country=us&entity=macSoftware",
        [bundleIDs stringByAddingPercentEncodingWithAllowedCharacters:
         [NSCharacterSet URLQueryAllowedCharacterSet]]];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"Error fetching metadata: %@", error);
            } else if (data) {
                [self parseAppStoreMetadata:data];
            }
            dispatch_semaphore_signal(self.semaphore);
        }];
    
    [task resume];
}

- (void)parseAppStoreMetadata:(NSData *)data {
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                        options:0
                                                          error:&error];
    
    if (error) {
        NSLog(@"JSON parsing error: %@", error);
        return;
    }
    
    NSArray *results = json[@"results"];
    NSLog(@"\n\n=== App Store Metadata ===");
    
    for (NSDictionary *result in results) {
        NSLog(@"\nApp: %@", result[@"trackName"]);
        NSLog(@"Bundle ID: %@", result[@"bundleId"]);
        NSLog(@"Version: %@", result[@"version"]);
        NSLog(@"Price: $%@", result[@"price"]);
        NSLog(@"Release Date: %@", result[@"releaseDate"]);
        NSLog(@"Developer: %@", result[@"artistName"]);
        NSLog(@"Category: %@", result[@"primaryGenreName"]);
        NSLog(@"Rating: %@", result[@"averageUserRating"]);
        NSLog(@"App Store URL: %@", result[@"trackViewUrl"]);
    }
}

@end
