//
//  MPPython.m
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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

#import "MPPython.h"
#include "Python/Python.h"
#include <stdlib.h>

@implementation MPPython

@synthesize virtualEnvPath = _virtualEnvPath;

- (id)initWithVirtualEnv:(NSString *)vEnvPath
{
    self = [super init];
    if (self) {
        [self setVirtualEnvPath:vEnvPath];
    }
    return self;
}

#pragma mark - Safety Methods

- (BOOL)virualEnvExists:(NSString *)vEnvPath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:vEnvPath]) {
        return YES;
    }
    return NO;
}

- (int)createEnvExists:(NSString *)vEnvPath error:(NSError **)error
{
    return 0;
}


#pragma mark - Run Python Code

- (int)runPySimpleScript:(NSString *)aScript error:(NSError **)error
{
    int result;
    NSDictionary *userInfo;
    
    // Set Python Path, for virtualenv
    if (_virtualEnvPath) {
        setenv("PYTHONPATH",[_virtualEnvPath UTF8String], 0);
        Py_OptimizeFlag=1;
        Py_SetPythonHome((char*)[_virtualEnvPath UTF8String]);
    }
    
    // Initialize the Python interpreter.
    Py_Initialize();
    
    // Script Contains exit, exit will exit the whole app
    NSRange range = [aScript rangeOfString:@"exit\\([0-9]\\)" options:NSRegularExpressionSearch];
    if (range.location != NSNotFound) {
        result = 1;
        if (error != NULL) {
            userInfo = @{ NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Unable to run python code.", nil),
                          NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Have you tried turning it off and on again?", nil)};
            *error = [NSError errorWithDomain:@"gov.llnl.py.error" code:10001 userInfo:userInfo];
        }
        return result;
    }
    
    result = PyRun_SimpleString([[aScript stringByAppendingString: @"\n"] UTF8String]);
    Py_Finalize();
    
    return result;
}

- (id)runPyScriptDef:(NSString *)aScript def:(NSString *)defName error:(NSError **)error
{
    id result = nil;
    NSDictionary *userInfo;
    
    // Set Python Path, for virtualenv
    if (_virtualEnvPath) {
        setenv("PYTHONPATH",[_virtualEnvPath UTF8String], 0);
        Py_OptimizeFlag=1;
        Py_SetPythonHome((char*)[_virtualEnvPath UTF8String]);
    }
    
    // Initialize the Python Interpreter
    Py_Initialize();
    
    // Run the string to so we can get its defined functions
    int pyRun = PyRun_SimpleString([aScript UTF8String]);
    if (pyRun != 0) {
        if (error != NULL) {
            userInfo = @{ NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Unable to run python code.", nil),
                          NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Have you tried turning it off and on again?", nil)};
            *error = [NSError errorWithDomain:@"gov.llnl.py.error" code:10001 userInfo:userInfo];
        }
        Py_Finalize();
        return result;
    }
    
    // Get the main environment
    PyObject *py_main = PyImport_AddModule("__main__");
    PyObject *py_main_dict = PyModule_GetDict(py_main);
    
    // Add Platform module, example
    PyObject *platform_module = PyImport_ImportModule("platform");
    PyDict_SetItemString(py_main_dict, "platform", platform_module);
    
    //Get a reference to our function (this should be made constant for speed).
    PyObject *py_func = PyDict_GetItemString(py_main_dict, [defName UTF8String]);
    if (!PyCallable_Check(py_func)) {
        if (error != NULL) {
            userInfo = @{ NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Failed to verify python function.", nil),
                          NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Have you tried turning it off and on again?", nil)};
            *error = [NSError errorWithDomain:@"gov.llnl.py.error" code:10002 userInfo:userInfo];
        }
        qlinfo(@"Function (%@) does not exist.",@"xaudit");
        Py_Finalize();
        return result;
    }
    
    PyObject *py_value = PyObject_CallObject(py_func, NULL);
    if (PyErr_Occurred()) {
        NSString *errMsg;
        PyObject *pTypeObj = NULL;
        PyObject *pValueObj = NULL;
        PyObject *pWhatObj = NULL;
        PyErr_Fetch(&pTypeObj, &pValueObj, &pWhatObj);
        if (pValueObj) {
            if (PyBytes_Check(pValueObj)) {
                errMsg = [NSString stringWithUTF8String:PyBytes_AsString(pValueObj)];
            }
        }
        Py_XDECREF(pWhatObj);
        Py_XDECREF(pValueObj);
        Py_XDECREF(pTypeObj);
        
        if (error != NULL) {
            userInfo = @{ NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(errMsg, nil),
                          NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Have you tried turning it off and on again?", nil)};
            *error = [NSError errorWithDomain:@"gov.llnl.py.error" code:10002 userInfo:userInfo];
        }
    }
    
    if (py_value != NULL) {
        if (PyDict_Check(py_value)) {
            result = [self dictionaryFromPyObject:py_value];
            qlerror(@"%@",result);
        } else if (PyString_Check(py_value)) {
            result = [self stringFromPyObject:py_value];
        }
        Py_DECREF(py_value);
    }
    
    Py_Finalize();
    return result;
}

- (id)runPyScriptGetValueFromVariable:(NSString *)aScript variable:(NSString *)varName error:(NSError **)error
{
    id result = nil;
    NSDictionary *userInfo;
    
    // Set Python Path, for virtualenv
    if (_virtualEnvPath) {
        setenv("PYTHONPATH",[_virtualEnvPath UTF8String], 0);
        Py_OptimizeFlag=1;
        Py_SetPythonHome((char*)[_virtualEnvPath UTF8String]);
    }
    
    // Initialize the Python Interpreter
    Py_Initialize();
    
    // Get the main environment
    PyObject *py_main = PyImport_AddModule("__main__");
    PyObject *py_dict = PyModule_GetDict(py_main);
    
    // Run the python source code
    PyRun_String([aScript UTF8String],
                 Py_file_input,
                 py_dict,
                 py_dict);
    
    // Get Variable Value from Script
    PyObject *py_result = PyDict_GetItemString(py_dict, [varName UTF8String]);
    if (!py_result) {
        if (error != NULL) {
            userInfo = @{ NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Unable to get variable from python code.", nil),
                          NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Have you tried turning it off and on again?", nil)};
            *error = [NSError errorWithDomain:@"gov.llnl.py.error" code:10002 userInfo:userInfo];
        }
        Py_Finalize();
        return nil;
    }
    
    // Convert PyObject to NSObject id type
    result = [self idFromPyObject:py_result];
    if (!result) {
        qlerror(@"Failed converting PyObject to id object.");
        if (error != NULL) {
            userInfo = @{ NSLocalizedDescriptionKey: NSLocalizedString(@"Operation was unsuccessful.", nil),
                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Failed converting PyObject to id object.", nil),
                          NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Have you tried turning it off and on again?", nil)};
            *error = [NSError errorWithDomain:@"gov.llnl.py.error" code:10002 userInfo:userInfo];
        }
        Py_Finalize();
        return nil;
    }
    
    Py_Finalize();
    return result;
}

#pragma mark - PyObject Parsing

- (id)idFromPyObject:(PyObject *)pyObj
{
    id result;
    
    if (pyObj == Py_None) {
        result = nil;
    }
    else if (PyString_Check(pyObj)) {
        result = [self stringFromPyObject:pyObj];
    }
    else if (PyInt_Check(pyObj)) {
        result = [NSNumber numberWithInt:(int)_PyInt_AsInt(pyObj)];
    }
    else if (PyLong_Check(pyObj)) {
        result = [NSNumber numberWithInt:(int)PyInt_AsLong(pyObj)];
    }
    else if (PyFloat_Check(pyObj)) {
        result = [NSNumber numberWithDouble:(double)PyFloat_AsDouble(pyObj)];
    }
    else if (PyBool_Check(pyObj)) {
        if (PyObject_IsTrue(pyObj)) {
            result = [NSNumber numberWithBool:TRUE];
        } else {
            result = [NSNumber numberWithBool:FALSE];
        }
    }
    else if (PyDict_Check(pyObj)) {
        result = [self dictionaryFromPyObject:pyObj];
    }
    else if (PyList_Check(pyObj)) {
        result = [self arrayFromPyObject:pyObj];
    }
    else {
        qlerror(@"Warning, idFromPyObject failed.");
        result = nil;
    }
    
    return result;
}

- (NSArray *)arrayFromPyObject:(PyObject *)pList
{
    if (pList == Py_None) {
        return nil;
    }
    
    NSMutableArray *result = [NSMutableArray array];
    
    PyObject *iterator = PyObject_GetIter(pList);
    PyObject *item;
    while ( (item = PyIter_Next(iterator)) )
    {
        id value = [self idFromPyObject:item];
        if (value == nil) {
            value = [NSNull null];
        }
        [result addObject:value];
        Py_DECREF(item);
    }
    
    Py_DECREF(iterator);
    return result;
}

- (NSString *)stringFromPyObject:(PyObject *)pStr
{
    if (pStr == Py_None) {
        return nil;
    }
    
    char *pyStr = PyString_AsString(pStr);
    NSString *result = [NSString stringWithUTF8String:pyStr];
    
    return result;
}

- (NSDictionary *)dictionaryFromPyObject:(PyObject *)pDict
{
    if (pDict == Py_None) {
        return nil;
    }
    PyObject *pKey, *pValue;
    Py_ssize_t pos = 0;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    while (PyDict_Next(pDict, &pos, &pKey, &pValue))
    {
        NSString *key = [self stringFromPyObject:pKey];
        id value = [self idFromPyObject:pValue];
        if (value == nil) {
            value = [NSNull null];
        }
        [result setObject:value forKey:key];
    }
    
    return result;
}

@end
