#!/opt/MacPatch/Server/env/server/bin/python3

'''
	Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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
'''

'''
	Script: MPInventory.py
	Version: 1.8
	History:

	1.7.1:  Base
	1.7.2:  Updated to support new dotfile config
	1.8:    Migrated to PyMYSQL from MySQL Connector
			MPMySQL class replaced by MPDB class
			Updated to use new DB Config class for config data
			Fixed logging bug when Multiprocessing was implemented
'''

import logging
import logging.handlers
import argparse
import sys
import os
import time
import glob
import json
from datetime import datetime, timedelta
from uuid import UUID
import shutil
import json
import os.path
import traceback
import socket

from dotenv import load_dotenv
from multiprocessing import Pool

# New
import pymysql.cursors

gDebug = False
gKeepFiles = False

# Define logging for global use
MP_SRV_BASE	= "/opt/MacPatch/Server"
MP_FLASK_FILE	= MP_SRV_BASE+"/apps/.mpglobal"
invFilesDir	= MP_SRV_BASE+"/InvData/files"
confFile	= MP_SRV_BASE+"/etc/siteconfig.json"
# Logging
logName		= "MPInventory"
logFile		= MP_SRV_BASE+"/logs/MPInventory.log"
logLevel	= logging.INFO
logFileHandler	= logging.handlers.RotatingFileHandler(logFile, maxBytes=100 << 20, backupCount=10)
logFormatter	= '[%(asctime)s][%(levelname)s] --- %(message)s'
logEchoStdOut	= False
logger		= None

# --------------------------------------------
# Logging Helpers for multiprocessing
# --------------------------------------------

"""
	Global Funtion for setting up logging
	args: level = Used for passing global variable of log level to a multiprocessing task
	args: echo = Used for passing global variable of echo StdOut to a multiprocessing task
"""
def MPLogger(level=None, echo=None):
	_logHandlers = []	
	_logger = logging.getLogger()
	# Change Variables for MP
	_logLevel = logLevel
	if level is not None:
		_logLevel = level
	
	_echo = logEchoStdOut
	if echo is not None:
		_echo = echo

	_fileHandler = logFileHandler
	_fileHandler.setLevel(_logLevel)
	_logHandlers.append(_fileHandler)

	if _echo:
		_streamHandler = logging.StreamHandler(sys.stdout)
		_streamHandler.setLevel(logLevel)
		_logHandlers.append(_streamHandler)

	logging.basicConfig(
		level=logLevel,
		handlers=_logHandlers,
		format=logFormatter,
		force=True
	)

	return _logger

"""
	Used with multiprocessing.Pool() to pass in global variables needed
	for logging in a multiprocessing task
"""
def init_worker(level, echo):
	global shared_logEchoStdOut
	global shared_logLevel
	shared_logEchoStdOut = echo
	shared_logLevel = level

# Init the Main logging logger
logger = MPLogger()

# --------------------------------------------
# Define Model
# --------------------------------------------
class DBConfig:
	
	user = 'dbuser'
	password = 'password'
	host = 'localhost'
	port = 3306
	database = 'MacPatchDB3'
	charset = 'utf8mb4'
	cursorclass = pymysql.cursors.DictCursor
	autocommit = False
	
	# Old config for mysql.connector
	#raise_on_warnings = True
	#buffered = True

	def __setitem__(self, key, value):
		setattr(self, key, value)

	def __getitem__(self, key):
		return getattr(self, key)

	def asDict(self):
		# Old config for mysql.connector
		#'raise_on_warnings': self.raise_on_warnings,
		#'buffered': self.buffered,
		myConfig = {
			'user': self.user,
			'password': self.password,
			'host': self.host,
			'port': self.port,
			'database': self.database,
			'charset': self.charset,
			'cursorclass': self.cursorclass,
			'autocommit': self.autocommit
		}
		return myConfig

# --------------------------------------------
# Define Classes
# --------------------------------------------

# The validation and database work is shared with the API, see inventory_core.py. It's a
# plain module (standard library only), so it is loaded from its folder, not as part of
# the mpapi package.
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'apps', 'api', 'mpapi', 'shared'))
import inventory_core as core


