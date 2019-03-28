//
//  NSString+Helper.m
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

#import "NSString+Helper.h"


@implementation NSString (StringHelper)

-(NSString *)trim
{
	NSString *s = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return s;
}

- (NSString *)midStartAt:(int)aStart end:(int)aEnd
{	
	NSString *newstring = @" ";
	if (aStart >= [self length]) {
		// This will gen a error
	} else {
		newstring = [self substringWithRange:NSMakeRange(aStart, aEnd)];
	}
	
	return newstring;
}

- (BOOL)containsString:(NSString *)aString
{
    return [self containsString:aString ignoringCase:YES];
}

- (BOOL)containsString:(NSString *)aString ignoringCase:(BOOL)flag
{
    unsigned mask = (flag ? NSCaseInsensitiveSearch : 0);
    NSRange range = [self rangeOfString:aString options:mask];
    return (range.length > 0);
}

- (BOOL)isEqualToString:(NSString *)aString ignoringCase:(BOOL)flag
{
	return [[self uppercaseString] isEqualToString:[aString uppercaseString]];
}

+ (NSString *)versionStringForApplication:(NSString *)appPath 
{
	NSBundle *xBundle = [NSBundle bundleWithPath:appPath];
	NSDictionary *xInfo = [xBundle infoDictionary];
	return [xInfo objectForKey:@"CFBundleShortVersionString"];
}

- (NSString *)replace:(NSString *)aSubString replaceString:(NSString *)aReplaceString
{
	NSRange replaceRange = [self rangeOfString:aSubString];
	if (replaceRange.location !=NSNotFound){
		NSString *newString;		
		newString = [self stringByReplacingCharactersInRange:replaceRange withString:aReplaceString];
		return newString;	
	}
	
	return self;
}

- (NSString *)replaceAll:(NSString *)aSubString replaceString:(NSString *)aReplaceString
{
	NSMutableString *mString = [self mutableCopy];
	[mString replaceOccurrencesOfString:aSubString withString:aReplaceString options:NSCaseInsensitiveSearch range:(NSRange){0,[mString length]}];
	NSString *returnString = [NSString stringWithString:mString];
	return returnString;
}

- (NSString *)replaceAllUsingObjects:(NSArray *)aSubStringObjects replaceString:(NSString *)aReplaceString
{
    NSMutableString *mString = [self mutableCopy];
    for (NSString *obj in aSubStringObjects) {
        [mString replaceOccurrencesOfString:obj withString:aReplaceString options:NSCaseInsensitiveSearch range:(NSRange){0,[mString length]}];
    }
	NSString *returnString = [NSString stringWithString:mString];
	return returnString;
}

- (NSString *)urlEncode
{
	return [self urlEncodeUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)urlEncodeUsingEncoding:(NSStringEncoding)encoding
{
    //(CFStringRef)@"!*'\"();:@&=+$,/?%#[]% ",
	return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL,
                                                               (CFStringRef)self,
                                                               NULL,
                                                               (CFStringRef)@"!*'\"();:@&=+$,?%#[]% ",
                                                               CFStringConvertNSStringEncodingToEncoding(encoding)));
}

- (NSString *)urlEncodeCustom
{
	NSMutableString *output = [NSMutableString string];
	const unsigned char *source = (const unsigned char *)[self UTF8String];
	int sourceLen = (int)strlen((const char *)source);
	for (int i = 0; i < sourceLen; ++i) {
		const unsigned char thisChar = source[i];
		if (thisChar == ' '){
			[output appendString:@"+"];
		} else if (thisChar == '.' || thisChar == '-' || thisChar == '_' || thisChar == '~' ||
				   (thisChar >= 'a' && thisChar <= 'z') ||
				   (thisChar >= 'A' && thisChar <= 'Z') ||
				   (thisChar >= '0' && thisChar <= '9')) {
			[output appendFormat:@"%c", thisChar];
		} else {
			[output appendFormat:@"%%%02X", thisChar];
		}
	}
	return output;
}


- (NSArray *)componentsSeparatedByString:(NSString *)aSeperator escapeString:(NSString *)aEscString
{
	NSString *filler = @"**$$";
	NSString *tmp1, *tmp2;
	tmp1 = [self stringByReplacingOccurrencesOfString:aEscString withString:filler];
	NSMutableArray *tmpArray = [[NSMutableArray alloc] initWithArray:[tmp1 componentsSeparatedByString:aSeperator]];
	
	int i = 0;
	for (i = 0; i < [tmpArray count]; i++) {
		tmp2 = [[tmpArray objectAtIndex:i] stringByReplacingOccurrencesOfString:filler withString:aSeperator];
		[tmpArray replaceObjectAtIndex:i withObject:tmp2];
	} 
	
	NSArray *result = [NSArray arrayWithArray:tmpArray];
	return result;
}

