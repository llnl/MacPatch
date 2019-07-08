//
//  FMXDatabaseMigration.h
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMXDatabaseConfiguration.h"

@class FMXDatabaseManager;
@class FMXDatabaseConfiguration;

@interface FMXDatabaseMigration : NSObject

@property (strong, nonatomic) NSString *versionTable;
@property (strong, nonatomic) FMXDatabaseConfiguration *configuration;
@property (assign, nonatomic) int currentVersion;

- (id)initWithVersionTable:(NSString *)versionTable;
- (void)prepareMigrationWithConfiguration:(FMXDatabaseConfiguration *)configuration;
- (void)migrate;
- (void)upToVersion:(int)version action:(void (^)(FMDatabase *db))action;

@end