class DBSession:
	"""inventory_core.Session on a pymysql connection. One connection per inventory file."""

	def __init__(self, databaseConfig: DBConfig):
		self.connection = pymysql.connect(
			host=databaseConfig.host,
			user=databaseConfig.user,
			passwd=databaseConfig.password,
			db=databaseConfig.database,
			port=int(databaseConfig.port),
			charset=databaseConfig.charset,
			cursorclass=pymysql.cursors.Cursor,
			autocommit=False,
			connect_timeout=5
		)

	def execute(self, sql, params=None):
		with self.connection.cursor() as cur:
			return cur.execute(sql, params)

	def executemany(self, sql, rows):
		with self.connection.cursor() as cur:
			cur.executemany(sql, rows)

	def fetchall(self, sql, params=None):
		with self.connection.cursor() as cur:
			cur.execute(sql, params)
			return list(cur.fetchall())

	def commit(self):
		self.connection.commit()

	def rollback(self):
		self.connection.rollback()

	def close(self):
		self.connection.close()


class StatsConfig:
	"""
	Inventory statistics settings, from the environment (the .mpglobal file):
		INVENTORY_STATS_ENABLED                 yes (default) or no
		INVENTORY_STATS_RETENTION_DAYS          days to keep a row per file loaded, default 120, 0 = forever
		INVENTORY_STATS_ROLLUP_RETENTION_DAYS   days to keep the daily roll-up, default 120, 0 = forever
	"""

	def __init__(self, enabled=True, days=120, rollupDays=120):
		self.enabled = enabled
		self.days = days
		self.rollupDays = rollupDays

	@classmethod
	def fromEnv(cls):
		def number(name, default):
			try:
				return max(0, int(os.environ.get(name, default)))
			except ValueError:
				logger.error(f"{name} is not a number, using {default}.")
				return default

		enabled = os.environ.get('INVENTORY_STATS_ENABLED', 'yes').strip().lower() not in ('no', 'false', '0', 'off')
		return cls(enabled,
				   number('INVENTORY_STATS_RETENTION_DAYS', 120),
				   number('INVENTORY_STATS_ROLLUP_RETENTION_DAYS', 120))


class InvStats:
	"""
	Stores what happened to each inventory file: a row in mp_inv_stats and the day's counters
	in mp_inv_stats_daily. Statistics never get in the way of loading inventory, a problem
	storing them is logged and nothing more.
	"""

	PRUNE_CHUNK = 10000

	def __init__(self, dbConfig: DBConfig, statsConfig: StatsConfig):
		self.dbConfig = dbConfig
		self.config = statsConfig
		self.server = socket.gethostname()

	def _connect(self):
		return pymysql.connect(
			host=self.dbConfig.host, user=self.dbConfig.user, passwd=self.dbConfig.password,
			db=self.dbConfig.database, port=int(self.dbConfig.port), charset=self.dbConfig.charset,
			cursorclass=pymysql.cursors.Cursor, autocommit=False, connect_timeout=5)

	def record(self, st):
		if not self.config.enabled:
			return

		connection = None
		try:
			connection = self._connect()
			with connection.cursor() as cur:
				cur.execute(
					"INSERT INTO mp_inv_stats (started, cuuid, inv_table, result, error_no, error_stage, error_msg, "
					"file_name, file_bytes, rows_received, rows_inserted, rows_updated, rows_purged, table_created, "
					"queued_ms, schema_ms, load_ms, total_ms, mp_server) "
					"VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
					(st['started'], st['cuuid'], st['inv_table'], st['result'], st['error_no'], st['error_stage'],
					 st['error_msg'], st['file_name'], st['file_bytes'], st['rows_received'], st['rows_inserted'],
					 st['rows_updated'], st['rows_purged'], st['table_created'], st['queued_ms'], st['schema_ms'],
					 st['load_ms'], st['total_ms'], self.server))
				cur.execute(
					"INSERT INTO mp_inv_stats_daily (day, inv_table, result, loads, rows_inserted, rows_updated, "
					"rows_purged, file_bytes, queued_ms_total, queued_ms_max, load_ms_total, load_ms_max) "
					"VALUES (%s, %s, %s, 1, %s, %s, %s, %s, %s, %s, %s, %s) "
					"ON DUPLICATE KEY UPDATE loads = loads + 1, "
					"rows_inserted = rows_inserted + VALUES(rows_inserted), rows_updated = rows_updated + VALUES(rows_updated), "
					"rows_purged = rows_purged + VALUES(rows_purged), file_bytes = file_bytes + VALUES(file_bytes), "
					"queued_ms_total = queued_ms_total + VALUES(queued_ms_total), "
					"queued_ms_max = GREATEST(queued_ms_max, VALUES(queued_ms_max)), "
					"load_ms_total = load_ms_total + VALUES(load_ms_total), "
					"load_ms_max = GREATEST(load_ms_max, VALUES(load_ms_max))",
					(st['started'].date(), st['inv_table'], st['result'], st['rows_inserted'], st['rows_updated'],
					 st['rows_purged'], st['file_bytes'], st['queued_ms'], st['queued_ms'], st['load_ms'], st['load_ms']))
			connection.commit()

		except Exception as e:
			logger.error(f"[InvStats][record] Unable to store statistics for {st.get('file_name')}: {e}")
		finally:
			if connection:
				connection.close()

	def prune(self):
		"""Delete statistics older than the retention settings, in chunks so tables are never locked for long."""
		if not self.config.enabled:
			return

		connection = None
		try:
			connection = self._connect()
			for table, column, days, cutoff in (
					('mp_inv_stats', 'started', self.config.days, datetime.now() - timedelta(days=self.config.days)),
					('mp_inv_stats_daily', 'day', self.config.rollupDays,
					 (datetime.now() - timedelta(days=self.config.rollupDays)).date())):
				if days <= 0:
					continue
				removed = 0
				while True:
					with connection.cursor() as cur:
						count = cur.execute(f"DELETE FROM {table} WHERE {column} < %s LIMIT {self.PRUNE_CHUNK}", (cutoff,))
					connection.commit()
					removed += count
					if count < self.PRUNE_CHUNK:
						break
				if removed:
					logger.info(f"[InvStats][prune] Removed {removed} row(s) older than {days} days from {table}.")

		except Exception as e:
			logger.error(f"[InvStats][prune] {e}")
		finally:
			if connection:
				connection.close()


