//
//  DBInstalledSoftware.m
//  FMDBXv2
//
//  Created by Charles Heizer on 11/7/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import "DBInstalledSoftware.h"

@implementation DBInstalledSoftware

+ (void)defaultTableMap:(FMXTableMap *)table
{
	[table setTableName:@"installed_software"];
	[table hasIntIncrementsColumn:@"id"];   // defines as a primary key.
	[table hasStringColumn:@"name"];
	[table hasStringColumn:@"suuid"];
	[table hasStringColumn:@"tuuid"];
	[table hasIntColumn:@"has_uninstall"];
	[table hasStringColumn:@"uninstall"];
	[table hasStringColumn:@"json_data"];
	[table hasDateColumn:@"install_date"];
}

@end
