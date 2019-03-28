//
//  FMXDatabaseManager.m
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import "FMXDatabaseManager.h"
#import <objc/runtime.h>

static FMXDatabaseManager *sharedInstance = nil;

@interface FMXDatabaseManager()

@property (strong, nonatomic) NSMutableDictionary *configurations;
@property (strong, nonatomic) NSMutableDictionary *tables;

@end

@implementation FMXDatabaseManager

/**
 *  Get a shared instance.
 *
 *  @return shared instance
 */
+ (FMXDatabaseManager *)sharedManager {
    @synchronized(self) {
        if (!sharedInstance) {
            sharedInstance = [[self alloc] init];
        }
    }
    return sharedInstance;
}

/**
 *  Init.
 *
 *  @return initialized instance
 */
- (id)init {
    self = [super init];
    if (self) {
        self.configurations = [[NSMutableDictionary alloc] init];
        self.tables = [[NSMutableDictionary alloc] init];
    }
    return self;
}

/**
 *  Register a database.
 *
 *  @param database     database name
 *  @param databasePath database file path
 *  @param migration    migration object
 */
-(void)registerDatabaseWithName:(NSString *)database path:(NSString *)databasePath migration:(FMXDatabaseMigration *)migration {
    // Register the configuration.
    FMXDatabaseConfiguration *configuration = [[FMXDatabaseConfiguration alloc] initWithDatabasePath:databasePath];
    [self.configurations setObject:configuration forKey:database];
    NSLog(@"[FMDBx] Registered database [%@]: %@", database, configuration.databasePathInDocuments);
    
    // Migration process if it exists.
    if (migration) {
        [migration prepareMigrationWithConfiguration: configuration];
        [migration migrate];
        NSLog(@"[FMDBx] Registered database [%@] version: %d", database, migration.currentVersion);
    }    
}

/**
 *  Register a default database.
 *
 *  @param databasePath database file path
 *  @param migration    migration object
 */
- (void)registerDefaultDatabaseWithPath:(NSString *)databasePath migration:(FMXDatabaseMigration *)migration {
    [self registerDatabaseWithName:@"default" path:databasePath migration:migration];
}

/**
 *  Destroy database.
 *
 *  @param database database name
 */
- (void)destroyDatabase:(NSString *)database {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [[self configuration:database] databasePathInDocuments];
    if (path && [fm fileExistsAtPath:path]) {
        [fm removeItemAtPath:path error:nil];
    }
}

/**
 *  Destroy default database.
 */
- (void)destroyDefaultDatabase {
    [self destroyDatabase:@"default"];
}

/**
 *  Get a configuration.
 *
 *  @param database database name
 *
 *  @return configuration object
 */
- (FMXDatabaseConfiguration *)configuration:(NSString *)database {
    return [self.configurations objectForKey:database];
}

/**
 *  Get a default configuration.
 *
 *  @return configuration object
 */
- (FMXDatabaseConfiguration *)defaultConfiguration {
    return [self configuration:@"default"];
}

/**
 *  Get a database.
 *
 *  @param database database name
 *
 *  @return FMDatabase object
 */
- (FMDatabase *)database:(NSString *)database {
    FMXDatabaseConfiguration *configuration = [self configuration:database];
    if (!configuration) {
        return nil;
    }
    return [configuration database];
}

- (FMDatabase *)databaseForModel:(Class)modelClass {
    return [self database:[self tableForModel:modelClass].database];
}

/**
 *  Get default database
 *
 *  @return FMDatabase object
 */
- (FMDatabase *)defaultDatabase {
    return [self database:@"default"];
}

/**
 *  Get a table map
 *
 *  @param modelClass model class
 *
 *  @return table map object
 */

- (FMXTableMap *)tableForModel:(Class)modelClass {
    FMXTableMap *table = [self.tables objectForKey:NSStringFromClass(modelClass)];
    if (!table) {
        table = [[FMXTableMap alloc] init];
        table.database = @"default";
        table.tableName = FMXDefaultTableNameFromModelName(NSStringFromClass(modelClass));
        
        // default table map
        [modelClass performSelector:@selector(defaultTableMap:) withObject:table];
        
        /*
        TODO: Initializing table map at runtime.
         
        // initializing tablemap automatically from the properties.
        objc_property_t *properties;
        unsigned int count;
        int i;
        properties = class_copyPropertyList(modelClass, &count);
        for (i = 0; i < count; i++) {
            objc_property_t property = properties[i];
            NSString *propertyName = [NSString stringWithUTF8String:property_getName(property)];
            NSString *columnName = FMXSnakeCaseFromCamelCase(propertyName);
            NSString *propertyType = nil;
        }
        */
        
        // Override by model.
        [modelClass performSelector:@selector(overrideTableMap:) withObject:table];
        
        // Cache the definition in the manager.
        [self.tables setObject:table forKey:NSStringFromClass(modelClass)];
    }
    return table;
}

/**
 *  Get a query
 *
 *  @param modelClass model class
 *
 *  @return query object
 */
- (FMXQuery *)queryForModel:(Class)modelClass {
    return [[FMXQuery alloc] initWithModelClass:modelClass];
}

@end