class DataMgr:
	"""
	Loads one .mpd inventory file (see inventory_core.py for the format and rules). After
	parseInvData(), `stats` describes what happened, why it failed if it did.
	"""

	def __init__(self, dbConfig: DBConfig, aFile):
		self.dbConfig = dbConfig
		self.file = aFile
		self.invData = None
		self.loadError = None
		self.stats = {'started': datetime.now(), 'cuuid': '', 'inv_table': '', 'result': 'unknown',
					  'error_no': None, 'error_stage': None, 'error_msg': None,
					  'file_name': os.path.basename(aFile)[:255], 'file_bytes': 0, 'rows_received': 0,
					  'rows_inserted': 0, 'rows_updated': 0, 'rows_purged': 0, 'table_created': 0,
					  'queued_ms': 0, 'schema_ms': 0, 'load_ms': 0, 'total_ms': 0}

		try:
			self.stats['file_bytes'] = os.path.getsize(aFile)
			# The API renames the finished file into place, so its age is the time spent waiting
			self.stats['queued_ms'] = int(max(0, time.time() - os.path.getmtime(aFile)) * 1000)
			with open(self.file) as json_data:
				self.invData = json.load(json_data)
		except Exception as e:
			# Reported by parseInvData, so it gets recorded and the file moved to the errors folder
			self.loadError = e
			logger.error(f"[DataMgr][init]: {e}")
			return

		key = self.invData.get('key') if isinstance(self.invData, dict) else None
		self.stats['cuuid'] = key[:50] if isinstance(key, str) else ''
		logger.info("Processing data for client id %s." % key)
		logger.info("Processing file %s." % self.file)

	def parseInvData(self):
		"""Store the file's data. Returns True on success; either way `stats` is filled in."""
		st = self.stats
		started = time.monotonic()
		stage = 'read'
		try:
			if self.loadError is not None:
				raise self.loadError

			stage = 'validate'
			plan = core.parse(self.invData)
			st['inv_table'] = plan.table
			st['rows_received'] = len(plan.rows)

			stage = 'connect'
			session = DBSession(self.dbConfig)
			try:
				# The client ID is the file's key, written by the API from the authenticated request
				result = core.process(plan, self.invData.get('key'), session, logger)
			finally:
				session.close()

			st.update(result='ok', rows_inserted=result['inserted'], rows_updated=result['updated'],
					  rows_purged=result['purged'], table_created=int(result['created']),
					  schema_ms=result['schema_ms'], load_ms=result['load_ms'])
			return True

		except Exception as e:
			category, errno = core.classify_error(e)
			st.update(result=category, error_no=errno, error_stage=getattr(e, 'inv_stage', stage),
					  error_msg=str(e)[:2000])
			# Best effort details when the payload was readable but not valid
			if isinstance(self.invData, dict):
				table = self.invData.get('table')
				st['inv_table'] = table[:255] if isinstance(table, str) else ''
				rows = self.invData.get('rows')
				st['rows_received'] = len(rows) if isinstance(rows, list) else 0
			logger.error(f"[DataMgr][parseInvData] {self.file}: {category} at {st['error_stage']}"
						 f"{' (MySQL error %d)' % errno if errno else ''}: {e}")
			return False

		finally:
			st['total_ms'] = int((time.monotonic() - started) * 1000)

