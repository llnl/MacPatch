//
//  InstalledSoftware.h
//  FMDBme
//
//  Created by Charles Heizer on 10/24/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface InstalledSoftware : NSObject <NSCoding, NSCopying>

@property (strong, nonatomic) NSString *id;
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *suuid;
@property (strong, nonatomic) NSString *tuuid;
@property (strong, nonatomic) NSString *uninstall;
@property (assign, nonatomic) NSInteger has_uninstall;
@property (strong, nonatomic) NSString *json_data;
@property (strong, nonatomic) NSDate *install_date;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end

