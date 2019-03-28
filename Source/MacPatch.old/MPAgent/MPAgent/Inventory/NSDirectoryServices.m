//
//  NSDirectoryServices.m
//
/*
 * http://javworld.com/Extreme/DirServ.html
 * Copyright © 2004 John A. Vink
 * Modified extensively by Daniel Hoit
 */

#import "NSDirectoryServices.h"

#import <DirectoryService/DirServices.h>
#import <DirectoryService/DirServicesUtils.h>
#import <DirectoryService/DirServicesConst.h>

 NSString *const DHDSSEARCHNODE             = @"/Search";
 NSString *const DHDSComputerAccountType    = @"dsRecTypeStandard:Computers";
 NSString *const DHDSUserAccountType        = @"dsRecTypeStandard:Users";
 NSString *const DHDSGroupAccountType       = @"dsRecTypeStandard:Groups";

@interface NSDirectoryServices (Private)
- (BOOL) openNode:(NSString*)node;
- (void) addRecordAtIndex:(unsigned long)recIndex toDictionary:(NSMutableDictionary*)dict withBuffer:(tDataBufferPtr)dataBuffer;
- (void) addEntry:(tAttributeEntry*)pAttrEntry withValue:(tAttributeValueListRef)valueRef toDictionary:(NSMutableDictionary*)dict withBuffer:(tDataBufferPtr)dataBuffer;
- (NSString*) nameOfRecord:(tRecordEntry*)recEntry attributes:(tAttributeListRef)attrListRef withBuffer:(tDataBufferPtr)dataBuffer;
static tDirStatus dsDataBufferAppendData(tDataBufferPtr  buf, 
										 const void *    dataPtr, 
										 size_t          dataLen );
@end


@implementation NSDirectoryServices

// ---------------------------------------------------------------------
// * init
// ---------------------------------------------------------------------
- (id) init
{
	if (nil != (self = [super init]))
	{
			// init directory services
		if (eDSNoErr != dsOpenDirService(&_dirRef))
		{
			printf("Can't open directory services\n");
			return nil;
		}
	}
	
	return self;
}


// ---------------------------------------------------------------------
// * dealloc
// ---------------------------------------------------------------------
- (void) dealloc
{
		// close directory services
	dsCloseDirService(_dirRef);
	
		// this ain't C++.  Always call your parent's dealloc, or you're not releasing any memory.
		// Only losers don't dealloc memory.  Don't be a loser.
	[super dealloc];
}


