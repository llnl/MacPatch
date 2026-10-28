import multiprocessing
import gevent.monkey
gevent.monkey.patch_all()

# Sample Gunicorn configuration file.

#
# Server socket
#
#   bind - The socket to bind.
#
#       A string of the form: 'HOST', 'HOST:PORT', 'unix:PATH'.
#       An IP is a valid HOST.
#
#   backlog - The number of pending connections. This refers
#       to the number of clients that can be waiting to be
#       served. Exceeding this number results in the client
#       getting an error when attempting to connect. It should
#       only affect servers under significant load.
#
#       Must be a positive integer. Generally set in the 64-2048
#       range.
#

bind = '127.0.0.1:3602'
backlog = 2048  # Console has fewer concurrent users than API, 2048 is sufficient

#
# Worker processes
#
#   workers - The number of worker processes that this server
#       should keep alive for handling requests.
#
#       For gevent workers: 2 x $(NUM_CORES) is recommended
#       Console has fewer concurrent users than API, but still benefits from gevent
#
#   worker_class - Using 'gevent' for handling multiple admin sessions efficiently
#       gevent uses greenlets (cooperative threading) for low memory overhead
#       Good for web UI with multiple admin users browsing simultaneously
#
#   worker_connections - For gevent worker class, this limits the
#       maximum number of simultaneous clients per worker process
#
#       Console: 500-1000 is sufficient (fewer concurrent users than API)
#       Admins typically have longer-lived sessions but fewer total connections
#
#   timeout - Worker timeout for long-running requests
#       Set high enough for admin operations like bulk updates, reports
#       For gevent, this just ensures worker is responsive
#
#   keepalive - Seconds to wait for next request on Keep-Alive connection
#       Enabling keepalive improves admin UI responsiveness
#       Reduces connection overhead for browser making multiple requests
#

# Workers: 2x CPU cores for optimal gevent performance
workers = multiprocessing.cpu_count() * 2

# Moderate concurrency: each worker handles up to 1000 concurrent admin sessions
worker_connections = 1000  # Increased from 100 for better admin UI performance

worker_class = 'gevent'
timeout = 300  # 5 minutes for long-running admin operations
keepalive = 2  # Enable HTTP keepalive for better browser performance
preload_app = True  # Preload application code before forking workers

#
#   spew - Install a trace function that spews every line of Python
#       that is executed when running the server. This is the
#       nuclear option.
#
#       True or False
#

spew = False

#
# Server mechanics
#
#   daemon - Detach the main Gunicorn process from the controlling
#       terminal with a standard fork/fork sequence.
#
#       True or False
#
#   raw_env - Pass environment variables to the execution environment.
#
#   pidfile - The path to a pid file to write
#
#       A path string or None to not write a pid file.
#
#   user - Switch worker processes to run as this user.
#
#       A valid user id (as an integer) or the name of a user that
#       can be retrieved with a call to pwd.getpwnam(value) or None
#       to not change the worker process user.
#
#   group - Switch worker process to run as this group.
#
#       A valid group id (as an integer) or the name of a user that
#       can be retrieved with a call to pwd.getgrnam(value) or None
#       to change the worker processes group.
#
#   umask - A mask for file permissions written by Gunicorn. Note that
#       this affects unix socket permissions.
#
#       A valid value for the os.umask(mode) call or a string
#       compatible with int(value, 0) (0 means Python guesses
#       the base, so values like "0", "0xFF", "0022" are valid
#       for decimal, hex, and octal representations)
#
#   tmp_upload_dir - A directory to store temporary request data when
#       requests are read. This will most likely be disappearing soon.
#
#       A path to a directory where the process owner can write. Or
#       None to signal that Python should choose one on its own.
#

daemon = False
raw_env = [
    'DJANGO_SECRET_KEY=something',
    'SPAM=eggs',
]
pidfile = None
umask = 0
user = 'www-data'
group = 'www-data'
tmp_upload_dir = None

#
#   Logging
#
#   logfile - The path to a log file to write to.
#
#       A path string. "-" means log to stdout.
#
#   loglevel - The granularity of log output
#
#       A string of "debug", "info", "warning", "error", "critical"
#  https://ios-sign-dev.llnl.gov/static/apps/500e5603-4ba2-456d-aabc-40ad45170471/signed/Eco.ipa.zip
#  https://ios-sign-dev.llnl.gov/static/apps/d6f187d9-59a2-46a5-a63f-a8dad386aa91/signed/NEOMobileCheckLists.ipa.zip

#ccesslog = '-'
#errorlog = '-'
accesslog = '/opt/MacPatch/Server/logs/gMPConsole_access.log'
errorlog = '/opt/MacPatch/Server/logs/gMPConsole_error.log'
loglevel = 'info'

access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'

#
# Process naming
#
#   proc_name - A base to use with setproctitle to change the way
#       that Gunicorn processes are reported in the system process
#       table. This affects things like 'ps' and 'top'. If you're
#       going to be running more than one instance of Gunicorn you'll
#       probably want to set a name to tell them apart. This requires
#       that you install the setproctitle module.
#
#       A string or None to choose a default of something like 'gunicorn'.
#

proc_name = None

#
# Server hooks
#
#   post_fork - Called just after a worker has been forked.
#
#       A callable that takes a server and worker instance
#       as arguments.
#
#   pre_fork - Called just prior to forking the worker subprocess.
#
#       A callable that accepts the same arguments as after_fork
#
#   pre_exec - Called just prior to forking off a secondary
#       master process during things like config reloading.
#
#       A callable that takes a server instance as the sole argument.
#

def post_fork(server, worker):
    server.log.info("Worker spawned (pid: %s)", worker.pid)

def pre_fork(server, worker):
    pass

def pre_exec(server):
    server.log.info("Forked child, re-executing.")

def when_ready(server):
    # Configure custom log format for gunicorn error log
    import logging.handlers

    # Remove existing handlers
    for handler in server.log.error_log.handlers[:]:
        server.log.error_log.removeHandler(handler)

    # Add our custom formatted handler
    handler = logging.handlers.RotatingFileHandler(
        '/opt/MacPatch/Server/logs/gMPConsole_error.log',
        maxBytes=10485760,
        backupCount=10
    )

    class MacPatchFormatter(logging.Formatter):
        def format(self, record):
            formatted_time = self.formatTime(record, '%Y-%m-%d %H:%M:%S')
            level_map = {'DEBUG': 'DBG', 'INFO': 'INF', 'WARNING': 'WRN', 'ERROR': 'ERR', 'CRITICAL': 'CRT'}
            level_short = level_map.get(record.levelname, 'INF')
            return f"{formatted_time},{int(record.msecs):03d} [gunicorn][{level_short}] --- {record.getMessage()}"

    handler.setFormatter(MacPatchFormatter())
    server.log.error_log.addHandler(handler)
    server.log.info("Server is ready. Spawning workers")

def worker_int(worker):
    worker.log.info("worker received INT or QUIT signal")

    ## get traceback info
    import threading, sys, traceback
    id2name = {th.ident: th.name for th in threading.enumerate()}
    code = []
    for threadId, stack in sys._current_frames().items():
        code.append("\n# Thread: %s(%d)" % (id2name.get(threadId,""),
            threadId))
        for filename, lineno, name, line in traceback.extract_stack(stack):
            code.append('File: "%s", line %d, in %s' % (filename,
                lineno, name))
            if line:
                code.append("  %s" % (line.strip()))
    worker.log.debug("\n".join(code))

def worker_abort(worker):
    worker.log.info("worker received SIGABRT signal")