//
//  FMXCsvTable.h
//  FMDBx
//
//  Created by KohkiMakimoto on 6/9/14.
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FMXCsvTable : NSObject

+ (void)foreachFileName:(NSString *)fileName process:(void (^)(NSDictionary *row))process;

+ (void)foreachFileName:(NSString *)fileName columnSeparator:(NSString *)separator process:(void (^)(NSDictionary *row))process;

+ (void)foreachURL:(NSURL *)url process:(void (^)(NSDictionary *row))process;

+ (void)foreachURL:(NSURL *)url columnSeparator:(NSString *)separator process:(void (^)(NSDictionary *row))process;

@end
