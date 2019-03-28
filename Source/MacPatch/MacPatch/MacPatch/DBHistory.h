//
//  DBHistory.h
//  FMDBXv2
//
//  Created by Charles Heizer on 11/7/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import "FMXModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DBHistory : FMXModel

@property (strong, nonatomic) NSNumber *id;
@property (strong, nonatomic) NSNumber *type;
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *uuid;
@property (strong, nonatomic) NSString *action;
@property (strong, nonatomic) NSNumber *result_code;
@property (strong, nonatomic) NSString *error_msg;
@property (strong, nonatomic) NSDate *cdate;

@end

NS_ASSUME_NONNULL_END
