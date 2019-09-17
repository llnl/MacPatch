//
//  CheckIn.m
//  MPAgent
//
//  Created by Charles Heizer on 9/16/19.
//  Copyright © 2019 LLNL. All rights reserved.
//

#import "CheckIn.h"

#import "MPAgent.h"
#import "MacPatch.h"
#import "MPSettings.h"
#import "Software.h"

#undef  ql_component
#define ql_component lcl_cCheckIn

@implementation CheckIn

- (void)runClientCheckIn
{
	// Collect Agent Checkin Data
	MPClientInfo *ci = [[MPClientInfo alloc] init];
	NSDictionary *agentData = [ci agentData];
	if (!agentData)
	{
		logit(lcl_vError,@"Agent data is nil, can not post client checkin data.");
		return;
	}
	
	// Post Client Checkin Data to WS
	NSError *error = nil;
	NSDictionary *revsDict;
	MPRESTfull *rest = [[MPRESTfull alloc] init];
	revsDict = [rest postClientCheckinData:agentData error:&error];
	if (error) {
		logit(lcl_vError,@"Running client check in had an error.");
		logit(lcl_vError,@"%@", error.localizedDescription);
	}
	else
	{
		[self updateGroupSettings:revsDict];
		[self installRequiredSoftware:revsDict];
	}
	
	logit(lcl_vInfo,@"Running client check in completed.");
	return;
}

- (void)updateGroupSettings:(NSDictionary *)settingRevisions
{
	// Query for Revisions
	// Call MPSettings to update if nessasary
	logit(lcl_vInfo,@"Check and Update Agent Settings.");
	logit(lcl_vDebug,@"Setting Revisions from server: %@", settingRevisions);
	MPSettings *set = [MPSettings sharedInstance];
	[set compareAndUpdateSettings:settingRevisions];
	return;
}

- (void)installRequiredSoftware:(NSDictionary *)checkinResult
{
	logit(lcl_vInfo,@"Install required client group software.");
	
	NSArray *swTasks;
	if (!checkinResult[@"swTasks"]) {
		logit(lcl_vError,@"Checkin result did not contain sw tasks object.");
		return;
	}
	
	swTasks = checkinResult[@"swTasks"];
	if (swTasks.count >= 1)
	{
		Software *sw = [[Software alloc] init];
		for (NSDictionary *t in swTasks)
		{
			NSString *task = t[@"tuuid"];
			if ([sw isSoftwareTaskInstalled:task])
			{
				continue;
			}
			else
			{
				NSError *err = nil;
				MPRESTfull *mpRest = [[MPRESTfull alloc] init];
				NSDictionary *swTask = [mpRest getSoftwareTaskUsingTaskID:task error:&err];
				if (err) {
					logit(lcl_vError,@"%@",err.localizedDescription);
					continue;
				}
				logit(lcl_vInfo,@"Begin installing %@.",swTask[@"name"]);
				int res = [sw installSoftwareTask:swTask];
				if (res != 0) {
					logit(lcl_vError,@"Required software, %@ failed to install.",swTask[@"name"]);
				}
			}
		}
	}
}



@end
