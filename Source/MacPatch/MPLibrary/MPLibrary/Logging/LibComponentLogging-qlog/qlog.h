//
//
// qlog.h -- 1.1.2
//
//
// Copyright (c) 2009-2015 Arne Harren <ah@0xc0.de>
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


//
// qlog -- a set of quick logging macros for LibComponentLogging.
//
// qlog just consists of this small header file which defines a short logging
// macro for every log level of LibComponentLogging, e.g. qlerror() for error
// messages and qltrace() for trace messages. All qlog macros support a format
// string and arguments, e.g. qlerror(@"code %d", code).
//
// All logging macros take the current log component from the ql_component
// preprocessor define which can be (re)defined in your application per file,
// per section, or at global scope.
//
// If you want to include the log component in your logging statements instead
// of using the ql_component define, you can use the _c variants of the qlog
// macros which take the log component as the first argument, e.g.
// qlerror_c(lcl_cMain), or qltrace_c(lcl_cMain, @"message").
//
// The *_if variants of the qlog macros use LibComponentLogging's lcl_log_if
// conditional logging macro.
//
// To install qlog, just copy the qlog.h header file to your project and add
// an import of qlog.h to your prefix header file or to your LibComponentLogging
// extensions configuration file lcl_config_extensions.h:
//
//   #import "qlog.h"
//
// Then, define the preprocessor symbol ql_component at a global scope with your
// default log component, e.g. add a define to your prefix header file:
//
//   #define ql_component lcl_cDefaultLogComponent
//
// Now, logging statements can be added to your application by simply using the
// qlog macros instead of LibComponentLogging's lcl_log macros:
//
//   qlinfo(@"initialized");
//   qlerror(@"file '%@' does not exist", file);
//   qltrace();
//
// All these logging statements will use the log component from the ql_component
// define which is visible at the location of the logging statement.
//
// If you want to use a specific log component for all logging statements in a
// file, you can simply redefine ql_component to match this log component, e.g.
// by adding a #undef #define sequence at the top of the file, e.g.
//
//   #undef ql_component
//   #define ql_component lcl_cFileLevelComponent
//
// If you want to use a specific log component at a specific location in your
// code, you can use the _c variants of the macros which take the log component
// as the first argument, e.g.
//
//  qlinfo_c(lcl_cMain, @"initialized");
//  qlerror_c(lcl_cMain, @"file '%@' does not exist", file);
//  qltrace_c(lcl_cMain);
//

//
// Allow use qlog in C apps
//

#ifndef __OBJC__
#    ifndef _LCL_LOG_C_STRING
#        define _LCL_LOG_C_STRING
#    endif
#endif

#if (defined(_LCL_LOG_C_STRING)) || (defined(__lcl_c_mode))
#    define _qlog_str ""
#else
#    define _qlog_str @""
#endif

//
// qlog macros which use the currently active ql_component
//

#define qlcritical(...)                                                        \
    lcl_log(ql_component, lcl_vCritical, _qlog_str __VA_ARGS__)

#define qlerror(...)                                                           \
    lcl_log(ql_component, lcl_vError, _qlog_str __VA_ARGS__)

#define qlwarning(...)                                                         \
    lcl_log(ql_component, lcl_vWarning, _qlog_str __VA_ARGS__)

#define qlinfo(...)                                                            \
    lcl_log(ql_component, lcl_vInfo, _qlog_str __VA_ARGS__)

#define qldebug(...)                                                           \
    lcl_log(ql_component, lcl_vDebug, _qlog_str __VA_ARGS__)

#define qltrace(...)                                                           \
    lcl_log(ql_component, lcl_vTrace, _qlog_str __VA_ARGS__)


//
// qlog-_if macros which use the currently active ql_component
//


#define qlcritical_if(predicate, ...)                                          \
    lcl_log_if(ql_component, lcl_vCritical, predicate, _qlog_str __VA_ARGS__)

#define qlerror_if(predicate, ...)                                             \
    lcl_log_if(ql_component, lcl_vError, predicate, _qlog_str __VA_ARGS__)

#define qlwarning_if(predicate, ...)                                           \
    lcl_log_if(ql_component, lcl_vWarning, predicate, _qlog_str __VA_ARGS__)

#define qlinfo_if(predicate, ...)                                              \
    lcl_log_if(ql_component, lcl_vInfo, predicate, _qlog_str __VA_ARGS__)

#define qldebug_if(predicate, ...)                                             \
    lcl_log_if(ql_component, lcl_vDebug, predicate, _qlog_str __VA_ARGS__)

#define qltrace_if(predicate, ...)                                             \
    lcl_log_if(ql_component, lcl_vTrace, predicate, _qlog_str __VA_ARGS__)


//
// qlog-_c macros which take the log component as first argument
//


#define qlcritical_c(log_component, ...)                                       \
    lcl_log(log_component, lcl_vCritical, _qlog_str __VA_ARGS__)

#define qlerror_c(log_component, ...)                                          \
    lcl_log(log_component, lcl_vError, _qlog_str __VA_ARGS__)

#define qlwarning_c(log_component, ...)                                        \
    lcl_log(log_component, lcl_vWarning, _qlog_str __VA_ARGS__)

#define qlinfo_c(log_component, ...)                                           \
    lcl_log(log_component, lcl_vInfo, _qlog_str __VA_ARGS__)

#define qldebug_c(log_component, ...)                                          \
    lcl_log(log_component, lcl_vDebug, _qlog_str __VA_ARGS__)

#define qltrace_c(log_component, ...)                                          \
    lcl_log(log_component, lcl_vTrace, _qlog_str __VA_ARGS__)


//
// qlog-_c_if macros which take the log component as first argument
//


#define qlcritical_c_if(log_component, predicate, ...)                         \
    lcl_log_if(log_component, lcl_vCritical, predicate, _qlog_str __VA_ARGS__)

#define qlerror_c_if(log_component, predicate, ...)                            \
    lcl_log_if(log_component, lcl_vError, predicate, _qlog_str __VA_ARGS__)

#define qlwarning_c_if(log_component, predicate, ...)                          \
    lcl_log_if(log_component, lcl_vWarning, predicate, _qlog_str __VA_ARGS__)

#define qlinfo_c_if(log_component, predicate, ...)                             \
    lcl_log_if(log_component, lcl_vInfo, predicate, _qlog_str __VA_ARGS__)

#define qldebug_c_if(log_component, predicate, ...)                            \
    lcl_log_if(log_component, lcl_vDebug, predicate, _qlog_str __VA_ARGS__)

#define qltrace_c_if(log_component, predicate, ...)                            \
    lcl_log_if(log_component, lcl_vTrace, predicate, _qlog_str __VA_ARGS__)

