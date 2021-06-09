//
//  MPScript.m
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "MPScript.h"

#undef  ql_component
#define ql_component lcl_cMPScript

@implementation MPScript

@synthesize scriptText;

#pragma mark -
#pragma mark init
//=========================================================== 
//  init 
//=========================================================== 
-(id)initWithScript:(NSString *)aScript
{
    self = [super init];
	
    if ( self ) {
		[self setScriptText:aScript];
    }
	
    return self;
}

#pragma mark - Main

-(BOOL)runScript:(NSString *)aScript
{
	BOOL result = FALSE;


    NSString *cleanScript = [aScript stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	NSString *tmpID = (NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
	CFRelease(uuid);
	
	NSString *tmpFile = [NSTemporaryDirectory() stringByAppendingPathComponent:tmpID];
	NSError *err = nil;
	[cleanScript writeToFile:tmpFile atomically:YES encoding:NSStringEncodingConversionAllowLossy error:&err];
	if (err) {
		result = FALSE;
        return result;
	}
	
	// Fix line endings
	if ([self fixLineEndingsInFile:tmpFile] == NO)
		qlerror(@"Warnning, did not get a return code of 0 when fixing line endings in %@. Script may not run.",tmpFile);
	
	NSTask *task = [[NSTask alloc] init];
	NSPipe *pipe = [NSPipe pipe];
	
	[task setLaunchPath:@"/bin/bash"];
	[task setArguments:[NSArray arrayWithObjects:@"-C",tmpFile,nil]];
	
    [task setStandardOutput: pipe];
    [task setStandardError: pipe];
	
	NSFileHandle *file = [pipe fileHandleForReading];
	
	[task launch];
	[task waitUntilExit];
	
	NSData *data = [file readDataToEndOfFile];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
	int status = [task terminationStatus];
	
	qldebug(@"Script = %@ \n %@ \n Exit Code: %d",tmpFile,[NSString stringWithContentsOfFile:tmpFile encoding:NSUTF8StringEncoding error:NULL], status);
	qldebug(@"Script Result = %@",string);
	
	if (status == 0) {
		result = TRUE;
        NSError *delErr = nil;
        [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:&delErr];
        if (delErr) {
            qlerror(@"Error removing file %@",tmpFile);
        }
	} else {
		qldebug(@"Exit Code: %d.\nScript Result: %@\nScript: %@",status,string,tmpFile);
	}
	
	return result;
}

- (NSString *)runScriptReturningResult:(NSString *)aScript
{
    NSString *cleanScript = [aScript stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	NSString *tmpID = (NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
	CFRelease(uuid);
	
	NSString *tmpFile = [NSTemporaryDirectory() stringByAppendingPathComponent:tmpID];
	NSError *err = nil;
	[cleanScript writeToFile:tmpFile atomically:YES encoding:NSStringEncodingConversionAllowLossy error:&err];
	if (err) {
		return @"ERROR";
	}
	
	// Fix line endings
	if ([self fixLineEndingsInFile:tmpFile] == NO)
		qlerror(@"Warnning, did not get a return code of 0 when fixing line endings in %@. Script may not run.",tmpFile);
	
	NSTask *task = [[NSTask alloc] init];
	NSPipe *pipe = [NSPipe pipe];
	
	[task setLaunchPath:@"/bin/bash"];
	[task setArguments:[NSArray arrayWithObjects:@"-C",tmpFile,nil]];
	
    [task setStandardOutput: pipe];
    [task setStandardError: pipe];
	
	NSFileHandle *file = [pipe fileHandleForReading];
	
	[task launch];
	[task waitUntilExit];
	
	NSData *data = [file readDataToEndOfFile];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	
	int status = [task terminationStatus];
	
	qldebug(@"Script = %@ \n %@ \n Exit Code: %d",tmpFile,[NSString stringWithContentsOfFile:tmpFile encoding:NSUTF8StringEncoding error:NULL], status);
	qldebug(@"Script Result = %@",string);
	
	if (status == 0) {
        NSError *delErr = nil;
        [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:&delErr];
        if (delErr) {
            qlerror(@"Error removing file %@",tmpFile);
        }
		return string;
	} else {
		qldebug(@"Exit Code: %d.\nScript Result: %@\nScript: %@",status,string,tmpFile);
		return @"ERROR";
	}
	
	return @"ERROR";
}

- (BOOL)runScriptsFromDirectory:(NSString *)aDirectory
{
	return [self runScriptsFromDirectory:aDirectory error:NULL];
}

- (BOOL)runScriptsFromDirectory:(NSString *)aDirectory error:(NSError **)error
{
	int res = 0;
	NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:aDirectory error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.sh') OR (SELF like [cd] '*.rb') OR (SELF like [cd] '*.py')"];
	NSArray *onlyScripts = [dirContents filteredArrayUsingPredicate:fltr];
	
	NSError *err = nil;
	NSString *scriptText = nil;
	for (NSString *scpt in onlyScripts)
	{
		err = nil;
		scriptText = [NSString stringWithContentsOfFile:[aDirectory stringByAppendingPathComponent:scpt] encoding:NSUTF8StringEncoding error:&err];
		if (err) {
			qlerror(@"Error reading script string: %@",[err description]);
			qlerror(@"%@",[err description]);
			if (*error != NULL) *error = err;
			res++;
			break;
		}
		
		if (![self runScript:scriptText])
		{
			res++;
			break;
		}
	}
	
	return (res == 0) ? YES : NO;
}

-(BOOL)fixLineEndingsInFile:(NSString *)aScriptPath
{
	BOOL result = NO;
	NSError *err = nil;
	NSMutableString *strData = [[NSMutableString alloc] initWithContentsOfFile:aScriptPath];
	// This will replace return lines and leave new lines
	[strData replaceOccurrencesOfString:@"\r" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [strData length])];
	[strData writeToFile:aScriptPath atomically:NO encoding:NSASCIIStringEncoding error:NULL];
	
	if (err) {
		qlerror(@"%@, error code %d (%@)",[err localizedDescription], (int)[err code], [err domain]);
		result=NO;
	} else {
		result=YES;
	}
	
	return result;
}

@end
