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
#import "MPAgentExecController.h"
#import "MacPatch.h"
#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <unistd.h>

#import "ExecFoo.h"

#define APPVERSION	@"3.2.0.1"
#define APPNAME		@"MPAgentExec"

void usage(void);

int main (int argc, char * argv[])
{
    @autoreleasepool {

        int a_Type = 0;
        BOOL echoToConsole = NO;
        BOOL verboseLogging = NO;
        BOOL isILoadMode = NO;
        BOOL forceRunTask = NO;
        MPPatchContentType updateType = kAllPatches;
        NSString *_updateBundle = nil;

        // Inventory
        NSString *argType = NULL;

        // Setup argument processing
        int c;
        while (1)
        {
            static struct option long_options[] =
            {
                {"Debug"				,no_argument	    ,0, 'D'},
                {"UpdateFilter"			,required_argument	,0, 'f'},
                {"UpdateBundle"			,required_argument	,0, 'B'},
				
                {"Critial"				,no_argument	    ,0, 'x'},
				
				{"AgentUpdate"			,no_argument		,0, 'G'},
				
                {"AllowClient"			,no_argument	    ,0, 'C'},
                {"AllowServer"			,no_argument	    ,0, 'S'},
                {"iload"				,no_argument	    ,0, 'i'},
                {"FORCERUN"				,no_argument		,0, 'F'},
                {"cuuid"                ,no_argument		,0, 'c'},
				
				// Software Dist
                {"installSWUsingGRP"    ,required_argument	,0, 'g'},
                {"installSWUsingSID"    ,required_argument	,0, 'd'},
                {"installSWUsingPLIST"  ,required_argument	,0, 'P'},
                // Output
                {"Echo"					,no_argument		,0, 'e'},
                {"Verbose"				,no_argument		,0, 'V'},
                {"version"				,no_argument		,0, 'v'},
                {"help"					,no_argument		,0, 'h'},
                {0, 0, 0, 0}
            };
            // getopt_long stores the option index here.
            int option_index = 0;
            c = getopt_long (argc, argv, "Df:B:GCSiFcg:d:P:eVvh", long_options, &option_index);

            // Detect the end of the options.
            if (c == -1) {
                break;
            }
            switch (c)
            {
                    case 'x':
                        a_Type = 10;
                        break;
                    case 'f':
                        if ([[[NSString stringWithUTF8String:optarg] lowercaseString] isEqualTo:@"apple"]) {
                            updateType = kApplePatches;
                        } else if ([[[NSString stringWithUTF8String:optarg] lowercaseString] isEqualTo:@"custom"] || [[[NSString stringWithUTF8String:optarg] lowercaseString] isEqualTo:@"third"]) {
							updateType = kCustomPatches;
                        } else if ([[[NSString stringWithUTF8String:optarg] lowercaseString] isEqualTo:@"critical"]) {
							updateType = kCriticalPatches;
						}
                        break;
                    case 'B':
                        a_Type = 2;
                        _updateBundle = [NSString stringWithUTF8String:optarg];
                        break;
                    case 'G':
                        a_Type = 5;
                        break;
                    case 'C':
                        //_defaultsOverride = [NSDictionary dictionaryWithObject:@"1" forKey:@"AllowClient"];
                        break;
                    case 'S':
						a_Type = 1000;
                        //_defaultsOverride = [NSDictionary dictionaryWithObject:@"1" forKey:@"AllowServer"];
                        break;
                    case 'c':
                        printf("%s\n",[[MPSystemInfo clientUUID] UTF8String]);
                        return 0;
                    case 'V':
                        verboseLogging = YES;
                        break;
                    case 'D':
                        verboseLogging = YES;
                        break;
                    case 'i':
                        isILoadMode = YES;
                        a_Type = 2;
                        updateType = kAllPatches;
                        break;
                    case 'g':
                        argType = [NSString stringWithUTF8String:optarg];
                        a_Type = 7;
                        break;
                    case 'd':
                        argType = [NSString stringWithUTF8String:optarg];
                        a_Type = 8;
                        break;
                    case 'P':
                        argType = [NSString stringWithUTF8String:optarg];
                        a_Type = 9;
                        break;
                    case 'F':
                        forceRunTask = YES;
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
#ifdef DEBUG
            printf("Debug mode.\n");
#else
            exit(0);
#endif
        }
        
        // Setup Logging
        NSString *_logFile = @"/Library/Logs/MPAgentExec.log";
        [MPLog setupLogging:_logFile level:lcl_vInfo];
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

        // Run Functions
        MPAgentExecController *controller = [[MPAgentExecController alloc] init];
		ExecFoo *ae = [ExecFoo new];
		
        int result = NO;
        switch (a_Type)
		{
            case 1:
				[controller scanForPatches:updateType forceRun:forceRunTask];
                break;
            case 2:
                if (isILoadMode == YES) {
                    [controller setILoadMode:YES];
                }
                if (_updateBundle) {
					[controller patchScanAndUpdate:kCustomPatches bundleID:_updateBundle];
                } else {
					[controller patchScanAndUpdate:updateType bundleID:NULL];
                }
                break;
            case 5:
                [controller scanAndUpdateAgentUpdater];
                break;
            case 7:
                // Install Using SW Group Name ID
                result = [controller installSoftwareTasksForGroup:argType];
                break;
            case 8:
                // Install Using SW Task ID
                result = [controller installSoftwareTask:argType];
                break;
            case 9:
                // Install Using PLIST of SW Task ID's
                result = [controller installSoftwareTasksUsingPLIST:argType];
                break;
            case 10:
                // Scan for and install critical updates
				[controller patchScanAndUpdate:kCriticalPatches bundleID:NULL];
                break;
			case 1000:
				
				[ae scanForatches];
				break;
            default:
                logit(lcl_vError, @"should never have gotten here!");
                break;
        }

        controller = nil;
    }
    return 0;
}

void usage(void) {
    
	printf("%s\n",[APPNAME UTF8String]);
	printf("Version: %s\n\n",[APPVERSION UTF8String]);
	printf("Usage: %s [OPTION]\n\n",[APPNAME UTF8String]);
	
	// Scan & Update
	printf(" -s \tScan for patches.\n");
	printf(" -u \tScan & Update approved patches.\n");
    printf(" -x \tScan & Update critical patches only.\n");
	
	printf("\n    \tOverrides configuration which prevents client from being updated.\n");
    printf(" -C \tAllowClient override.\n");
    printf(" -S \tAllowServer override.\n\n");
	
	// Agent Updates
    printf(" -G \tScan for Agent updates and update if needed.\n");
	printf(" -i \tScan & Update approved patches in iLoad output mode.\n\n");
	
	// Software Dist
    printf(" -g \t[Software Group Name] Install Software in group.\n");
    printf(" -d \tInstall software using TaskID\n");
    printf(" -P \t[Software Plist] Install software using plist.\n\n");
	
	// Misc
	printf(" -e \tEcho logging data to console.\n");
	printf(" -V \tVerbose logging.\n");
	printf(" -v \tDisplay version info. \n");
	printf("\n");
    exit(0);
}
