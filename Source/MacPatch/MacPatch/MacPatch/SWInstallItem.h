//
//  SWInstallItem.h
//
//  Created by   on 12/16/14
//  Copyright (c) 2014 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>



@interface SWInstallItem : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong) NSString *swuuid;
@property (nonatomic, strong) NSString *mdate;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) double hasUninstall;
@property (nonatomic, strong) NSString *jsonData;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end
