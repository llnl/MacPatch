//
//  History.h
//  FMDBme
//
//  Created by Charles Heizer on 10/23/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface History : NSObject <NSCoding, NSCopying>


@property (nonatomic, strong) NSString *id;
@property (nonatomic) NSInteger type;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, strong) NSString *action;
@property (nonatomic) NSInteger result_code;
@property (nonatomic, strong) NSString *error_msg;
@property (nonatomic, strong) NSDate *cdate;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end
