//
//  FMXHelpers.h
//  FMDBx
//
//  Copyright (c) 2014 KohkiMakimoto. All rights reserved.
//

#import <Foundation/Foundation.h>

NSString *FMXSnakeCaseFromCamelCase(NSString *input);
NSString *FMXLowerCamelCaseFromSnakeCase(NSString *input);
NSString *FMXUpperCamelCaseFromSnakeCase(NSString *input);
NSString *FMXDefaultTableNameFromModelName(NSString *input);
SEL FMXSetterSelectorFromColumnName(NSString *input);