# --------------------------------------------
# Main Class
# --------------------------------------------

class MPInventory:

	def __init__(self, dbConfig: DBConfig, filesBaseDir, keepProcessedFiles=False, poolCount=2, statsConfig=None):
		self.dbConfig = dbConfig
		self.statsConfig = statsConfig or StatsConfig(enabled=False)
		self.lastPrune = 0
		self.poolCount = poolCount
		self.filesBaseDir = filesBaseDir
		self.files = ''
		self.keepProcessedFiles = keepProcessedFiles

	def getFiles(self):
		if os.path.exists(self.filesBaseDir) and os.path.isdir(self.filesBaseDir):
			self.files = glob.glob(self.filesBaseDir + '/*.mpd')
			logger.debug("Files: found in " + self.filesBaseDir)
		else:
			logger.error("Error: " + self.filesBaseDir + " does not exist.")

	def moveErrorFile(self,file):
		parDir = os.path.abspath(os.path.join(self.filesBaseDir, os.pardir))
		errDir = parDir + "/Errors"
		head, tail = os.path.split(file)
		errFile = errDir + "/" + tail
		invFile = self.filesBaseDir + "/" + tail

		# Make Errors Dir if Missing
		if os.path.exists(errDir) is False:
			os.makedirs(errDir)

		try:
			# Try to move the error file, if fail remove it
			shutil.move(invFile,errFile)
		except Exception as e:
			logger.error("Error moving file. %s" % str(e))
			os.remove(invFile)

	def moveInvFile(self,file):
		parDir = os.path.abspath(os.path.join(self.filesBaseDir, os.pardir))
		proDir = parDir + "/Processed"
		head, tail = os.path.split(file)
		proFile = proDir + "/" + tail
		invFile = self.filesBaseDir + "/" + tail

		# Make Processed Dir if Missing
		if os.path.exists(proDir) is False:
			os.makedirs(proDir)

		try:
			# Try to move the error file, if fail remove it
			shutil.move(invFile,proFile)
		except Exception as e:
			logger.error("Error moving file. %s" % str(e))
			os.remove(invFile)

	def processFiles(self):
		self.getFiles()
		logger.info("***************** START (processFiles) ***************** ")
		logger.info("%d file(s) found to process."% len(self.files))

		p = Pool(processes=self.poolCount,initializer=init_worker, initargs=(logLevel,logEchoStdOut,))
		p.map(self.processFile, self.files)
		p.close()
		logger.info("***************** DONE (processFiles)  ***************** ")

	def processFileReal(self, file):
		if os.path.exists(file):
			# Process the inv File
			try:
				dMgr = DataMgr(self.dbConfig, file)
				if dMgr.parseInvData() is True:
					if gKeepFiles is True:
						self.moveInvFile(file)
					else:
						os.remove(file)
				else:
					self.moveErrorFile(file)

			except Exception as e:
				logger.error('[processFile]: Error reading {0}:\n{1}'.format(file,e))
				self.moveErrorFile(file)    

	def processFile(self, file):
		# Logger has to be re-defined since this function is called as a
		# multiprocessing task
		logger = MPLogger(level=shared_logLevel,echo=shared_logEchoStdOut)
		try:
			if os.path.exists(file):
				# Process the inv File
				dMgr = DataMgr(self.dbConfig, file)
				success = dMgr.parseInvData()
				InvStats(self.dbConfig, self.statsConfig).record(dMgr.stats)
				if success:
					if gKeepFiles is True:
						self.moveInvFile(file)
					else:
						os.remove(file)
				else:
					self.moveErrorFile(file)
		except Exception as e:
			logging.error(f"[processFile]: {file}")
			logging.error(f"[processFile]: {e}")
			self.moveErrorFile(file)

	def pruneStats(self):
		"""Remove statistics past their retention, at most once an hour."""
		if time.time() - self.lastPrune >= 3600:
			self.lastPrune = time.time()
			InvStats(self.dbConfig, self.statsConfig).prune()

	def processFilesOld(self):
		self.getFiles()
		
		logger.info("---------------------------------------------")
		logger.info("%d file(s) found to process."% len(self.files))
		for iFile in self.files:
			if os.path.exists(iFile):
				# Process the inv File
				try:
					dMgr = DataMgr(self.dbConfig, iFile)
					if dMgr.parseInvData() is True:
						if gKeepFiles is True:
							self.moveInvFile(iFile)
						else:
							os.remove(iFile)
					else:
						self.moveErrorFile(iFile)

				except Exception as e:
					logger.error('Error reading {0}:\n{1}'.format(iFile,e))
					self.moveErrorFile(iFile)

