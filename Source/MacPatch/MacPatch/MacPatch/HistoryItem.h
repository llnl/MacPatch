//
//  HistoryItem.h
//
//  Created by   on 12/16/14
//  Copyright (c) 2014 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>



@interface HistoryItem : NSObject <NSCoding, NSCopying>

@property (nonatomic, assign) int errorcode;
@property (nonatomic, strong) NSString *mdate;
@property (nonatomic, strong) NSString *rawdata;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) int action;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end
