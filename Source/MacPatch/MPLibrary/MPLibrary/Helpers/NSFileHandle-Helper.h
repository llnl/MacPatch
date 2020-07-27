//
//  NSFileHandle-Helper.h
//  MPLibrary
//
//  Created by Charles Heizer on 7/24/20.
//

#import <Foundation/Foundation.h>

@interface NSFileHandle (MPNSFileHandleAdditions)
- (NSData *)availableDataOrError:(NSException **)returnError;
@end

