//
//  MPTask_EditorAppDelegate.m
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Daniel Hoit <hoit2 at llnl.gov>.
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

#import "MPTask_EditorAppDelegate.h"
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>

#define MP_TASKS_PLIST @"/Library/MacPatch/Client/.tasks/gov.llnl.mp.tasks.plist"
#define MP_ALT_TASKS_PLIST @"/Library/MacPatch/Client/MPTasks.plist"


@interface CheckBoxValueTransformer: NSValueTransformer
{
    NSButton *buttonState;
}
@end

@implementation CheckBoxValueTransformer

- (id)init
{
    if (self = [super init])
    {
        [buttonState setEnabled:YES];
        [buttonState setState:NSOffState];
    }
    return self;
}

- (void)dealloc
{
    buttonState = nil;
}

+ (Class)transformedValueClass { return [NSButton class]; }
+ (BOOL)allowsReverseTransformation { return YES; }

- (id)transformedValue:(id)value
{
    return [NSNumber numberWithBool:([value integerValue] > 0)];
}

- (id)reverseTransformedValue:(id)value
{
    //NSLog(@"%@",value);
    if ([[value stringValue] isEqualToString:@"1"]) {
        return @"1";
    } else {
        return @"0";
    }
}

@end


@implementation MPTask_EditorAppDelegate

@synthesize window;
@synthesize taskFile;

- (BOOL)scanForPlists
{
	BOOL taskFileExists = [[NSFileManager defaultManager] fileExistsAtPath:MP_TASKS_PLIST];
	BOOL altTaskFileExists = [[NSFileManager defaultManager] fileExistsAtPath:MP_ALT_TASKS_PLIST];
	BOOL returnVal = NO;
	usingAltTaskFile = NO;
	if (taskFileExists && altTaskFileExists) {
		NSAlert *selectTask = [NSAlert alertWithMessageText:@"Please select a MacPatch plist to edit" 
											  defaultButton:@"Primary plist" 
											alternateButton:@"Alternate plist" 
												otherButton:nil 
								  informativeTextWithFormat:@"The primary MacPatch plist is located %@. The alternate is %@", MP_TASKS_PLIST,MP_ALT_TASKS_PLIST];
		int userChoice = (int)[selectTask runModal];
		if (userChoice == NSAlertDefaultReturn) {
			taskFile = [NSDictionary dictionaryWithContentsOfFile:MP_TASKS_PLIST];
			returnVal = YES;
		} else {
			taskFile = [NSDictionary dictionaryWithContentsOfFile:MP_ALT_TASKS_PLIST];
			usingAltTaskFile = YES;
			returnVal = YES;
		}
	} else if (taskFileExists) {
		taskFile = [NSDictionary dictionaryWithContentsOfFile:MP_TASKS_PLIST];
		returnVal = YES;
	} else if (altTaskFileExists) {
		taskFile = [NSDictionary dictionaryWithContentsOfFile:MP_ALT_TASKS_PLIST];
		usingAltTaskFile = YES;
		returnVal = YES;
	}
	
	return returnVal;
}