- (BOOL)stringToBoolValue
{
	NSString *_BoolString = [self uppercaseString];
    
    if ([_BoolString isEqualTo:@"0"]) {
        return FALSE;
    }
    if ([_BoolString isEqualTo:@"1"]) {
        return TRUE;
    }
	if ([_BoolString isEqualTo:@"N"]) {
        return FALSE;
    }
    if ([_BoolString isEqualTo:@"Y"]) {
        return TRUE;
    }
    if ([_BoolString isEqualTo:@"NO"]) {
        return FALSE;
    }
    if ([_BoolString isEqualTo:@"YES"]) {
        return TRUE;
    }  
    if ([_BoolString isEqualTo:@"T"]) {
        return TRUE;
    }
    if ([_BoolString isEqualTo:@"F"]) {
        return FALSE;
    }
    if ([_BoolString isEqualTo:@"TRUE"]) {
        return TRUE;
    }
    if ([_BoolString isEqualTo:@"FALSE"]) {
        return FALSE;
    }
    
    return FALSE;
}

- (NSString *)validXMLString
{
	// Not all UTF8 characters are valid XML.
	// See:
	// http://www.w3.org/TR/2000/REC-xml-20001006#NT-Char
	// (Also see: http://cse-mjmcl.cse.bris.ac.uk/blog/2007/02/14/1171465494443.html )
	//
	// The ranges of unicode characters allowed, as specified above, are:
	// Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF] /* any Unicode character, excluding the surrogate blocks, FFFE, and FFFF. */
	//
	// To ensure the string is valid for XML encoding, we therefore need to remove any characters that
	// do not fall within the above ranges.
	
	// First create a character set containing all invalid XML characters.
	// Create this once and leave it in memory so that we can reuse it rather
	// than recreate it every time we need it.
	static NSCharacterSet *invalidXMLCharacterSet = nil;
	
	if (invalidXMLCharacterSet == nil)
	{
		// First, create a character set containing all valid UTF8 characters.
		NSMutableCharacterSet *XMLCharacterSet = [[NSMutableCharacterSet alloc] init];
		[XMLCharacterSet addCharactersInRange:NSMakeRange(0x9, 1)];
		[XMLCharacterSet addCharactersInRange:NSMakeRange(0xA, 1)];
		[XMLCharacterSet addCharactersInRange:NSMakeRange(0xD, 1)];
		[XMLCharacterSet addCharactersInRange:NSMakeRange(0x20, 0xD7FF - 0x20)];
		[XMLCharacterSet addCharactersInRange:NSMakeRange(0xE000, 0xFFFD - 0xE000)];
		[XMLCharacterSet addCharactersInRange:NSMakeRange(0x10000, 0x10FFFF - 0x10000)];
		
		// Then create and retain an inverted set, which will thus contain all invalid XML characters.
		invalidXMLCharacterSet = [XMLCharacterSet invertedSet];
	}
	
	// Are there any invalid characters in this string?
	NSRange range = [self rangeOfCharacterFromSet:invalidXMLCharacterSet];
	
	// If not, just return self unaltered.
	if (range.length == 0)
		return self;
	
	// Otherwise go through and remove any illegal XML characters from a copy of the string.
	NSMutableString *cleanedString = [self mutableCopy];
	
	while (range.length > 0)
	{
		[cleanedString deleteCharactersInRange:range];
		range = [cleanedString rangeOfCharacterFromSet:invalidXMLCharacterSet];
	}
	
	//
    NSArray *cleanFromString = [NSArray arrayWithObjects:@"&quot;",@"&lt;",@"&amp;",@"&gt;",@"&apos;",nil];
    /*
	cleanedString = (NSMutableString *)[cleanedString replaceAll:@"&quot;" replaceString:@""];
	cleanedString = (NSMutableString *)[cleanedString replaceAll:@"&lt;" replaceString:@""];
	cleanedString = (NSMutableString *)[cleanedString replaceAll:@"&amp;" replaceString:@""];
	cleanedString = (NSMutableString *)[cleanedString replaceAll:@"&gt;" replaceString:@""];
	cleanedString = (NSMutableString *)[cleanedString replaceAll:@"&apos;" replaceString:@""];
     */
    
    NSString *cleanString = [cleanedString replaceAllUsingObjects:cleanFromString replaceString:@""];
	return cleanString;
}

- (BOOL)isNSStringType
{
    if ([[self className] isMemberOfClass: [NSString class]]) {
        return YES;
    }
    if ([[self class] isKindOfClass: [NSString class]]) {
        return YES;
    }
    if ([[self classForCoder] isSubclassOfClass: [NSString class]]) {
        return YES;
    }
    
    return NO;
}

- (BOOL)isBase64String
{
	NSString *b64Str = [self copy];
	b64Str = [[b64Str componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
	if ([b64Str length] % 4 == 0) {
		static NSCharacterSet *invertedBase64CharacterSet = nil;
		if (invertedBase64CharacterSet == nil) {
			invertedBase64CharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="]invertedSet];
		}
		return [b64Str rangeOfCharacterFromSet:invertedBase64CharacterSet options:NSLiteralSearch].location == NSNotFound;
	}
	return NO;
}

@end