// ---------------------------------------------------------------------
// * getNodes
// ---------------------------------------------------------------------
// this returns a list of the available nodes.
// usually you'll just want to use the first one.
- (NSArray*) getNodes
{
    bool done = false;
    tDirStatus dirStatus = eDSNoErr;
    UInt32 bufferCount = 0;
    tDataBufferPtr dataBuffer = nil;
    tDataListPtr nodeName = nil;
    tContextData context = 0;
	NSMutableArray* result = [NSMutableArray array];

		// allocate a 32k buffer.
	dataBuffer = dsDataBufferAllocate(_dirRef, 32 * 1024);
	if (dataBuffer != nil)
	{
		while ((dirStatus == eDSNoErr) && !done)
		{
			dirStatus = dsFindDirNodes( _dirRef, dataBuffer, nil, eDSAuthenticationSearchNodeName, 
					&bufferCount, &context );
			if (dirStatus == eDSNoErr && bufferCount > 0)
			{
				dirStatus = dsGetDirNodeName( _dirRef, dataBuffer, 1, &nodeName );
				if (dirStatus == eDSNoErr)
				{
					char* pNodeName = dsGetPathFromList(_dirRef, nodeName, "/");
					[result addObject:[NSString stringWithCString:pNodeName]];
					dsDataListDeallocate(_dirRef, nodeName);
					free(nodeName);
				}
				else
				{
					logit(lcl_vError,@"dsGetDirNodeName error = %d, count = %d", (int)dirStatus, (int)bufferCount );
				}
			}
			else
				logit(lcl_vError,@"Error %d from dsFindDirNodes", (int)dirStatus);
			done = (context == 0);
		}
		dsDataBufferDeAllocate( _dirRef, dataBuffer );
	}
	
		// remember this list of nodes for future function calls
	_nodes = [[NSArray arrayWithArray:result] retain];
	
		// return a copy to the caller
	return [_nodes copy];
}
- (NSArray*) getLocalNodes
{
    bool done = false;
    tDirStatus dirStatus = eDSNoErr;
    UInt32 bufferCount = 0;
    tDataBufferPtr dataBuffer = nil;
    tDataListPtr nodeName = nil;
    tContextData context = 0;
	NSMutableArray* result = [NSMutableArray array];
	
	// allocate a 32k buffer.
	dataBuffer = dsDataBufferAllocate(_dirRef, 32 * 1024);
	if (dataBuffer != nil)
	{
		while ((dirStatus == eDSNoErr) && !done)
		{
			dirStatus = dsFindDirNodes( _dirRef, dataBuffer, nil, eDSLocalNodeNames, 
									   &bufferCount, &context );
			if (dirStatus == eDSNoErr && bufferCount > 0)
			{
				dirStatus = dsGetDirNodeName( _dirRef, dataBuffer, 1, &nodeName );
				if (dirStatus == eDSNoErr)
				{
					char* pNodeName = dsGetPathFromList(_dirRef, nodeName, "/");
					[result addObject:[NSString stringWithCString:pNodeName]];
					dsDataListDeallocate(_dirRef, nodeName);
					free(nodeName);
				}
				else
				{
					logit(lcl_vError,@"dsGetDirNodeName error = %d, count = %d", (int)dirStatus, (int)bufferCount );
				}
			}
			else
				logit(lcl_vError,@"Error %d from dsFindDirNodes", (int)dirStatus);
			done = (context == 0);
		}
		dsDataBufferDeAllocate( _dirRef, dataBuffer );
	}
	
	// remember this list of nodes for future function calls
	_nodes = [[NSArray arrayWithArray:result] retain];
	
	// return a copy to the caller
	return [_nodes copy];
}
- (BOOL)setPassword:(NSString *)password forUser:(NSString *)user inDsNode:(NSString *)node error:(NSError **)dsError 
{
	if (!node) //If there is no node specified, use the local node.
		node = @"/Local/Default";
	
	/*if (node == nil)
	{
		// see if any nodes were ever fetched
		if (_nodes == nil)
			[self getNodes];
		// see if there are any nodes
		if (_nodes && [_nodes count] == 0)
		{
			NSLog(@"No nodes available");
			return nil;
		}
		
		// use the first node we find
		node = [_nodes objectAtIndex:0];
	}*/
	NSArray *localNodes = [self getLocalNodes];
	//NSLog(@"Available nodes: %@", localNodes);
	if (![localNodes containsObject:node]) {
		if (dsError != NULL) *dsError = [NSError errorWithDomain:@"DSError. The requested node was not available." code:97 userInfo:nil];
		return NO;
	}
	
	int result = 0;

	do
	{
		if (![self openNode:node]) {
			if (dsError != NULL) *dsError = [NSError errorWithDomain:@"DSError. Couldn't open the correct node" code:99 userInfo:nil];
			break;
		}
	tDataNodePtr authType;
	tDataBufferPtr dataBuffer;
	tDataBufferPtr responseBuffer;
	tDirStatus aDirErr;
	tContextData aContinueData = 0;
	long aDataBufSize = 0;
	
	//Spec the type of auth
	authType = dsDataNodeAllocateString(_dirRef, kDSStdAuthSetPasswdAsRoot);
	const char * newUserName = [user cStringUsingEncoding:NSUTF8StringEncoding];
	const char * newUserPass = [password cStringUsingEncoding:NSUTF8StringEncoding];
	size_t newUserNameLen;
	size_t newPasswordLen;
	UInt32 length;
	tDirStatus errorStatus;
	newUserNameLen = strlen(newUserName);
	newPasswordLen = strlen(newUserPass);
	
	responseBuffer = dsDataBufferAllocate(_dirRef,512);
	aDataBufSize += sizeof(long) + newUserNameLen;
	aDataBufSize += sizeof(long) + newPasswordLen;
	
	dataBuffer = dsDataBufferAllocate(_dirRef,(int)aDataBufSize);
	if (dataBuffer == NULL) {
		printf("Bang. We gots no buffer\n");
		return NO;
	} else {
		length = (UInt32)newUserNameLen;
        errorStatus = dsDataBufferAppendData(dataBuffer, &length, sizeof(length));
        if (errorStatus != eDSNoErr) {
			if (dsError != NULL) *dsError = [NSError errorWithDomain:@"DSError. Couldn't append to buffer." code:100 userInfo:nil];
			return NO;
		}
		
        errorStatus = dsDataBufferAppendData(dataBuffer, newUserName, newUserNameLen);
		if (errorStatus != eDSNoErr) {
			if (dsError != NULL) *dsError = [NSError errorWithDomain:@"DSError. Couldn't append to buffer." code:200 userInfo:nil];
			return NO;
		}
       
		length = (UInt32)newPasswordLen;
        errorStatus = dsDataBufferAppendData(dataBuffer, &length, sizeof(length));
		if (errorStatus != eDSNoErr) {
			if (dsError != NULL) *dsError = [NSError errorWithDomain:@"DSError. Couldn't append to buffer." code:300 userInfo:nil];
			return NO;
		}
        
		errorStatus = dsDataBufferAppendData(dataBuffer, newUserPass, newPasswordLen);
		if (errorStatus != eDSNoErr) {
			if (dsError != NULL) *dsError = [NSError errorWithDomain:@"DSError. Couldn't append to buffer." code:400 userInfo:nil];
			return NO;
		}
		
	}
	
	dsBool inDirNodeAuthOnlyBool = FALSE;
	//do the authentication
	aDirErr = dsDoDirNodeAuth(_dirRef,authType,inDirNodeAuthOnlyBool,dataBuffer,responseBuffer,&aContinueData);
	if (aDirErr == eDSNoErr) {
		result = YES;
	} else {
		printf("Authentication to the node failed: %d\n", aDirErr);
		printf("response buffer length = %d, rb data = %s\n", (int)responseBuffer->fBufferLength, responseBuffer->fBufferData);
		result = NO;
	}
	
	//clean it up
	aDirErr = dsDataBufferDeAllocate(_dirRef,dataBuffer);
	aDirErr = dsDataBufferDeAllocate(_dirRef,responseBuffer);
	aDirErr = dsDataNodeDeAllocate(_dirRef,authType);
	} while (0);
	
	return result;
}

