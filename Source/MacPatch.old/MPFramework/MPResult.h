//
//  MPResult.h
//  MPLibrary
//
//  Created by Charles Heizer on 5/20/16.
//
//

#import <Foundation/Foundation.h>

@interface MPResult : NSObject
{
    NSData          *resultData;
}

@property (nonatomic, strong) NSData *resultData;

- (id)initWithResultData:(NSData *)aResultObj;
- (id)returnResultUsingType:(NSString *)aType error:(NSError **)aError;

//- (id)deserializeJSONString:(NSString *)JSONString error:(NSError **)aError;
//- (NSString *)serializeJSONDataAsString:(NSDictionary *)aData error:(NSError **)aError;

@end
