//
//  MPASUSCatalogs.m
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

#import "Logger.h"
#import "MPASUSCatalogs.h"
#import "MPSystemInfo.h"
#import "Suserver.h"


@interface MPASUSCatalogs ()
{
    MPSettings      *settings;
}

// Helper method to check if URL is valid and returns expected status code
- (BOOL)isURLValidWithTimeout:(NSString *)urlString expectedStatusCode:(NSInteger)statusCode timeoutInterval:(NSTimeInterval)timeout;

@end

@implementation MPASUSCatalogs

-(id)init
{
    self = [super init];
	if (self)
    {
        settings = [MPSettings sharedInstance];
    }
    return self;
}

#pragma mark -

- (BOOL)writeCatalogURL:(NSString *)aCatalogURL
{
	BOOL result = TRUE;

	@try
    {
        NSDictionary *osVerInfo = [MPSystemInfo osVersionOctets];
        if ([[osVerInfo objectForKey:@"major"] intValue] >= 11) {
            LogInfo(@"Apple Software Catalogs are no longer supported.");
            return result;
        }
        
		// 10.14 and higher and not Apple CatalogURL
		if ([[osVerInfo objectForKey:@"minor"] intValue] >= 14)
		{
			// Allow sustom softwareupdate server like reposado
			if (![aCatalogURL containsString:@".apple.com"])
			{
				[NSTask launchedTaskWithLaunchPath:@"/usr/bin/defaults" arguments:@[@"write",@"/Library/Preferences/com.apple.SoftwareUpdate",@"SUDisableEVCheck",@"-bool",@"YES"]];
			}
		}
		// Set the catalog now
		// For Mac OS X 10.10 or higher
		LogInfo(@"Setting catalog using softwareupdate, to %@",aCatalogURL);
		[NSTask launchedTaskWithLaunchPath:@"/usr/sbin/softwareupdate" arguments:[NSArray arrayWithObjects:@"--set-catalog",aCatalogURL,nil]];
	}
	@catch ( NSException *e )
    {
		LogError(@"Error unable to set CatalogURL.");
		result = FALSE;
	}
	
	return result;
}

- (BOOL)disableCatalogURL
{
	// Disabled this, using interceptor now...
	//return [self writeCatalogURL:@"http://127.0.0.1:8088/index.sucatalog"];
	return YES;
}

- (BOOL)resetCatalogURL
{
    NSDictionary *osVerInfo = [MPSystemInfo osVersionOctets];
    if ([[osVerInfo objectForKey:@"major"] intValue] >= 11) {
        // Not supported on macOS 11 and higher
        return YES;
    }
    
	LogInfo(@"Reset CatalogURL to default.");
	[NSTask launchedTaskWithLaunchPath:@"/usr/sbin/softwareupdate" arguments:@[@"--clear-catalog"]];
	return YES;
}

- (NSString *)currentCatalogURL
{
	NSString *result = @"";
	NSDictionary *asusPrefs = [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/com.apple.SoftwareUpdate.plist"];
	if (asusPrefs[@"CatalogURL"])
	{
		result = [asusPrefs[@"CatalogURL"] trim];
	}
	return result;
}

#pragma mark - New methods

- (BOOL)checkAndSetCatalogURL
{
    NSArray *suServers = settings.suservers;
    if (suServers.count <= 0) {
        LogInfo(@"Software update server list is empty. Can not set CatalogURL");
		[self resetCatalogURL];
        return YES;
    }
    
    NSString *newCatalogURL = NULL;
    for (Suserver *server in suServers)
    {
        if ([self isURLValidWithTimeout:server.catalogURL expectedStatusCode:200 timeoutInterval:10.0])
        {
            LogDebug(@"SU Catalog verified: %@",server.catalogURL);
            newCatalogURL = server.catalogURL;
            break;
        }
        else
        {
            LogError(@"CatalogURL: %@ did not return 200 or is unreachable.",server.catalogURL);
            continue;
        }
    }
    
    // No valid suserver
    if (newCatalogURL == NULL)
        return NO;
	
	// Catalog is already set, no need to reset it
	if ([newCatalogURL isEqualToString:[self currentCatalogURL]]) return YES;

	// Write and return
    return [self writeCatalogURL:newCatalogURL];
}

#pragma mark - Helper Methods

- (BOOL)isURLValidWithTimeout:(NSString *)urlString expectedStatusCode:(NSInteger)statusCode timeoutInterval:(NSTimeInterval)timeout
{
    if (!urlString || [urlString length] == 0) {
        return NO;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        LogError(@"Invalid URL: %@", urlString);
        return NO;
    }

    __block BOOL result = NO;
    __block BOOL completed = NO;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = timeout;
    config.timeoutIntervalForResource = timeout;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:timeout];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        if (error) {
            LogError(@"URL check failed for %@: %@", urlString, error.localizedDescription);
            result = NO;
        }
        else if ([response isKindOfClass:[NSHTTPURLResponse class]])
        {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == statusCode) {
                result = YES;
            } else {
                LogDebug(@"URL %@ returned status code %ld, expected %ld",
                        urlString, (long)httpResponse.statusCode, (long)statusCode);
                result = NO;
            }
        }
        else
        {
            result = NO;
        }

        completed = YES;
    }];

    [task resume];

    // Wait for completion with timeout
    NSDate *timeoutDate = [NSDate dateWithTimeIntervalSinceNow:timeout + 1.0];
    while (!completed && [[NSDate date] compare:timeoutDate] == NSOrderedAscending) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    [session finishTasksAndInvalidate];

    return result;
}

@end
