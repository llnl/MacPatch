//
//  NSDirectoryServices.h
//
//

/*
 * http://javworld.com/Extreme/DirServ.html
 * Copyright © 2004 John A. Vink
 * Modified extensively by Daniel Hoit
 */

#import <DirectoryService/DirServicesTypes.h>
extern NSString *const DHDSSEARCHNODE;
extern NSString *const DHDSComputerAccountType;
extern NSString *const DHDSUserAccountType;
extern NSString *const DHDSGroupAccountType;

@interface NSDirectoryServices : NSObject
{
	tDirReference			_dirRef;
	NSArray*				_nodes;
	tDirNodeReference		_nodeRef;
}
- (NSArray*) getNodes;
- (NSArray*) getLocalNodes;
- (NSArray*) getRecordsOfType:(NSString*)recordType fromNode:(NSString*)node;
- (NSDictionary*) getRecord:(NSString*)recordName ofType:(NSString*)recordType fromNode:(NSString*)node;
- (BOOL)setPassword:(NSString *)password forUser:(NSString *)user inDsNode:(NSString *)node error:(NSError **)dsError; 

@end
