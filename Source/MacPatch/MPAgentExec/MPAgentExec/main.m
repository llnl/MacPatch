//
//  main.m
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#define APPVERSION	@"3.0.6.0"
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
		BOOL overrideReboot = NO;
        int _UpdateType = 0; // 0 All, 1 = Apple, 2 = Third
        NSString *_updateBundle = nil;
        NSDictionary *_defaultsOverride = nil;

        // Inventory
        NSString *argType = NULL;

        // Setup argument processing
        int c;
        while (1)
        {
            static struct option long_options[] =
            {
                {"Debug"				,no_argument	    ,0, 'D'},
                {"Scan"					,no_argument	    ,0, 's'},
                {"Update"				,no_argument	    ,0, 'u'},
                {"UpdateFilter"			,required_argument	,0, 'f'},
                {"UpdateBundle"			,required_argument	,0, 'B'},
                {"Critial"				,no_argument	    ,0, 'x'},
				{"AVInfo"				,no_argument	    ,0, 'a'},
				{"AVUpdate"				,no_argument	    ,0, 'U'},
                {"AgentUpdate"			,no_argument		,0, 'G'},
                {"AllowClient"			,no_argument	    ,0, 'C'},
                {"AllowServer"			,no_argument	    ,0, 'S'},
                {"iload"				,no_argument	    ,0, 'i'},
                {"FORCERUN"				,no_argument		,0, 'F'},
				{"installRebootPatches"	,no_argument		,0, 'R'},
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
            c = getopt_long (argc, argv, "Dsuf:B:aUGCSiFRcg:d:P:eVvh", long_options, &option_index);

            // Detect the end of the options.
            if (c == -1) {
                break;
            }
            switch (c)
            {
                    case 's':
                        a_Type = 1;
                        break;
                    case 'u':
                        a_Type = 2;
                        break;
                    case 'x':
                        a_Type = 10;
                        break;
                    case 'f':
                        if ([[NSString stringWithUTF8String:optarg] isEqualTo:@"Apple"]) {
                            _UpdateType = 1;
                        } else if ([[NSString stringWithUTF8String:optarg] isEqualTo:@"Custom"] || [[NSString stringWithUTF8String:optarg] isEqualTo:@"Third"]) {
                            _UpdateType = 2;
                        }
                        break;
                    case 'B':
                        a_Type = 2;
                        _updateBundle = [NSString stringWithUTF8String:optarg];
                        break;
                    case 'a':
                        a_Type = 3;
                        break;
                    case 'U':
                        a_Type = 4;
                        break;
                    case 'G':
                        a_Type = 5;
                        break;
                    case 'C':
                        _defaultsOverride = [NSDictionary dictionaryWithObject:@"1" forKey:@"AllowClient"];
                        break;
                    case 'S':
                        _defaultsOverride = [NSDictionary dictionaryWithObject:@"1" forKey:@"AllowServer"];
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
                        _UpdateType = 0;
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
					case 'R':
						overrideReboot = YES;
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
        NSString *_logFile = [NSString stringWithFormat:@"%@/Logs/MPAgentExec.log",MP_ROOT_CLIENT];
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

        // Run Functions
        MPAgentExecController *controller = [[MPAgentExecController alloc] init];
        if (_defaultsOverride) {
            [controller overRideDefaults:_defaultsOverride];
        }
        if (forceRunTask == YES) {
            [controller setForceRun:YES];
        }
		if (overrideReboot == YES) {
			[controller setOverrideRebootPatchInstalls:YES];
		}

        int result = NO;
        switch (a_Type) {
            case 1:
                if (_UpdateType >= 1) {
                    [controller scanForPatchesWithFilter:_UpdateType];
                } else {
                    [controller scanForPatches];
                }
                break;
            case 2:
                if (isILoadMode == YES) {
                    [controller setILoadMode:YES];
                }
                if (_updateBundle) {
                    [controller scanAndUpdateCustomWithPatchBundleID:_updateBundle];
                } else {
					if (isILoadMode)
					{
						[controller scanForPatchesAndUpdateWithFilterCritical:_UpdateType critical:NO stayAliveForProvisioning:YES];
					} else {
                    	[controller scanForPatchesAndUpdateWithFilter:_UpdateType];
					}
                }
                break;
            case 3:
                [controller scanForAVDefs];
                break;
            case 4:
                [controller scanForAVDefsAndUpdate];
                break;
            case 5:
                [controller scanAndUpdateAgentUpdater];
                break;
            case 6:
                // Inventory has been moved to MPAgent
                break;
            case 7:
                // Install Using SW Group Name ID
                result = [controller installSoftwareTasksForGroup:argType];
                break;
            case 8:
                // Install Using SW Task ID
                result = [controller installSoftwareTasks:argType];
                break;
            case 9:
                // Install Using PLIST of SW Task ID's
                result = [controller installSoftwareTasksUsingPLIST:argType];
                break;
            case 10:
                // Scan for and install critical updates
                [controller scanForPatchesAndUpdateWithFilterCritical:_UpdateType critical:YES];
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
    // Symantec Antivirus
	printf(" -a \tScan for AV info.\n");
	printf(" -U \tScan for AV info and update outdated AV defs.\n\n");
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
