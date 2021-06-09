//
//  MPPython.h
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

#import <Foundation/Foundation.h>
#include "Python/Python.h"

@interface MPPython : NSObject

@property (nonatomic, weak) NSString *virtualEnvPath;

/**
 Initialize Class with a python virtualenv

 @param vEnvPath Virtualenv path
 @return id
 */
- (id)initWithVirtualEnv:(NSString *)vEnvPath;

/**
 Run a python script, no input and no return values
 
 @param aScript Python Script string
 @param error NSError or NULL
 @return return code
 */
- (int)runPySimpleScript:(NSString *)aScript error:(NSError **)error;

/**
 Run Python Script method in the main name space
 
 @param aScript Python Script string
 @param defName Name of python method
 @param error NSError or NULL
 @return return id type object of the method
 */
- (id)runPyScriptDef:(NSString *)aScript def:(NSString *)defName error:(NSError **)error;

/**
 Run Python Script and get the value of a global variable
 
 @param aScript Python Script string
 @param varName Variable Name
 @param error NSError or NULL
 @return return id type object of the method
 */
- (id)runPyScriptGetValueFromVariable:(NSString *)aScript variable:(NSString *)varName error:(NSError **)error;

// Python PyObject Helpers

/**
 Return id object from PyObject
 Will determin the Python Object Type and return
 a Objective C class type.
 
 @param pyObj Python C PyObjct
 @return returns an id on any NSObject type
 */
- (id)idFromPyObject:(PyObject *)pyObj;

/**
 Python PyObject List type to NSArray
 
 @param pList Python List Object
 @return NSArray
 */
- (NSArray *)arrayFromPyObject:(PyObject *)pList;

/**
 Python PyObject String type to NSString
 
 @param pStr Python string object
 @return NSString
 */
- (NSString *)stringFromPyObject:(PyObject *)pStr;

/**
 Python PyObject Dictionary type to NSDictionary
 
 @param pDict Python Dictionary type
 @return NSDictionary
 */
- (NSDictionary *)dictionaryFromPyObject:(PyObject *)pDict;

@end
