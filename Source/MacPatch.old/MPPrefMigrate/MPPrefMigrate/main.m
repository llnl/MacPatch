//
//  main.m
//  MPPrefMigrate
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.
 
 This file is part of MacPatch, a program for installing and patching
 software.
 
 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.
 
 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.
 
 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <getopt.h>
#include <unistd.h>
#include "MPTaskMigrater.h"

#define APPVERSION	@"1.0"
#define APPNAME		@"mpPrefMigrate"

void usage(void);

int main (int argc, char * argv[])
{
    @autoreleasepool
    {
        int forTasks = 0;
    
		NSString *fromFile = NULL;
		NSString *toFile = NULL;
		
		// Setup argument processing
		int c;
		while (1)
		{
			static struct option long_options[] =
			{
				{"FromFile"			,required_argument	,0, 'f'},
				{"ToFile"			,required_argument	,0, 't'},
                {"FromFile"			,required_argument	,0, 'F'},
				{"ToFile"			,required_argument	,0, 'T'},
				{"version"			,no_argument		,0, 'v'},
				{"help"				,no_argument		,0, 'h'},
				{0, 0, 0, 0}
			};
			// getopt_long stores the option index here.
			int option_index = 0;
			c = getopt_long (argc, argv, "f:t:F:T:vh", long_options, &option_index);
			
			// Detect the end of the options.
			if (c == -1)
				break;
			
			switch (c)
			{
				case 'f':
					fromFile = [NSString stringWithUTF8String:optarg];
					break;
                case 't':
					toFile = [NSString stringWithUTF8String:optarg];
					break;
                case 'F':
					fromFile = [NSString stringWithUTF8String:optarg];
                    forTasks++;
					break;
                case 'T':
					toFile = [NSString stringWithUTF8String:optarg];
                    forTasks++;
					break;
				case 'v':
					printf("%s\n",[APPVERSION UTF8String]);
					return 0;
				case 'h':
                    usage();
                    return 0;
				case '?':
                    usage();
                    return 0;
				default:
					printf("Silly Rabbit, Trix are for Kids!\n");
					usage();
			}
		}
		
		if (optind < argc) {
            while (optind < argc) {
                printf ("Invalid argument %s ", argv[optind++]);
            }
            usage();
            exit(0);
        }
		
		// Make sure the user is root or is using sudo
		if (getuid()) {
			printf("You must be root to run this app. Try using sudo.\n");
            exit(0);
		}
    
		NSFileManager *fm = [NSFileManager defaultManager];
		if (![fm fileExistsAtPath:fromFile]) {
			fprintf(stderr,"Error %s file not found.",[fromFile UTF8String]);
			exit(1);
		}
    
		if (![fm fileExistsAtPath:toFile]) {
			fprintf(stderr,"Error %s file not found.",[toFile UTF8String]);
			exit(1);
		}
        if (![[toFile lastPathComponent] isEqualTo:@"gov.llnl.mp.tasks.plist"]) {
			fprintf(stderr,"Error from file must be %s.",[[toFile lastPathComponent] UTF8String]);
			exit(1);
		}
    
    NSMutableArray *toFileArray;
    if (forTasks == 2)
    {
        NSMutableArray *mergedArray = [NSMutableArray array];
        [mergedArray addObjectsFromArray:[[NSDictionary dictionaryWithContentsOfFile:fromFile] objectForKey:@"mpTasks"]]; // Orig
        [mergedArray addObjectsFromArray:[[NSDictionary dictionaryWithContentsOfFile:toFile] objectForKey:@"mpTasks"]]; //New
        
        MPTaskMigrater *tm = [[MPTaskMigrater alloc] init];
        toFileArray = [NSMutableArray array];
        for (NSDictionary *d in mergedArray) {
            int r = [tm containsDict:toFileArray dict:d];
            if ( r == -1) {
                [toFileArray addObject:d];
            } else if (r >= 0) {
                [toFileArray replaceObjectAtIndex:r withObject:d];
            }
        }
        
    } else {
        NSDictionary *fromFileDict = [NSDictionary dictionaryWithContentsOfFile:fromFile];
        toFileArray = [[NSDictionary dictionaryWithContentsOfFile:toFile] objectForKey:@"mpTasks"];
        
        for (NSDictionary *dict in toFileArray)
        {
            if ([[dict objectForKey:@"cmd"] isEqualTo:@"kMPVulScan"]) {
                if ([[fromFileDict allKeys] containsObject:@"DailyScanTime"]) {
                    fprintf(stdout,"Migrating settings for DailyScanTime.");
                    [dict setValue:[NSString stringWithFormat:@"RECURRING@Daily@%@",[fromFileDict objectForKey:@"DailyScanTime"]] forKey:@"interval"];
                }
            }
            if ([[dict objectForKey:@"cmd"] isEqualTo:@"kMPVulUpdate"]) {
                if ([[fromFileDict allKeys] containsObject:@"PatchInstallTime"]) {
                    fprintf(stdout,"Migrating settings for PatchInstallTime.");
                    [dict setValue:[NSString stringWithFormat:@"RECURRING@%@@%@",[fromFileDict objectForKey:@"PatchInstallDay"],[fromFileDict objectForKey:@"PatchInstallTime"]] forKey:@"interval"];
                }
            }
        }
		}
    
		NSDictionary *_updatedTasks = [NSDictionary dictionaryWithObject:toFileArray forKey:@"mpTasks"];
		[_updatedTasks writeToFile:toFile atomically:YES];
    }
    return 0;
}

void usage(void) {
    
	printf("%s\n",[APPNAME UTF8String]);
	printf("Version: %s\n\n",[APPVERSION UTF8String]);
	printf("Usage: %s [OPTION]\n\n",[APPNAME UTF8String]);
	printf(" -f \tFrom file (gov.llnl.swuad.plist).\n");
	printf(" -t \tTo file (gov.llnl.mp.tasks.plist).\n");
    printf("\n");
    printf(" Merge: gov.llnl.mp.tasks.plist");
    printf(" \t-F \tFrom file (gov.llnl.mp.tasks.plist).\n");
	printf(" \t-T \tTo file (gov.llnl.mp.tasks.plist).\n");
	printf("\n -v \tDisplay version info. \n");
	printf("\n");
    exit(0);
}