// ---------------------------------------------------------------------
// * getRecord
// ---------------------------------------------------------------------
- (NSDictionary*) getRecord:(NSString*)recordName ofType:(NSString*)recordType fromNode:(NSString*)node
{
	tDirStatus				dirStatus = eDSNoErr;
	NSMutableDictionary*	result = [NSMutableDictionary dictionary];
	
		// if the user did not give us a node, try and get the first one, which will be the search node
	if (node == nil)
	{
			// see if any nodes were ever fetched
		if (_nodes == nil)
			[self getNodes];
			// see if there are any nodes
		if (_nodes && [_nodes count] == 0)
		{
			NSLog(@"No nodes available");
			return nil;
		}
		
			// use the first node we find
		node = [_nodes objectAtIndex:0];
	}
	//NSLog(@"Available nodes: %@", [self getNodes]);
	
	do
	{
		if (![self openNode:node])
			break;
			
		tDataList recNames = {};
		tDataList recTypes = {};
		tDataList attrTypes = {};

		if ( (eDSNoErr == (dirStatus = dsBuildListFromStringsAlloc (_dirRef, &recNames, [recordName cStringUsingEncoding:[NSString defaultCStringEncoding]], nil))) &&
			 (eDSNoErr == (dirStatus = dsBuildListFromStringsAlloc (_dirRef, &recTypes, [recordType cStringUsingEncoding:[NSString defaultCStringEncoding]], nil))))
		{
			if ([recordType isEqualToString:@"dsRecTypeStandard:Computers"]){
				//NSLog(@"Comp me.");
				//dirStatus = dsBuildListFromStringsAlloc( _dirRef, &attrTypes, kDSNAttrRecordName, kDS1AttrDistinguishedName, kDS1AttrENetAddress, kDS1AttrSMBPWDLastSet, kDSNAttrMetaNodeLocation, NULL );
				//dirStatus = dsBuildListFromStringsAlloc( _dirRef, &attrTypes, kDSNAttrRecordName, kDS1AttrDistinguishedName, kDS1AttrENetAddress, kDS1AttrSMBPWDLastSet, kDSNAttrMetaNodeLocation, kDSAttributesNativeAll, NULL );
				dirStatus = dsBuildListFromStringsAlloc(_dirRef, &attrTypes, kDSAttributesAll, NULL);
				
			} else if ([recordType isEqualToString:@"dsRecTypeStandard:Users"] && [node isEqualToString:@"/Search"]){
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_5	
				dirStatus = dsBuildListFromStringsAlloc( _dirRef, &attrTypes, kDS1AttrBirthday, kDS1AttrDistinguishedName, kDS1AttrFirstName, kDS1AttrLastName, NULL );
#endif
			} else {
				//NSLog(@"we are using this one...");
				dirStatus = dsBuildListFromStringsAlloc (_dirRef, &attrTypes, kDSAttributesAll, nil);

			}
		}
		
		if (dirStatus != eDSNoErr)
			break;
		
		tDataBufferPtr dataBuffer = dsDataBufferAllocate(_dirRef, 32 * 1024);
		if (dataBuffer == nil)
			break;
			
		tContextData context = 0;
		UInt32 recCount;
		dirStatus = dsGetRecordList(_nodeRef, dataBuffer, &recNames, eDSExact, &recTypes, &attrTypes, false, &recCount, &context);
		if (dirStatus != eDSNoErr)
		{
			NSLog(@"Can't get record list");
			break;
		}
		//NSLog(@"Number records: %ld", recCount);
		if (recCount < 1)
		{
			//NSLog(@"Number records: %ld", recCount);
			break;
		} else if (recCount > 1) {
			qlinfo(@"Shaft. There are %i records", recCount);
			NSMutableDictionary *theOther = [NSMutableDictionary dictionary];
			[self addRecordAtIndex:2 toDictionary:theOther withBuffer:dataBuffer];
											 NSLog(@"The other record is this one: %@", theOther);
		
		} else {
			[self addRecordAtIndex:1 toDictionary:result withBuffer:dataBuffer];
		}
		// Deallocate recNames, recTypes, and attrTypes by calling dsDataListDeallocate.
		dsDataListDeallocate(_dirRef, &recNames);
		dsDataListDeallocate(_dirRef, &recTypes);
		dsDataListDeallocate(_dirRef, &attrTypes);
		dsDataBufferDeAllocate(_dirRef, dataBuffer);

	} while (0);
	
	return [NSDictionary dictionaryWithDictionary:result];
}


