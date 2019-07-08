//
//  DBHistory.m
//  FMDBXv2
//
//  Created by Charles Heizer on 11/7/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import "DBHistory.h"

@implementation DBHistory

+ (void)defaultTableMap:(FMXTableMap *)table
{
	[table hasIntIncrementsColumn:@"id"];   // defines as a primary key.
	[table hasIntColumn:@"type"];
	[table hasStringColumn:@"name"];
	[table hasStringColumn:@"suuid"];
	[table hasStringColumn:@"tuuid"];
	[table hasBoolColumn:@"has_uninstall"];
	[table hasStringColumn:@"uninstall"];
	[table hasStringColumn:@"json_data"];
	[table hasDateColumn:@"installed_date"];
}

@end
