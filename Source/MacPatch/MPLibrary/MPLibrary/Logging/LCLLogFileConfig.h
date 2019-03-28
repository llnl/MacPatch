//
// configuration of LCLLogFile
//


// Rename the LCLLogFile class by adding your application/framework's unique
// prefix in order to avoid duplicate symbols in the global class namespace.
#ifndef LCLLogFile
#define LCLLogFile                                                             \
    MPFrameworkLCLLogFile
#endif

// Tell LCLLogFile the path of the log file.
#define _LCLLogFile_LogFilePath /* (NSString *) */                             \
    [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Empty.log"]

// Tell LCLLogFile whether it should append to an existing log file on startup,
// instead of creating a new log file.
#define _LCLLogFile_AppendToExistingLogFile /* (BOOL) */                       \
    YES

// Tell LCLLogFile the maximum size of a log file in bytes.
#define _LCLLogFile_MaxLogFileSizeInBytes /* (size_t) */                       \
    10 * 1024 * 1024

// Tell LCLLogFile whether it should mirror the log messages to stderr.
#define _LCLLogFile_MirrorMessagesToStdErr /* (BOOL) */                        \
    NO

// Tell LCLLogFile the maximum size of a log message in characters.
#define _LCLLogFile_MaxMessageSizeInCharacters /* NSUInteger */                \
    0

// Tell LCLLogFile whether it should escape ('\\' and) '\n' line feed characters
// in log messages
#define _LCLLogFile_EscapeLineFeeds /* BOOL */                                 \
    NO

// Tell LCLLogFile whether it should show file names.
#define _LCLLogFile_ShowFileNames /* (BOOL) */                                 \
    YES

// Tell LCLLogFile whether it should show line numbers.
#define _LCLLogFile_ShowLineNumbers /* (BOOL) */                               \
    YES

// Tell LCLLogFile whether it should show function names.
#define _LCLLogFile_ShowFunctionNames /* (BOOL) */                             \
    NO