// ---------------------------------------------------------------------
// * getRecord
// ---------------------------------------------------------------------
- (NSArray*) getRecordsOfType:(NSString*)recordType fromNode:(NSString*)node
{
	tDirStatus				dirStatus = eDSNoErr;
	NSArray *res;
	NSMutableArray*			result = [[NSMutableArray alloc] init];
	
		// if the user did not give us a node, try and get the first one
	if (node == nil)
	{
			// see if any nodes were ever fetched
		if (_nodes == nil)
			[self getNodes];
			// see if there are any nodes
		if (_nodes && [_nodes count] == 0)
		{
			NSLog(@"No nodes available");
			[result release];
			return nil;
		}
		
			// use the first node we find
		node = [_nodes objectAtIndex:0];
	}

	do
	{
		if (![self openNode:node])
			break;
			
		tDataList recNames = {};
		tDataList recTypes = {};
		tDataList attrTypes = {};

		if ((eDSNoErr == (dirStatus = dsBuildListFromStringsAlloc (_dirRef, &recNames, kDSRecordsAll, nil))) &&
			(eDSNoErr == (dirStatus = dsBuildListFromStringsAlloc (_dirRef, &recTypes, [recordType UTF8String], nil))))
		{
			dirStatus = dsBuildListFromStringsAlloc (_dirRef, &attrTypes, kDSAttributesAll, nil);
		}
		
		if (dirStatus != eDSNoErr)
			break;
		
		tDataBufferPtr dataBuffer = dsDataBufferAllocate(_dirRef, 32 * 1024);
		if (dataBuffer == nil)
			break;
			
		tContextData context = 0;
		UInt32 recCount;
		dirStatus = dsGetRecordList(_nodeRef, dataBuffer, &recNames, eDSExact, &recTypes, &attrTypes, false, &recCount, &context);
		if (dirStatus != eDSNoErr)
		{
			NSLog(@"Can't get record list.  Error %d", (int)dirStatus);
			break;
		}
			
		if (recCount < 1)
		{
			NSLog(@"Number records: %d", (int)recCount);
			break;
		}
		
		unsigned long i;
		tRecordEntry* recEntry = nil;
		tAttributeListRef attrListRef;
		for (i = 1; i <= recCount; i++)
		{
			dirStatus = dsGetRecordEntry(_nodeRef, dataBuffer, (int)i, &attrListRef, &recEntry);
			NSString* recordName = [self nameOfRecord:recEntry attributes:attrListRef withBuffer:dataBuffer];
			if (recordName)
				[result addObject:recordName];
		}

		// Deallocate recNames, recTypes, and attrTypes by calling dsDataListDeallocate.
		dsDataListDeallocate(_dirRef, &recNames);
		dsDataListDeallocate(_dirRef, &recTypes);
		dsDataListDeallocate(_dirRef, &attrTypes);
		dsDataBufferDeAllocate(_dirRef, dataBuffer);

	} while (0);
	
	res = [NSArray arrayWithArray:result];
	[result release];
	return res;
}


