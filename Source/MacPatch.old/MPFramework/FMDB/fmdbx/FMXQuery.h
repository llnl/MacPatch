//
//  FMXQuery.h
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMXModel.h"

@class FMXModel;

@interface FMXQuery : NSObject

@property (assign, nonatomic, readonly) Class modelClass;

- initWithModelClass:(Class)aClass;

- (FMXModel *)modelByPrimaryKey:(id)primaryKeyValue;

- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters;

- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy;


- (FMXModel *)modelByPrimaryKey:(id)primaryKeyValue database:(FMDatabase *)db;

- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters database:(FMDatabase *)db;

- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy database:(FMDatabase *)db;



- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters;

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy;

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit;

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit offset:(NSInteger)offset;


- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters database:(FMDatabase *)db;

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy database:(FMDatabase *)db;

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit database:(FMDatabase *)db;

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit offset:(NSInteger)offset database:(FMDatabase *)db;


- (NSInteger)countWhere:(NSString *)conditions parameters:(NSDictionary *)parameters;

- (NSInteger)countWhere:(NSString *)conditions parameters:(NSDictionary *)parameters database:(FMDatabase *)db;

@end
