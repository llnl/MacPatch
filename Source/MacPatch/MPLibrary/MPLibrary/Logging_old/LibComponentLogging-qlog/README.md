

# LibComponentLogging-qlog

[http://0xc0.de/LibComponentLogging](http://0xc0.de/LibComponentLogging)    
[http://github.com/aharren/LibComponentLogging-qlog](http://github.com/aharren/LibComponentLogging-qlog)


## Overview

qlog -- a set of quick logging macros for LibComponentLogging.

qlog is just a small header file which defines a short logging macro for
every log level of LibComponentLogging, e.g. qlerror() for error messages
and qltrace() for trace messages. Additionally, all logging macros take the
current log component from the ql_component preprocessor define which can
be (re)defined in your application at a file-level, section-based, or global
scope. If you want to include the log component in your logging statements
instead of using the ql_component define, you can use the _c variants of
the logging macros which take the log component as the first argument, e.g.
qlerror_c(lcl_cMain), qltrace_c(lcl_cMain, @"message").


## Usage

To install qlog, just copy the qlog.h header file to your project and add an
import of qlog.h to your prefix header file or to your LibComponentLogging
extensions configuration file, e.g.

    //
    // lcl_config_extensions.h
    //
    ...
    #import "qlog.h"
    ...

Then, define the preprocessor symbol ql_component at a global scope with your
default log component, e.g. add a define to your prefix header file:

    #define ql_component lcl_cDefaultLogComponent

Now, logging statements can be added to your application by simply using the
qlog macros instead of LibComponentLogging's lcl_log macros:

    qlinfo(@"initialized");
    qlerror(@"file '%@' does not exist", file);
    qltrace();

All these logging statements will use the log component from the ql_component
define which is visible at the location of the logging statement.

If you want to use a specific log component for all logging statements in a file,
you can simply redefine ql_component to match this log component, e.g. by adding
a #undef #define sequence at the top of the file, e.g.

    #undef ql_component
    #define ql_component lcl_cFileLevelComponent

If you want to use a specific log component at a specific location in your code,
you can use the _c variants of the macros which take the log component as the
first argument, e.g.

    qlinfo_c(lcl_cMain, @"initialized");
    qlerror_c(lcl_cMain, @"file '%@' does not exist", file);
    qltrace_c(lcl_cMain);


## Related Repositories

The following Git repositories are related to this repository:

* [http://github.com/aharren/LibComponentLogging-Core](http://github.com/aharren/LibComponentLogging-Core):
  Core files of LibComponentLogging.


## Copyright and License

Copyright (c) 2009-2011 Arne Harren <ah@0xc0.de>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