@end


@implementation NSDirectoryServices (Private)

// ---------------------------------------------------------------------
// * openNode
// ---------------------------------------------------------------------
- (BOOL) openNode:(NSString*)node
{
    tDataListPtr			nodePath = nil;
	tDirStatus				dirStatus;

	nodePath = dsBuildFromPath(_dirRef, [node UTF8String], "/" );
	if (nodePath == nil)
		return NO;
		
	BOOL result = YES;
	dirStatus = dsOpenDirNode(_dirRef, nodePath, &_nodeRef);
	if (dirStatus != eDSNoErr)
	{
		NSLog(@"Can't open node");
		result = NO;
	}
	dsDataListDeallocate(_dirRef, nodePath);
	free(nodePath);
	
	return result;
}
static tDirStatus dsDataBufferAppendData(
										 tDataBufferPtr  buf, 
										 const void *    dataPtr, 
										 size_t          dataLen
										 )
// Appends a value to a data buffer.  dataPtr and dataLen describe 
// the value to append.  buf is the data buffer to which it's added.
{
    tDirStatus      err;
	
    assert(buf != NULL);
    assert(dataPtr != NULL);
    assert(buf->fBufferLength <= buf->fBufferSize);
    
    // The cast to size_t in the following line is unnecessary, but it helps 
    // to emphasise that we do this range check in 64-bit if size_t is 64-bit. 
    // Thus, this check will work even if you try to add more than 32-bits of 
    // data to a buffer (which is inherently limited to 32-bits because 
    // fBufferSize is UInt32).
    
    if ( (buf->fBufferLength + dataLen) > (size_t) buf->fBufferSize ) {
        err = eDSBufferTooSmall;
    } else {
        memcpy(&buf->fBufferData[buf->fBufferLength], dataPtr, dataLen);
        buf->fBufferLength += (UInt32) dataLen;
        err = eDSNoErr;
    }
    
    return err;
}

// ---------------------------------------------------------------------
// * addRecordAtIndex
// ---------------------------------------------------------------------
// add the record to the dictionary
- (void) addRecordAtIndex:(unsigned long)recIndex toDictionary:(NSMutableDictionary*)dict withBuffer:(tDataBufferPtr)dataBuffer
{
	tDirStatus dirStatus;
	short i;

	tRecordEntry* recEntry = nil;
	tAttributeListRef attrListRef;
	dirStatus = dsGetRecordEntry(_nodeRef, dataBuffer, (int)recIndex, &attrListRef, &recEntry);
	if (dirStatus == eDSNoErr)
	{
		for (i = 1; i <= recEntry->fRecordAttributeCount; i++)
		{
			tAttributeValueListRef valueRef;
			tAttributeEntry *pAttrEntry = nil;
			if (eDSNoErr == (dirStatus = dsGetAttributeEntry(_nodeRef, dataBuffer, attrListRef, i, &valueRef, &pAttrEntry)))
			{
				[self addEntry:pAttrEntry withValue:valueRef toDictionary:dict withBuffer:(tDataBufferPtr)dataBuffer];
				
				dirStatus = dsDeallocAttributeEntry(_dirRef, pAttrEntry);
			}
		}
		dsCloseAttributeList(attrListRef);
		dsDeallocRecordEntry(_dirRef, recEntry);
	}
	else
		NSLog(@"Can't get record entry - %d", dirStatus);
}


