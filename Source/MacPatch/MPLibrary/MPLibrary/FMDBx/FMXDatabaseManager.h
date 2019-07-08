//
//  FMXDatabaseManager.h
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMXDatabaseMigration.h"
#import "FMXDatabaseConfiguration.h"
#import "FMXTableMap.h"
#import "FMXModel.h"
#import "FMXHelpers.h"
#import "FMXQuery.h"

@class FMXDatabaseMigration;
@class FMXDatabaseConfiguration;
@class FMXQuery;

@interface FMXDatabaseManager : NSObject

+ (FMXDatabaseManager *)sharedManager;

- (void)registerDatabaseWithName:(NSString *)database
                            path:(NSString *)databasePath
                       migration:(FMXDatabaseMigration *)migration;

- (void)registerDefaultDatabaseWithPath:(NSString *)databasePath
                              migration:(FMXDatabaseMigration *)migration;

- (void)destroyDatabase:(NSString *)database;

- (void)destroyDefaultDatabase;

- (FMXDatabaseConfiguration *)configuration:(NSString *)database;

- (FMXDatabaseConfiguration *)defaultConfiguration;

- (FMDatabase *)database:(NSString *)database;

- (FMDatabase *)databaseForModel:(Class)modelClass;

- (FMDatabase *)defaultDatabase;

- (FMXTableMap *)tableForModel:(Class)modelClass;

- (FMXQuery *)queryForModel:(Class)modelClass;

@end
