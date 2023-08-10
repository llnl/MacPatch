//
//  AHCodesignVerifier.h
//
// Copyright (c) 2014 Eldon Ahrold
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>

/**
 *  Simple Class that checks wether two items are signed with the same
 * certificate
 */
@interface AHCodesignVerifier : NSObject
/**
 *  Get the name of the certificate used to code sign the application.
 *
 *  @param path  Path to the App bundle or executable.
 *  @param error Populated NSError object should error occur.
 *
 *  @return Name of the certificate
 */
+ (NSString*)certNameOfItemAtPath:(NSString*)path error:(NSError**)error;

/**
 *  Test the codesign of an itema at a path.
 *
 *  @param path  Path to the App bundle or executable.
 *  @param error Populated NSError object should error occur.
 *
 *  @return YES if the codesign is complete and valid, NO if there are any issues whith the codesign.
 */
+ (BOOL)codeSignOfItemAtPathIsValid:(NSString *)path
                              error:(NSError**)error;

/**
 *  Test the codesign of an itema at a path.
 *
 *  @param path  Path to the App bundle or executable.
 *  @param deep  Whether the check should recursively check nested code 
 *  @param error Populated NSError object should error occur.
 *
 *  @return YES if the codesign is complete and valid, NO if there are any issues whith the codesign.
 */
+ (BOOL)codeSignOfItemAtPathIsValid:(NSString *)path
                               deep:(BOOL)deep
                              error:(NSError**)error;
/**
 *  Check wether two items are code signed by the same certificate.
 *
 *  @param item1 First item.
 *  @param item2 Second item.
 *  @param error Populated NSError object should error occur.
 *
 *  @return YES if they match, NO otherwise
 */
+ (BOOL)codesignOfItemAtPath:(NSString*)item1
          isSameAsItemAtPath:(NSString*)item2
                       error:(NSError**)error;
@end
