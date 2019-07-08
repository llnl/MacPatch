//
//
// qlog.h -- 1.0.3
//
//
// Copyright (c) 2009-2011 Arne Harren <ah@0xc0.de>
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
// messages and qltrace() for trace messages. Additionally, all logging macros
// take the current log component from the ql_component preprocessor define
// which can be (re)defined in your application at a file-level, section-based,
// or global scope. If you want to include the log component in your logging
// statements instead of using the ql_component define, you can use the _c
// variants of the logging macros which take the log component as the first
// argument, e.g. qlerror_c(lcl_cMain), qltrace_c(lcl_cMain, @"message").
//


//
// qlog macros which use the currently active ql_component
//


#define qlcritical(...)                                                        \
    lcl_log(ql_component, lcl_vCritical, @"" __VA_ARGS__)

#define qlerror(...)                                                           \
    lcl_log(ql_component, lcl_vError, @"" __VA_ARGS__)

#define qlwarning(...)                                                         \
    lcl_log(ql_component, lcl_vWarning, @"" __VA_ARGS__)

#define qlinfo(...)                                                            \
    lcl_log(ql_component, lcl_vInfo, @"" __VA_ARGS__)

#define qldebug(...)                                                           \
    lcl_log(ql_component, lcl_vDebug, @"" __VA_ARGS__)

#define qltrace(...)                                                           \
    lcl_log(ql_component, lcl_vTrace, @"" __VA_ARGS__)


//
// qlog-_c macros which take the log component as first argument
//


#define qlcritical_c(log_component, ...)                                       \
    lcl_log(log_component, lcl_vCritical, @"" __VA_ARGS__)

#define qlerror_c(log_component, ...)                                          \
    lcl_log(log_component, lcl_vError, @"" __VA_ARGS__)

#define qlwarning_c(log_component, ...)                                        \
    lcl_log(log_component, lcl_vWarning, @"" __VA_ARGS__)

#define qlinfo_c(log_component, ...)                                           \
    lcl_log(log_component, lcl_vInfo, @"" __VA_ARGS__)

#define qldebug_c(log_component, ...)                                          \
    lcl_log(log_component, lcl_vDebug, @"" __VA_ARGS__)

#define qltrace_c(log_component, ...)                                          \
    lcl_log(log_component, lcl_vTrace, @"" __VA_ARGS__)

