//
//  main.m
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
#import "MPAgentUp2DateController.h"
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <unistd.h>

#define APPVERSION	@"3.1.0.0"
#define APPNAME		@"MPAgentUp2Date"

void usage(void);

int main (int argc, char * argv[])
{
    @autoreleasepool {
    
        int a_Type = 0;
	BOOL echoToConsole = NO;
	BOOL verboseLogging = NO;
	
	// Setup argument processing
	int c;
	while (1)
	{
		static struct option long_options[] =
		{
			{"Debug"			,no_argument	    ,0, 'D'},
			{"Scan"				,no_argument	    ,0, 's'},
			{"Update"			,no_argument	    ,0, 'u'},
			{"Echo"				,no_argument		,0, 'e'},
			{"Verbose"			,no_argument		,0, 'V'},
			{"version"			,no_argument		,0, 'v'},
			{"help"				,no_argument		,0, 'h'},
			{0, 0, 0, 0}
		};
		// getopt_long stores the option index here.
		int option_index = 0;
		c = getopt_long (argc, argv, "DsueVvh", long_options, &option_index);
		
		// Detect the end of the options.
		if (c == -1)
			break;
		
		switch (c)
		{
			case 's':
				a_Type = 1;
				break;
			case 'u':
				a_Type = 2;
				break;
			case 'V':
				verboseLogging = YES;
				break;
			case 'D':
				verboseLogging = YES;
				break;
			case 'e':
				echoToConsole = YES;
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
#ifndef DEBUG
		exit(0);
#endif
	}
	
    // Setup Logging
    NSString *_logFile = [NSString stringWithFormat:@"%@/Logs/MPAgentUp2Date.log",MP_ROOT_UPDATE];
    [MPLog setupLogging:_logFile level:lcl_vDebug];
    if (verboseLogging) {
		lcl_configure_by_name("*", lcl_vDebug);
		[LCLLogFile setMirrorsToStdErr:YES];
		logit(lcl_vInfo,@"***** %@ v.%@ started -- Debug Enabled *****", APPNAME, APPVERSION);
	} else {
		lcl_configure_by_name("*", lcl_vInfo);
		if (echoToConsole) {
			[LCLLogFile setMirrorsToStdErr:YES];
            }
		logit(lcl_vInfo,@"***** %@ v.%@ started *****", APPNAME, APPVERSION);
	}
        
	NSFileManager *fm = [NSFileManager defaultManager];
	NSError *error = nil;
	NSArray *files = [fm contentsOfDirectoryAtPath:@"/Users/Shared/.mpUpdate" error:&error];
	
	for(NSString *file in files) {
		[fm removeItemAtPath:[@"/Users/Shared/.mpUpdate" stringByAppendingPathComponent:file] error:&error];
		if(error) {
			logit(lcl_vError,@"Error unable to delete %@",file);
		}
	}
	
        // Run Functions
	MPAgentUp2DateController *_controller = [[MPAgentUp2DateController alloc] init];
	
        if (a_Type == 1) {
		[_controller scanForUpdate];
	} else if (a_Type == 2) {
		[_controller scanAndUpdate];
	} else {
		logit(lcl_vError, @"should never have gotten here!");
	}
        
    }
    return 0;
}

void usage(void) {
    
	printf("%s\n",[APPNAME UTF8String]);
	printf("Version: %s\n\n",[APPVERSION UTF8String]);
	printf("Usage: %s [OPTION]\n\n",[APPNAME UTF8String]);
	printf(" -s \tScan for agent updates.\n");
	printf(" -u \tScan & Update agent.\n");
	printf(" -e \tEcho results to console.\n");
	printf(" -V \tVerbose logging.\n");
	printf("\n -v \tDisplay version info. \n");
	printf("\n");
    exit(0);
}
