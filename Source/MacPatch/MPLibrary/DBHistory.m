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
	[table setTableName:@"history"];
	[table hasIntIncrementsColumn:@"id"];   // defines as a primary key.
	[table hasIntColumn:@"type"];
	[table hasStringColumn:@"name"];
	[table hasStringColumn:@"uuid"];
	[table hasStringColumn:@"action"];
	[table hasIntColumn:@"result_code"];
	[table hasStringColumn:@"error_msg"];
	[table hasDateColumn:@"cdate"];
}

@end