# --------------------------------------------
# Main Class
# --------------------------------------------
class App():

	def __init__(self):
		self.stdin_path = '/dev/null'
		self.stdout_path = '/dev/tty'
		self.stderr_path = '/dev/tty'

	def run(self):
		filepath = '/tmp/mydaemon/currenttime.txt'
		dirpath = os.path.dirname(filepath)

		while True:
			if not os.path.exists(dirpath) or not os.path.isdir(dirpath):
				os.makedirs(dirpath)
			f = open(filepath, 'w')
			f.write(datetime.strftime(datetime.now(), '%Y-%m-%d %H:%M:%S'))
			f.close()
			time.sleep(10)

def main():
	global logger
	global logEchoStdOut
	global logLevel

	'''Main command processing'''
	parser = argparse.ArgumentParser(description='Process some args.')
	parser.add_argument('--config', help="Flask Global config file", required=False, default=None)
	parser.add_argument('--debug', help='Set log level to debug', action='store_true')
	parser.add_argument('--files', help="JSON files to process", required=True)
	parser.add_argument('--save', help='Saves JSON files', action='store_true')
	parser.add_argument('--echo', help='Saves JSON files', required=False, action='store_true')
	args = parser.parse_args()

	if args.echo:
		logEchoStdOut = True

	if args.debug:
		logLevel = logging.DEBUG

	# Re-Init the logging with possible config changes
	if args.echo or args.debug:
		logger = MPLogger()

	dbConf = DBConfig()
	# Parse Config
	if args.config:
		if not os.path.exists(MP_FLASK_FILE):
			print("Unable to open " + MP_FLASK_FILE +". File not found.")
			sys.exit(1)
		else:
			load_dotenv(MP_FLASK_FILE, override=True)

			if 'DB_NAME' in os.environ:
				dbConf.database = os.environ.get('DB_NAME')
				#myConfig['database'] = os.environ.get('DB_NAME')
			else:
				raise ValueError("Error, config missing key DB_NAME.")

			if 'DB_HOST' in os.environ:
				dbConf.host = os.environ.get('DB_HOST')
				#myConfig['host'] = os.environ.get('DB_HOST')
			else:
				raise ValueError("Error, config missing key DB_HOST.")

			if 'DB_USER' in os.environ:
				dbConf.user = os.environ.get('DB_USER')
				#myConfig['user'] = os.environ.get('DB_USER')
			else:
				raise ValueError("Error, config missing key DB_USER.")

			if 'DB_PASS' in os.environ:
				dbConf.password = os.environ.get('DB_PASS')
				#myConfig['password'] = os.environ.get('DB_PASS')
			else:
				raise ValueError("Error, config missing key DB_PASS.")
	else:
		if os.path.exists(MP_FLASK_FILE):
			load_dotenv(MP_FLASK_FILE, override=True)

			_configKeys = [('DB_NAME','database'),('DB_HOST','host'),('DB_USER','user'),('DB_PASS','password')]
			for k in _configKeys:
				if k[0] in os.environ:
					dbConf[k[1]] = os.environ.get(k[0])
				else:
					raise ValueError(f"Error, config missing key {k}.")	
		else:
			print("Using default config data.")

	logger.info('# ------------------------------------------------------')
	logger.info('# Starting MPInventory                                  ')
	logger.info('# ------------------------------------------------------')

	# Keep Files
	if args.save:
		gKeepFiles = True
		logger.info('Keep processed files is enabled.')

	if not os.path.exists(args.files):
		print("%s does not exist." % args.files)
		sys.exit(1)

	statsConf = StatsConfig.fromEnv()
	if statsConf.enabled:
		logger.info(f"Statistics are enabled, keeping {statsConf.days or 'all'} day(s) of loads and {statsConf.rollupDays or 'all'} day(s) of daily totals.")
	else:
		logger.info('Statistics are disabled.')

	mpi = MPInventory(dbConfig=dbConf, filesBaseDir=args.files, statsConfig=statsConf)
	while True:
		mpi.processFiles()
		mpi.pruneStats()
		time.sleep(3.0)


if __name__ == '__main__':
	main()