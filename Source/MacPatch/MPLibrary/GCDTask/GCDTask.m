//
//  GCDTask.m
//
//  Author: Darvell Long
//  Copyright (c) 2014 Reliablehosting.com. All rights reserved.
//

#import "GCDTask.h"
#define GCDTASK_BUFFER_MAX 4096

@implementation GCDTask

- (id) init
{
    return [super init];
}

- (void) launchWithOutputBlock: (void (^)(NSData* stdOutData)) stdOut
                 andErrorBlock: (void (^)(NSData* stdErrData)) stdErr
                      onLaunch: (void (^)(void)) launched
                        onExit: (void (^)(int)) exit
{
    executingTask = [[NSTask alloc] init];
 
    /* Set launch path. */
    [executingTask setLaunchPath:[_launchPath stringByStandardizingPath]];
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:[executingTask launchPath]])
    {
        @throw [NSException exceptionWithName:@"GCDTASK_INVALID_EXECUTABLE" reason:@"There is no executable at the path set." userInfo:nil];
    }

    /* Clean then set arguments. */
    for (id arg in _arguments)
    {
        if([arg class] != [NSString class])
        {
            NSMutableArray* cleanedArray = [[NSMutableArray alloc] init];
            /* Clean up required! */
            for (id arg in _arguments)
            {
                [cleanedArray addObject:[NSString stringWithFormat:@"%@",arg]];
            }
            [self setArguments:cleanedArray];
            break;
        }
    }
    
    
    [executingTask setArguments:_arguments];
    if (_environment) {
        [executingTask setEnvironment:_environment];
    }
    
    
    /* Setup pipes */
    stdinPipe = [NSPipe pipe];
    stdoutPipe = [NSPipe pipe];
    stderrPipe = [NSPipe pipe];
    
    [executingTask setStandardInput:stdinPipe];
    [executingTask setStandardOutput:stdoutPipe];
    [executingTask setStandardError:stderrPipe];
    
    /* Set current directory, just pass on our actual CWD. */
    /* TODO: Potentially make this changeable? Surely there's probably a nicer way to get the CWD too. */
    [executingTask setCurrentDirectoryPath:[[[NSFileManager alloc] init] currentDirectoryPath]];

    
    /* Ensure the pipes are non-blocking so GCD can read them correctly. */
    fcntl([stdoutPipe fileHandleForReading].fileDescriptor, F_SETFL, O_NONBLOCK);
    fcntl([stderrPipe fileHandleForReading].fileDescriptor, F_SETFL, O_NONBLOCK);
    
    /* Setup a dispatch source for both descriptors. */
    _stdoutSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,[stdoutPipe fileHandleForReading].fileDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    _stderrSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,[stderrPipe fileHandleForReading].fileDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    
    //_stdoutSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,[stdoutPipe fileHandleForReading].fileDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    //_stderrSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,[stderrPipe fileHandleForReading].fileDescriptor, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    
    /* Set stdout source event handler to read data and send it out. */
    dispatch_source_set_event_handler(_stdoutSource, ^ {
        void* buffer = malloc(GCDTASK_BUFFER_MAX);
        ssize_t bytesRead;
        
        do
        {
            errno = 0;
			bytesRead = read([self->stdoutPipe fileHandleForReading].fileDescriptor, buffer, GCDTASK_BUFFER_MAX);
        } while(bytesRead == -1 && errno == EINTR);
        
        if(bytesRead > 0)
        {
            // Create before dispatch to prevent a race condition.
            NSData* dataToPass = [NSData dataWithBytes:buffer length:bytesRead];
            dispatch_async(dispatch_get_main_queue(), ^{
				if(!self->_hasExecuted)
                {
                    if(launched)
                        launched();
					self->_hasExecuted = TRUE;
                }
                if(stdOut)
                {
                    stdOut(dataToPass);
                }
            });
        }
        
        if(errno != 0 && bytesRead <= 0)
        {
			dispatch_source_cancel(self->_stdoutSource);
            dispatch_async(dispatch_get_main_queue(), ^{
                if(exit)
					exit([self->executingTask terminationStatus]);
            });
        }

        
        free(buffer);
    });
    
    /* Same thing for stderr. */
    dispatch_source_set_event_handler(_stderrSource, ^ {
        void* buffer = malloc(GCDTASK_BUFFER_MAX);
        ssize_t bytesRead;
        
        do
        {
            errno = 0;
			bytesRead = read([self->stderrPipe fileHandleForReading].fileDescriptor, buffer, GCDTASK_BUFFER_MAX);
        } while(bytesRead == -1 && errno == EINTR);
        
        if(bytesRead > 0)
        {
            NSData* dataToPass = [NSData dataWithBytes:buffer length:bytesRead];
            dispatch_async(dispatch_get_main_queue(), ^{
                if(stdErr)
                {
                    stdErr(dataToPass);
                }
            });
        }
        
        if(errno != 0 && bytesRead <= 0)
        {
			dispatch_source_cancel(self->_stderrSource);
        }
        
        free(buffer);
    });

    
    dispatch_resume(_stdoutSource);
    dispatch_resume(_stderrSource);

    __weak typeof(self) weakSelf = self;
    executingTask.terminationHandler = ^(NSTask* task)
    {
        __strong typeof(self) strongSelf = weakSelf;
        dispatch_source_cancel(weakSelf.stdoutSource);
        dispatch_source_cancel(weakSelf.stderrSource);
        if(exit)
            exit([strongSelf->executingTask terminationStatus]);
    };

    [executingTask launch];
}

- (BOOL) WriteStringToStandardInput: (NSString*) input
{
    return [self WriteDataToStandardInput:[input dataUsingEncoding:NSUTF8StringEncoding]];
}


/* Currently synchronous. TODO: Async fun! */
- (BOOL) WriteDataToStandardInput: (NSData*) input
{
    if (!stdinPipe || stdinPipe == nil)
    {
        GCDDebug(@"Standard input pipe does not exist.");
        return NO;
    }
    
    [[stdinPipe fileHandleForWriting] writeData:input];
    return YES;
}

/* If you don't like setting your own array. You really should never have a use for this. */
- (void) AddArgument: (NSString*) argument
{
    NSMutableArray* temp = [NSMutableArray arrayWithArray:_arguments];
    [temp addObject:argument];
    [self setArguments:temp];
}

- (void) RequestTermination
{
    /* Ask nicely for SIGINT, then SIGTERM. */
    [executingTask interrupt];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void)
    {
		[self->executingTask terminate];
    });
}


@end
