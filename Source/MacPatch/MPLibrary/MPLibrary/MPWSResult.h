//
//  CHWSResult.h
//  MPAgent
//
//  Created by Charles Heizer on 9/15/17.
//  Copyright © 2017 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AppKit/AppKit.h>

@interface MPWSResult : NSObject

@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSString *errormsg;
@property (nonatomic, assign) NSInteger errorno;
@property (nonatomic, strong) NSDictionary *result;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (instancetype)initWithJSONData:(NSData *)data;
- (NSDictionary *)toDictionary;

@end
