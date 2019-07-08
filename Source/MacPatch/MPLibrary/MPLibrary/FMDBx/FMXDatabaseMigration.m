//
//  FMXDatabaseMigration.m
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import "FMXDatabaseMigration.h"
#import "FMDatabase.h"
#import "FMResultSet.h"

@implementation FMXDatabaseMigration

/**
 *  Init with a schema version table name.
 *
 *  @param versionTable a schema version table name
 *  @return a instance
 */
- (id)initWithVersionTable:(NSString *)versionTable
{
    self = [super init];
    if (self) {
        self.versionTable = versionTable;
    }
    return self;
}

/**
 *  Init
 *
 *  @return <#return value description#>
 */
- (id)init
{
    self = [super init];
    if (self) {
        // Default version schema table name is `schema_version`.
        self.versionTable = @"schema_version";
    }
    return self;
}

/**
 *  Prepare process for migration.
 *
 *  @param configuration a FMXDatabaseConfiguration instance
 */
- (void)prepareMigrationWithConfiguration:(FMXDatabaseConfiguration *)configuration
{
    self.configuration = configuration;
    
    FMDatabase *db = [self.configuration database];
    [db open];
    
    // Check existing schema version table.
    FMResultSet *rs = [db executeQuery:[NSString stringWithFormat:
                                        @"select * from sqlite_master where type='table' and name = '%@'",
                                        self.versionTable]];
    if (![rs next]) {
        // There is not a record.
        // Create schema version table.
        [db beginTransaction];
        [db executeUpdate:[NSString stringWithFormat:
                           @"create table %@ (version INTGER PRIMARY KEY NOT NULL)",
                           self.versionTable]];
        [db executeUpdate:[NSString stringWithFormat:
                           @"insert into %@ (version) values (0)",
                           self.versionTable]];
        [db commit];
        NSLog(@"[FMDBx] Created version table: %@", self.versionTable);
    }
    
    // Set up current version.
    rs = [db executeQuery:[NSString stringWithFormat:@"select version from %@", self.versionTable]];
    if ([rs next]) {
        self.currentVersion = [rs intForColumn:@"version"];
    } else {
        // Initial version is `0`.
        self.currentVersion = 0;
    }
    
    [db close];
}

/**
 *  Migrate database.
 *  You must override this method in the subclass.
 */
-(void)migrate
{
}

/**
 *  Migrate up process.
 *
 *  @param version version number
 *  @param action  migration process.
 */
- (void)upToVersion:(int)version action:(void (^)(FMDatabase *))action
{
    if (version <= self.currentVersion) {
        // check version.
        return;
    }
    
    FMDatabase *db = [self.configuration database];
    [db open];
    [db beginDeferredTransaction];

    NSLog(@"[FMDBx] Migrating to %d", version);
    action(db);
    NSLog(@"[FMDBx] Migrated to %d", version);
    
    // Update schema version.
    [db executeUpdate:[NSString stringWithFormat:@"update %@ set version = %d", self.versionTable, version]];
    self.currentVersion = version;
    
    [db commit];
    [db close];
}

@end