// ---------------------------------------------------------------------
// * addEntry
// ---------------------------------------------------------------------
// Adds an entry to the dictionary.  The entry could be a single value or an array of values.
- (void) addEntry:(tAttributeEntry*)pAttrEntry withValue:(tAttributeValueListRef)valueRef toDictionary:(NSMutableDictionary*)dict withBuffer:(tDataBufferPtr)dataBuffer
{
	tDirStatus dirStatus;
	tAttributeValueEntry *pValueEntry = nil;

		// if there is only one value, then we can add it to the result as a string
	if (pAttrEntry->fAttributeValueCount == 1)
	{
		if (eDSNoErr == (dirStatus = dsGetAttributeValue(_nodeRef, dataBuffer, 1, valueRef, &pValueEntry)))
		{
			[dict setObject:[NSString stringWithCString:pValueEntry->fAttributeValueData.fBufferData encoding:[NSString defaultCStringEncoding]] forKey:[NSString stringWithCString:pAttrEntry->fAttributeSignature.fBufferData encoding:[NSString defaultCStringEncoding]]];						
			dirStatus = dsDeallocAttributeValueEntry(_dirRef, pValueEntry);
		}
	} 
		// if there is more than one value, then we need to add it to the result as an array
	else if (pAttrEntry->fAttributeValueCount > 1)
	{
		NSMutableArray* entries = [NSMutableArray new];
		unsigned long k;
			// iterate over all the entries and add them to the array
		for (k = 1; k <= pAttrEntry->fAttributeValueCount; k++)
		{
			if (eDSNoErr == (dirStatus = dsGetAttributeValue(_nodeRef, dataBuffer, (int)k, valueRef, &pValueEntry)))
			{
				[entries addObject:[NSString stringWithCString:pValueEntry->fAttributeValueData.fBufferData encoding:[NSString defaultCStringEncoding]]];							
				dirStatus = dsDeallocAttributeValueEntry(_dirRef, pValueEntry);
			}
		}
		
		[dict setObject:[NSArray arrayWithArray:entries] forKey:[NSString stringWithCString:pAttrEntry->fAttributeSignature.fBufferData]];
		[entries release];
	}
}


// ---------------------------------------------------------------------
// * nameOfRecord
// ---------------------------------------------------------------------
// looks through all the attributes and finds the name attribute.  And returns it.
- (NSString*) nameOfRecord:(tRecordEntry*)recEntry attributes:(tAttributeListRef)attrListRef withBuffer:(tDataBufferPtr)dataBuffer
{
	tDirStatus dirStatus = eDSNoErr;
	unsigned long i;

		// iterate through all the attributes looking for the name attribute
	for (i = 1; i <= recEntry->fRecordAttributeCount; i++)
	{
		tAttributeValueListRef valueRef;
		tAttributeEntry *pAttrEntry = nil;
		
			// get the attribute
		if (eDSNoErr == (dirStatus = dsGetAttributeEntry(_nodeRef, dataBuffer, attrListRef, (int)i, &valueRef, &pAttrEntry)))
		{
				// cehck to see if this is the name attribute
			if (0 == strcmp(pAttrEntry->fAttributeSignature.fBufferData, kDSNAttrRecordName))
			{
					// this is the name attribute.  Now fetch the value and return it.
				tAttributeValueEntry *pValueEntry = nil;
				NSString* result = nil;
				if (eDSNoErr == (dirStatus = dsGetAttributeValue(_nodeRef, dataBuffer, 1, valueRef, &pValueEntry)))
					result = [NSString stringWithCString:pValueEntry->fAttributeValueData.fBufferData];

				dsDeallocAttributeEntry(_dirRef, pAttrEntry);
				return result;
			}
								
			dsDeallocAttributeEntry(_dirRef, pAttrEntry);
		}
	}

		// no name was found.  This should never happen.
	return nil;
}

@end
