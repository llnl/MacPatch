//
//  DBMigration.m
//  FMDBXv2
//
//  Created by Charles Heizer on 11/7/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import "DBMigration.h"

@implementation DBMigration

- (void)migrate
{
	[self upToVersion:1 action:^(FMDatabase *db){
		[db executeUpdate:@""
		 "create table installed_software ("
		 "  id integer primary key autoincrement,"
		 "  name text not null,"
		 "  suuid text not null,"
		 "  tuuid text not null,"
		 "  uninstall text,"
		 "  has_uninstall integer not null,"
		 "  json_data text not null,"
		 "  install_date integer not null"
		 ")"
		 ];
		
		[db executeUpdate:@""
		 "create table installed_patch ("
		 "  id integer primary key autoincrement,"
		 "  name text not null,"
		 "  puuid text not null,"
		 "  json_data text not null,"
		 "  install_date integer not null"
		 ")"
		 ];
		
		[db executeUpdate:@""
		 "create table history ("
		 "  id integer primary key autoincrement,"
		 "  type integer not null,"
		 "  name text not null,"
		 "  uuid text not null,"
		 "  action text not null,"
		 "  result_code integer not null,"
		 "  error_msg text,"
		 "  cdate integer not null"
		 ")"
		 ];
	}];
	
	[self upToVersion:2 action:^(FMDatabase *db){
		// ... schema changes for version 2
		[db executeUpdate:@""
		 "create table required_patches ("
		 "  id integer primary key autoincrement,"
		 "  type text not null,"
		 "  patch_id text not null,"
		 "  patch text not null,"
		 "  patch_version text,"
		 "  patch_reboot integer not null,"
		 "  patch_data blob,"
		 "  patch_scandate text"
		 ")"
		 ];
	}];
	
	// ...etc
	
}

@end
