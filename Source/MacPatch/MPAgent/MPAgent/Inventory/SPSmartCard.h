//
//  SPSmartCard.h
//  MPAgent
//
//  Created by Charles Heizer on 9/1/20.
//  Copyright © 2020 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SPSmartCard : NSObject

- (NSArray *)parseXMLFile:(NSString *)xmlFile;

- (NSArray *)getSPSmartCardReaders:(NSArray *)spData;
- (NSArray *)getSPSmartCardReaderDrivers:(NSArray *)spData;
- (NSArray *)getSPSmartCardTokendDrivers:(NSArray *)spData;
- (NSArray *)getSPSmartCardDrivers:(NSArray *)spData;

@end