- (IBAction)openPlists:(id)sender
{	
	if ([self scanForPlists]) {
		[self populateInterfaceFromPlist:taskFile];
	} else {
		[NSError errorWithDomain:@"No MacPatch Plist files found!" code:1 userInfo:nil];
		[NSApp presentError:[NSError errorWithDomain:@"No MacPatch Plist files found!" code:1 userInfo:nil]];
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[self openPlists:self];
	[window center];
	unsavedChanges = NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([dataManager selectionIndex] == NSNotFound) {
		[intervalDate setTitle:@""];
		[intervalText setStringValue:@""];
		[intervalStart setTitle:@""];
	} else {
		NSString *selectionString = [[dataManager selection] valueForKey:@"interval"];
		NSArray *formatParts = [selectionString componentsSeparatedByString:@"@"];
		if ([formatParts count] < 2) {
			NSLog(@"Error parsing interval string");
			return;
		}
		if ([formatParts count] == 3) {
			[intervalDate setEnabled:YES];
			[intervalDate selectItemWithTitle:[formatParts objectAtIndex:1]];
		} else {
			[intervalDate setTitle:@""];
			[intervalDate setEnabled:NO];
		}
		[intervalStart selectItemWithTitle:[[formatParts objectAtIndex:0] uppercaseString]];
		[intervalText setStringValue:[formatParts lastObject]];
	}
}

- (BOOL)populateInterfaceFromPlist:(NSDictionary *)plist
{
	if (usingAltTaskFile) {
		window.title = MP_ALT_TASKS_PLIST;
	} else {
		window.title = MP_TASKS_PLIST;
	}
	
	[dataManager setContent:nil];
	[dataManager addObjects:[plist objectForKey:@"mpTasks"]];
	[window update];
	[dataManager setSelectionIndex:0];

	return YES;
}

- (IBAction)updateTableRow:(id)sender
{
	if ([[intervalStart titleOfSelectedItem] isEqualTo:@"RECURRING"] )
    {
		[intervalDate setEnabled:YES];
	} else {
		[intervalDate setTitle:@""];
		[intervalDate setEnabled:NO];
	}
	
	NSString *updateString = nil;
	if ([intervalDate isEnabled])
    {
		updateString = [NSString stringWithFormat:@"%@@%@@%@",[intervalStart titleOfSelectedItem],[intervalDate titleOfSelectedItem],[intervalText stringValue]];
	} else {
		updateString = [NSString stringWithFormat:@"%@@%@",[intervalStart titleOfSelectedItem],[intervalText stringValue]];
	}

	int intRow = (int)[dataManager selectionIndex];
	NSMutableDictionary *boom = [[dataManager arrangedObjects] objectAtIndex:intRow];
	[boom setObject:updateString forKey:@"interval"];
}

- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor
{
	unsavedChanges = YES; 
	[saveButton setEnabled:NO];
	[saveButton setTitle:@"Editing..."];
	return YES;
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	[saveButton setTitle:@"Save"];
	[saveButton setEnabled:YES];
	return YES;
}

- (BOOL)windowShouldClose:(id)sender
{
	if (unsavedChanges)
    {
		NSAlert *saveBeforeQuitAlert;
			saveBeforeQuitAlert = [NSAlert alertWithMessageText:@"Save before quitting?"
							defaultButton:@"Save and Quit" 
						  alternateButton:@"Quit" 
							  otherButton:@"Cancel" 
				informativeTextWithFormat:@"If you quit now, unsaved changes will be lost."];

		int saveChoice = (int)[saveBeforeQuitAlert runModal];
		if (saveChoice == NSAlertDefaultReturn)
        {
			[self savePlist:self];
			return YES;
		} else if (saveChoice == NSAlertAlternateReturn) {
			return YES;
		} else {
			return NO;
		}
	}
	return YES;
}

- (IBAction)savePlist:(id)sender
{
	[window endEditingFor:[window firstResponder]];
	//First, we write the plist somewhere we can touch
	NSString *tempFile = @"/var/tmp/mpplist.plist";
	NSDictionary *mpPlist = [NSDictionary dictionaryWithObject:[dataManager arrangedObjects] forKey:@"mpTasks"];
	BOOL didWrite = [mpPlist writeToFile:tempFile atomically:NO];
	if (!didWrite) {
		NSLog(@"Error writing file to disk!");
		return;
	}
	
	//OSStatus userDidCancel = -60006;
	//int read (long,StringPtr,int);
	//int write (long,StringPtr,int);
	OSStatus myStatus;
	AuthorizationFlags myFlags = kAuthorizationFlagDefaults;              // 1
	AuthorizationRef myAuthorizationRef;                                  // 2
	
	myStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,  // 3
								   myFlags, &myAuthorizationRef);
	if (myStatus != errAuthorizationSuccess) {
		//return myStatus;
		NSAlert *authFail = [NSAlert alertWithMessageText:@"Authorization Failure." 
											defaultButton:@"OK" 
										  alternateButton:nil 
											  otherButton:nil 
								informativeTextWithFormat:@"There was an error authorizing the write operation. Please try again."];
		[authFail runModal];
		NSLog(@"Authentication failed");
		return;
	}
	
	do
	{
		{
			AuthorizationItem myItems = {kAuthorizationRightExecute, 0, NULL, 0}; //4
			AuthorizationRights myRights = {1, &myItems};                  // 5
			
			myFlags = kAuthorizationFlagDefaults |                         // 6
			kAuthorizationFlagInteractionAllowed |
			kAuthorizationFlagPreAuthorize |
			kAuthorizationFlagExtendRights;
			myStatus = AuthorizationCopyRights (myAuthorizationRef,       // 7
												&myRights, NULL, myFlags, NULL );
		}
		
		if (myStatus != errAuthorizationSuccess) break;
		
		{
			//Setup the authed copy.
			//Figure out where we are writing to
			NSString * plistDestination = nil;
			plistDestination = (usingAltTaskFile) ? MP_ALT_TASKS_PLIST : MP_TASKS_PLIST;
			char *myArguments[] = { "-r",(char *)[tempFile cStringUsingEncoding:NSUTF8StringEncoding],(char *)[plistDestination cStringUsingEncoding:NSUTF8StringEncoding],NULL };
			
			FILE *myCommunicationsPipe = NULL;
			char myReadBuffer[128];
			
			myFlags = kAuthorizationFlagDefaults;                          // 8
			myStatus = AuthorizationExecuteWithPrivileges                  // 9
			(myAuthorizationRef,"/bin/cp", myFlags, myArguments,
			 &myCommunicationsPipe);
			
			if (myStatus == errAuthorizationSuccess)
				for(;;)
				{
					int bytesRead = (int)read (fileno (myCommunicationsPipe), myReadBuffer, sizeof (myReadBuffer));
					if (bytesRead < 1) break;
					write (fileno (stdout), myReadBuffer, bytesRead);
				}
			
		}
	} while (0);
	
	AuthorizationFree (myAuthorizationRef, kAuthorizationFlagDefaults);    // 10
	unsavedChanges = NO;
}


@end
