//
//  NSMetadataQuery+Synchronous.h
//  TestPercent
//
//  Created by Heizer, Charles on 7/30/14.
//  Copyright (c) 2014 Lawrence Livermore National Laboratory. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMetadataQuery (Synchronous)

// search everywhere, returns an array of NSMetadataItem objects
- (NSArray *)resultsForSearchString:(NSString *)searchString;
// limit the search to specific folders, returns an array of NSMetadataItem objects
- (NSArray *)resultsForSearchString:(NSString *)searchString inFolders:(NSSet *)paths;

@end
