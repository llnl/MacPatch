//
//  DBInstalledSoftware.h
//  FMDBXv2
//
//  Created by Charles Heizer on 11/7/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import "FMXModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DBInstalledSoftware : FMXModel

@property (strong, nonatomic) NSNumber *id;
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *suuid;
@property (strong, nonatomic) NSString *tuuid;
@property (strong, nonatomic) NSString *uninstall;
@property (strong, nonatomic) NSNumber *has_uninstall;
@property (strong, nonatomic) NSString *json_data;
@property (strong, nonatomic) NSDate *install_date;

@end

NS_ASSUME_NONNULL_END
