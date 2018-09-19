//
//  FMXQuery.m
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import "FMXQuery.h"
#import "FMXModel.h"
#import "FMXTableMap.h"
#import "FMXColumnMap.h"
#import "FMDatabase.h"
#import "FMResultSet.h"

@interface FMXQuery ()

@property (readwrite) Class modelClass;

@end

@implementation FMXQuery

- (id)initWithModelClass:(Class)aClass
{
    self = [super init];
    if (self) {
        self.modelClass = aClass;
    }
    return self;
}

- (FMXModel *)modelByPrimaryKey:(id)primaryKeyValue
{
    return [self modelByPrimaryKey:primaryKeyValue database:nil];
}

- (FMXModel *)modelByPrimaryKey:(id)primaryKeyValue database:(FMDatabase *)db
{
    FMXModel *model = nil;
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }

    FMResultSet *rs = [db executeQuery:[NSString stringWithFormat:@"select * from `%@` where `%@` = ?",
                                        table.tableName,
                                        table.primaryKeyName], primaryKeyValue];
    if ([rs next]) {
        model = [self.modelClass modelWithResultSet:rs];
    }
    
    if (isPrivateConnection) {
        [db close];
    }
    
    return model;
}

- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters
{
    return [self modelWhere:conditions parameters:parameters database:nil];
}

- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters database:(FMDatabase *)db
{
    FMXModel *model = nil;
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }
    
    NSString *sql = [NSString stringWithFormat:@"select * from `%@` where %@ limit 1",
                     table.tableName,
                     [self validatedConditionsString:conditions]];
    FMResultSet *rs = [db executeQuery:sql withParameterDictionary:parameters];
    
    if ([rs next]) {
        model = [self.modelClass modelWithResultSet:rs];
    }
    
    if (isPrivateConnection) {
        [db close];
    }
    
    return model;
}
- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy
{
    return [self modelWhere:conditions parameters:parameters orderBy:orderBy database:nil];
}

- (FMXModel *)modelWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy database:(FMDatabase *)db
{
    if (orderBy == nil) {
        return [self modelWhere:conditions parameters:parameters];
    }
    
    FMXModel *model = nil;
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }
    
    NSString *sql = [NSString stringWithFormat:@"select * from `%@` where %@ order by %@ limit 1",
                     table.tableName,
                     [self validatedConditionsString:conditions],
                     orderBy
                     ];
    FMResultSet *rs = [db executeQuery:sql withParameterDictionary:parameters];
    
    if ([rs next]) {
        model = [self.modelClass modelWithResultSet:rs];
    }
    
    if (isPrivateConnection) {
        [db close];
    }
    
    return model;
}

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters
{
    return [self modelsWhere:conditions parameters:parameters database:nil];
}

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters database:(FMDatabase *)db
{
    NSMutableArray *models = [[NSMutableArray alloc] init];
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }

    NSString *sql = [NSString stringWithFormat:@"select * from `%@` where %@",
                     table.tableName,
                     [self validatedConditionsString:conditions]];
    FMResultSet *rs = [db executeQuery:sql withParameterDictionary:parameters];
    
    while ([rs next]) {
        [models addObject:[self.modelClass modelWithResultSet:rs]];
    }

    if (isPrivateConnection) {
        [db close];
    }
    
    return models;
}

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy
{
    return [self modelsWhere:conditions parameters:parameters orderBy:orderBy database:nil];
}

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy database:(FMDatabase *)db
{
    if (orderBy == nil) {
        return [self modelsWhere:conditions parameters:parameters];
    }
    
    NSMutableArray *models = [[NSMutableArray alloc] init];
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }

    NSString *sql = [NSString stringWithFormat:@"select * from `%@` where %@ order by %@",
                     table.tableName,
                     [self validatedConditionsString:conditions],
                     orderBy
                     ];
    FMResultSet *rs = [db executeQuery:sql withParameterDictionary:parameters];
    
    while ([rs next]) {
        [models addObject:[self.modelClass modelWithResultSet:rs]];
    }

    if (isPrivateConnection) {
        [db close];
    }
    
    return models;
}

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit
{
    return [self modelsWhere:conditions parameters:parameters orderBy:orderBy limit:limit database:nil];
}

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit database:(FMDatabase *)db
{
    NSMutableArray *models = [[NSMutableArray alloc] init];
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }
    NSString *sql = [NSString stringWithFormat:@"select * from `%@` where %@ order by %@ limit %ld",
                     table.tableName,
                     [self validatedConditionsString:conditions],
                     orderBy,
                     (long)limit
                     ];
    FMResultSet *rs = [db executeQuery:sql withParameterDictionary:parameters];
    
    while ([rs next]) {
        [models addObject:[self.modelClass modelWithResultSet:rs]];
    }
    if (isPrivateConnection) {
        [db close];
    }
    
    return models;
}
- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit offset:(NSInteger)offset
{
    return [self modelsWhere:conditions parameters:parameters orderBy:orderBy limit:limit offset:offset database:nil];
}

- (NSArray *)modelsWhere:(NSString *)conditions parameters:(NSDictionary *)parameters orderBy:(NSString *)orderBy limit:(NSInteger)limit offset:(NSInteger)offset database:(FMDatabase *)db
{
    NSMutableArray *models = [[NSMutableArray alloc] init];
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }
    NSString *sql = [NSString stringWithFormat:@"select * from `%@` where %@ order by %@ limit %ld offset %ld",
                     table.tableName,
                     [self validatedConditionsString:conditions],
                     orderBy,
                     (long)limit,
                     (long)offset
                     ];
    FMResultSet *rs = [db executeQuery:sql withParameterDictionary:parameters];
    
    while ([rs next]) {
        [models addObject:[self.modelClass modelWithResultSet:rs]];
    }
    if (isPrivateConnection) {
        [db close];
    }
    
    return models;
}

- (NSInteger)countWhere:(NSString *)conditions parameters:(NSDictionary *)parameters
{
    return [self countWhere:conditions parameters:parameters database:nil];
}

- (NSInteger)countWhere:(NSString *)conditions parameters:(NSDictionary *)parameters database:(FMDatabase *)db
{
    NSInteger count = 0;
    
    FMXTableMap *table = [[FMXDatabaseManager sharedManager] tableForModel:self.modelClass];
    BOOL isPrivateConnection = NO;
    if (!db) {
        isPrivateConnection = YES;
        db = [[FMXDatabaseManager sharedManager] databaseForModel:self.modelClass];
        [db open];
    }

    NSString *sql = [NSString stringWithFormat:@"select count(*) as count from `%@` where %@",
                     table.tableName,
                     [self validatedConditionsString:conditions]];
    FMResultSet *rs = [db executeQuery:sql withParameterDictionary:parameters];
    
    if ([rs next]) {
        count = [rs intForColumn:@"count"];
    }
    
    if (isPrivateConnection) {
        [db close];
    }
    
    return count;
}

- (NSString *)validatedConditionsString:(NSString *)conditions
{
    if (conditions == nil || [conditions isEqualToString:@""]) {
        conditions = [NSString stringWithFormat:@"1 = 1"];
    }
    
    return conditions;
}

@end
