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
from datetime import datetime
from uuid import UUID
import shutil
import json
import os.path
import traceback

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

class DBField:

	name = ''
	dataType = 'varchar'
	length = 255
	dataTypeExt = ''
	defaultValue = ''
	autoIncrement = False
	primaryKey = False
	allowNull = True

	def __init__(self):
		return

	def fieldDescription(self):
		_field = {
			'name': DBField.name,
			'dataType': DBField.dataType,
			'length': DBField.length,
			'dataTypeExt': DBField.dataTypeExt,
			'defaultValue': DBField.defaultValue,
			'autoIncrement': DBField.autoIncrement,
			'primaryKey': DBField.primaryKey,
			'allowNull': DBField.allowNull
		}
		return _field

	def getFieldForName(self,name,field):
		if name == "rid":
			return self.getDefaultRID()

		if name == "cuuid":
			return self.getDefaultCUUID()

		if name == "mdate":
			return self.getDefaultMDATE()
		else:
			return field

	def getDefaultRID(self):
		_field = self.fieldDescription()
		_field['name'] = "rid"
		_field['dataType'] = "bigint"
		_field['length'] = 20
		_field['primaryKey'] = True
		_field['autoIncrement'] = True
		_field['allowNull'] = False
		return _field

	def getDefaultCUUID(self):
		_field = self.fieldDescription()
		_field['name'] = "cuuid"
		_field['dataType'] = "varchar"
		_field['length'] = 50
		_field['allowNull'] = False
		return _field

	def getDefaultMDATE(self):
		_field = self.fieldDescription()
		_field['name'] = "mdate"
		_field['dataType'] = "datetime"
		_field['length'] = 0
		return _field

class DB(object):
	
	def __init__(self, databaseConfig: DBConfig):
		self.dbConfig = databaseConfig
		self.connection = None

	def open_connection(self):
		"""Connect to MySQL."""
		try:
			if self.connection is None:
				self.connection = pymysql.connect(
					host=self.dbConfig.host, 
					user=self.dbConfig.user, 
					passwd=self.dbConfig.password, 
					db=self.dbConfig.database,
					port=int(self.dbConfig.port), 
					charset=self.dbConfig.charset,
					cursorclass=self.dbConfig.cursorclass,
					connect_timeout=5
				)
		except pymysql.MySQLError as e:
			print(f"ERROR: {e}")
			return {}
		#finally:
			#print('Connection opened successfully.')

	def query(self, query, data=None, insertMany=False):
		"""Run the SQL query."""
		_rollbackOnError = False
		if any(x in query for x in ['INSERT', 'CREATE', 'DELETE', 'TRUNCATE', 'UPDATE']):
			_rollbackOnError = True

		try:
			self.open_connection()
			with self.connection.cursor() as cur:
				if any(x in query for x in ['SELECT', 'SHOW']):
					records = []
					cur.execute(query)
					result = cur.fetchall()
					for row in result:
						records.append(row)
					
					cur.close()
					return records
				
				elif "INSERT INTO" in query:
					if data is not None:
						cur.execute(query, data)
					else:
						cur.execute(query)
					
					self.connection.commit()
					if insertMany == False:
						result = cur.lastrowid
					else:
						result = {}

					cur.close()
					return result

				else:
					result = cur.execute(query)
					self.connection.commit()
					affected = f"{cur.rowcount} rows affected."
					cur.close()
					return affected

		except pymysql.MySQLError as e:
			print(f"ERROR: {e}")
			if _rollbackOnError == True:
				self.connection.rollback()
				self.connection.close()
				self.connection = None
			return None

		finally:
			if self.connection:
				self.connection.close()
				self.connection = None
		
	def insert(self, query, data):
		return self.query(query=query,data=data)

	# New Function
	def insertMany(self, query, values):
		"""Run the SQL query."""
		_rollbackOnError = True

		try:
			self.open_connection()
			with self.connection.cursor() as cur:
				cur.executemany(query, values)
				self.connection.commit()
				cur.close()
				return True

		except pymysql.MySQLError as e:
			print(f"ERROR: {e}")
			if _rollbackOnError == True:
				self.connection.rollback()
				self.connection.close()
				self.connection = None

			return False

		finally:
			if self.connection:
				self.connection.close()
				self.connection = None

	def insertManyOld(self, table, fields, values):
		_sql = f"INSERT INTO {table} (" + ", ".join(fields) + ") VALUES"
		for v in values:
			_values = []
			for f in fields:
				if isinstance(v[f], str):
					_values.append("\'" + sqlescape(v[f]) +"\'")
				elif isinstance(v[f], bool):
					_values.append(f"{int(v[f])}")
				elif isinstance(v[f], int):
					_values.append(f"{v[f]}")
				else:
					_values.append(v[f])
			_sql = _sql +" (" + ", ".join(_values) + "),"

		_sql = _sql[:-1] + ';'
		print(f"[insertMany][sql]: {_sql}")

		return self.query(query=_sql,data=None,insertMany=True)

class MPDB:
	"""
		MPDB is a Helper Class to get MacPatch database info.
		
		Requires DB Class Object on init

		Updated for PyMySQL, scrpiut ver 1.8 and higher
	"""

	def __init__(self, dbObj: DB):
		# dbConnection is required
		self.db = dbObj

	def tablesFromDataBase(self):
		tables = []
		_qry = "SHOW TABLES;"
		_res = self.db.query(_qry)
		if _res is not None:
			if len(_res) >= 1:
				tables = [list(table.values())[0] for table in _res]

		return tables

	def getInventoryTables(self):
		tables = []
		_qry = "SELECT TABLE_NAME FROM information_schema.tables WHERE table_name like 'mpi_%';"
		_res = self.db.query(_qry)
		if _res is not None:
			if len(_res) >= 1:
				tables = [list(table.values())[0] for table in _res]

		return list(set(tables))
	
	def columnsForTable(self,tableName):
		result = []
		_sql = "SELECT COLUMN_NAME, DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,NUMERIC_PRECISION FROM information_schema.columns WHERE table_schema='" + self.db.dbConfig.database +"' AND table_name = '" + tableName + "'"
		_res = self.db.query(_sql)
		for row in _res:
			tmp = { 'name': '', 'dataType': '', 'length': 0 }
			if 'COLUMN_NAME' in row:
				tmp['name'] = row['COLUMN_NAME']
			else:
				continue
			
			if 'DATA_TYPE' in row:
				tmp['dataType'] = row['DATA_TYPE']
			else:
				continue

			if 'NUMERIC_PRECISION' in row:
				if row['NUMERIC_PRECISION'] is not None:
					tmp['length'] = int(row['NUMERIC_PRECISION'])

			if 'CHARACTER_MAXIMUM_LENGTH' in row:
				if row['CHARACTER_MAXIMUM_LENGTH'] is not None:
					tmp['length'] = int(row['CHARACTER_MAXIMUM_LENGTH'])

			result.append(tmp)

		return result
	
	def tableExists(self,table):
		_tables = self.tablesFromDataBase()
		if table.upper() in list(map(str.upper, self.tables)):
			return True
		else:
			return False

	def columnExists(self, column, table):
		columns = self.columnsForTable(self,table)
		if column.upper() in list(map(str.upper, columns)):
			return True
		else:
			return False

	def colsToAlterOrAdd(self,tableName,cols,fields):
		logger.info("Number of fields to verify: %d" % len(fields))

		for field in fields:
			logger.debug("Verify field %s" % field['name'])
			if self.searchForColNameInFields(field['name'],cols) is False:
				logger.info("Add Field: %s" % field['name'])
				x = self.createColumn(tableName,field)
			else:
				if self.colMatchesDataInField(field['name'],cols,field) is False:
					logger.info("Alter Field: %s" % field['name'])
					x = self.alterColumn(tableName,field)
				else:
					logger.debug("Field Passed: %s" % field['name'])

	def searchForColNameInFields(self, name, fields):
		res = False
		for element in fields:
			if element['name'].lower() == name.lower():
				return True

		return res

	def colMatchesDataInField(self, name, cols, field):
		res = True
		colRes = {}

		for col in cols:
			if col['name'].lower() == name.lower():
				colRes = col
				break

		# Match DataType (Column Type)
		# If db column is text type dont change to varchar
		if colRes['dataType'] != field['dataType']:
			logger.debug("Datatypes do not match for {}. db({}) == inv({})".format(name, colRes['dataType'], field['dataType']))
			if str(colRes['dataType']).lower() == "text" and str(field['dataType']).lower() == "varchar":
				logger.debug("Database is of text which is greater than varchar. This is OK.")
				return True
			else:
				return False
		else:
			logger.debug("Datatypes match for {}. db({}) == inv({})".format(name, colRes['dataType'], field['dataType']))
	
		if int(colRes['length']) >= int(field['length']):
			logger.debug("Length for {} is greater or equal. db({}) >= inv({})".format(name, colRes['length'], field['length']))
		else:
			logger.warning("Column ({}) length {} >= {} did not match.".format(name, colRes['length'], field['length']))
			return False

		return res

	def returnFieldObjectFromField(self,field):
		dfObj = DBField() # Creeat New DBField Obj
		dbField = dfObj.fieldDescription() # Get Default DBField Values
		for key, value in dbField.items():
			if key in field:
				dbField[key] = field[key]

		return dbField

	def createTable(self, tableName, fields):
		_result = False
		_sqlArr = []
		_sqlStrBegin = "CREATE TABLE %s (" % tableName
		_sqlPkeyStr = ""
		for field in fields:
			_field = self.returnFieldObjectFromField(field)
			_sqlStr = ''
			# is RID field
			if field['name'] == 'rid':
				_sqlStr = _sqlStr + "`" + _field['name'] + "`" + " bigint(" + str(_field['length']) + ") UNSIGNED"
			else:
				_sqlStr = _sqlStr + "`" + _field['name'] + "` " + _field['dataType']

			# if it's not date or time field
			if "date" not in field['name'] and "time" not in _field['name']:
				if _field['name'] != 'rid':
					if _field['dataType'] == "text":
						_sqlStr = _sqlStr + " " + _field['dataTypeExt']
					else:
						_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']
			else:
				if _field['dataType'] == "text":
					if "time" in _field['name'] and _field['dataType'] == "text":
						_sqlStr = _sqlStr + " " + _field['dataTypeExt']
					if "date" in _field['name'] and _field['dataType'] == "text":
						_sqlStr = _sqlStr + " " + _field['dataTypeExt']
				else:
					if "time" in _field['name'] and _field['dataType'] == "varchar":
						_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']
					if "date" in _field['name'] and _field['dataType'] == "varchar":
						_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']

			if _field['allowNull'] is False:
				_sqlStr = _sqlStr + " NOT NULL"

			if len(_field['defaultValue']) > 0:
				if _field['name'] != 'rid' and "date" not in field['name']:
					_sqlStr = _sqlStr + " DEFAULT '" + _field['defaultValue'] + "'"

			if _field['autoIncrement']:
				_sqlStr = _sqlStr + " NOT NULL AUTO_INCREMENT"

			if _field['primaryKey']:
				_sqlPkeyStr = " PRIMARY KEY (`"+_field['name']+"`)"

			_sqlArr.append(_sqlStr)

		_sqlArr.append(_sqlPkeyStr)
		_sqlStrExec = _sqlStrBegin + " " + ','.join(_sqlArr) + ");"

		if gDebug:
			logger.debug(_sqlStrExec)
			return True

		#_res = self.db.query(_sqlStrExec.encode('ascii',errors='ignore'))
		_res = self.db.query(_sqlStrExec)
		if _res is not None:
			_result = True

		return _result

	def alterColumn(self,tableName,field):

		_field = self.returnFieldObjectFromField(field)
		_sqlStr = "ALTER TABLE %s" % tableName

		# is RID field
		if _field['name'] == 'rid' or _field['name'] == 'mdate' or _field['name'] == 'cuuid':
			return False
		else:
			_sqlStr = _sqlStr + " CHANGE COLUMN `" + _field['name'] + "` `" + _field['name'] + "` " + _field['dataType']

		# if it's not date or time field
		if "date" not in _field['name'] and "time" not in _field['name']:
			if _field['dataType'] == "text":
				_sqlStr = _sqlStr + " " + _field['dataTypeExt']
			else:
				_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']
		else:
			if _field['dataType'] == "text":
				if "time" in _field['name'] and _field['dataType'] == "text":
					_sqlStr = _sqlStr + " " + _field['dataTypeExt']
				if "date" in _field['name'] and _field['dataType'] == "text":
					_sqlStr = _sqlStr + " " + _field['dataTypeExt']
			else:
				if "time" in _field['name'] and _field['dataType'] == "varchar":
					_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']
				if "date" in _field['name'] and _field['dataType'] == "varchar":
					_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']

		if _field['allowNull'] is False:
			_sqlStr = _sqlStr + " NOT NULL"

		if len(_field['defaultValue']) > 0:
			if _field['name'] != 'rid' and "date" not in _field['name']:
				_sqlStr = _sqlStr + " DEFAULT '" + _field['defaultValue'] + "'"

		_sqlStr = _sqlStr + ";"

		if gDebug:
			logger.debug(_sqlStr)
			return True

		#_res = self.db.query(_sqlStr.encode('ascii',errors='ignore'))
		_res = self.db.query(_sqlStr)
		if _res is not None:
			logger.info("%s was altered sucessfully." % _field['name'])
			return True
		else:
			return False
		
	def createColumn(self, tableName, field):

		_field = self.returnFieldObjectFromField(field)
		_sqlStr = "ALTER TABLE %s" % tableName

		# is RID field
		if _field['name'] == 'rid' or _field['name'] == 'mdate' or _field['name'] == 'cuuid':
			return False
		else:
			_sqlStr = _sqlStr + " ADD COLUMN `" + _field['name'] + "` " + _field['dataType']

		# if it's not date or time field
		if "date" not in _field['name'] and "time" not in _field['name']:
			if _field['dataType'] == "text":
				_sqlStr = _sqlStr + " " + _field['dataTypeExt']
			else:
				_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']
		else:
			if _field['dataType'] == "text":
				if "time" in _field['name'] and _field['dataType'] == "text":
					_sqlStr = _sqlStr + " " + _field['dataTypeExt']
				if "date" in _field['name'] and _field['dataType'] == "text":
					_sqlStr = _sqlStr + " " + _field['dataTypeExt']
			else:
				if "time" in _field['name'] and _field['dataType'] == "varchar":
					_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']
				if "date" in _field['name'] and _field['dataType'] == "varchar":
					_sqlStr = _sqlStr + "(" + str(_field['length']) + ") " + _field['dataTypeExt']

		if _field['allowNull'] is False:
			_sqlStr = _sqlStr + " NOT NULL"

		if len(_field['defaultValue']) > 0:
			if _field['name'] != 'rid' and "date" not in _field['name']:
				_sqlStr = _sqlStr + " DEFAULT '" + _field['defaultValue'] + "'"

		_sqlStr = _sqlStr + ";"

		if gDebug:
			logger.debug(_sqlStr)
			return True
		
		#_res = self.db.query(_sqlStr.encode('ascii',errors='ignore'))
		_res = self.db.query(_sqlStr)
		if _res is not None:
			logger.info("%s was created sucessfully." % _field['name'])
			return True
		else:
			return False

	def removeKeyData(self, tableName, keyVal):
		
		_sqlStr = "Delete from %s where cuuid = '%s'" % (str(tableName), str(keyVal))
		if gDebug:
			logger.debug(_sqlStr)
			return True
		
		logger.info(f"[MPDB][removeKeyData]: Delete cuuid ({keyVal}) from {tableName}")
		_res = self.db.query(_sqlStr)

	def updateRowData(self,tableName,keyVal,mdate,row):
		_sqlArr = []
		_sqlStrPre = "UPDATE %s SET" % tableName
		_sqlStrPst = "WHERE cuuid='%s'" % keyVal
		_sqlStr = ''

		# Add mdate first
		_str = "mdate='%s'" % mdate
		_sqlArr.append(_str)

		# Loop through and add the rest
		for key, value in row.items():
			if key == "rid" or key == "cuuid":
				continue
			else:
				_str = "%s='%s'" % (key, value)
				_sqlArr.append(_str)

		# Build the SQL string
		_sqlStr = "%s %s %s;" %(_sqlStrPre,','.join(_sqlArr),_sqlStrPst)
		if gDebug == True:
			logger.debug(_sqlStr)
			return True
		
		#_res = self.db.query(_sqlStr.encode('ascii',errors='ignore'))
		_res = self.db.query(_sqlStr)
		if _res is not None:
			logger.info(f"[MPDB][updateRowData] row updated in {tableName} for cuuid ({keyVal})")
			return True
		else:
			return False
		
	def insertRowData(self,tableName,keyVal,mdate,row):
		_result = False
		_sqlArrCol = []
		_sqlArrVal = []
		_sqlStrPre = "INSERT INTO %s" % tableName
		_sqlStr = ''

		# Add the client id, mdate to the row
		_row = row
		_row['cuuid'] = keyVal
		_row['mdate'] = mdate

		# Loop through and add the rest
		for key, value in row.items():
			if key == 'rid':
				continue
			else:
				_colStr = "`%s`" % (key)
				_sqlArrCol.append(_colStr)
				_valStr = "'%s'" % (value.replace("'", "\\'"))
				_sqlArrVal.append(_valStr)

		# Build the SQL string
		_sqlStr = "%s (%s) Values (%s);" % (_sqlStrPre, ','.join(_sqlArrCol),','.join(_sqlArrVal))
		if gDebug == True:
			logger.debug(_sqlStr)
			return True
		
		#_res = self.db.query(_sqlStr.encode('ascii',errors='ignore'))
		_res = self.db.query(_sqlStr)
		if _res is not None:
			logger.info(f"Sucessfully inserted rows for client {keyVal} in {tableName}")
			return True
		else:
			return False
		
	# New
	# Replaces insertRowData ( eliminates many small queries to one large one using executemany function)
	def insertRows(self, tableName, fields, rows):
		_clientID = None
		_sqlColumns = []
		_sqlPlaceHolders = []
		_sqlStr = ''

		# Get all of the table column names and make list
		for field in fields:
			# rid is the primary key and is auto incremented, do not include it
			if field['name'].lower() == 'rid':
				continue

			_sqlColumns.append(field['name'])
			_sqlPlaceHolders.append('%s')

		# Create a list of tuples containing the values to be inserted
		_rowDataTupleList = []
		_clientID = rows[0]['cuuid']
		for row in rows:
			# Make sure the data keys and columns match up. else skip the row
			if len(row.keys()) == len(_sqlColumns):
				_rowData = []
				for col in _sqlColumns:
					_rowData.append(row[col])
				
				_rowDataTupleList.append(tuple(_rowData))
			else:
				logger.debug(f"skipping row with data: {row}")

		# Build the SQL String
		logger.info(f"[insertRows]: Inserting {len(_rowDataTupleList)} row(s) in {tableName} for cuuid {_clientID}")
		_sqlStr = f"INSERT INTO {tableName} ({','.join(_sqlColumns)}) VALUES ({','.join(_sqlPlaceHolders)})"
		_res = self.db.insertMany(query=_sqlStr, values=_rowDataTupleList)
		return _res

class DataMgr:

	def __init__(self, dbConfig: DBConfig, aFile):
		self.dbConfig = dbConfig
		self.file = aFile
		try:
			json_data=open(self.file)
			self.invData = json.load(json_data)
			json_data.close()
		except Exception as e:
			logger.error(f"[DataMgr][init]: {e}")
			raise e

		logger.info("Processing data for client id %s." % self.invData['key'])
		logger.info("Processing file %s." % self.file)

	def valid_uuid(self, uuid_string):

		try:
			val = UUID(uuid_string, version=4)
			return True
		except ValueError:
			# If it's a value error, then the string
			# is not a valid hex code for a UUID.
			return False

		return False

	def dictContainsKeyValue(self, dict, key, value):
		for x in dict:
			if x[key] == value:
				return True

		return False

	def parseInvData(self):
		logger.info('parseInvData')
		_result = False
		# Get DB Instance
		_db = DB(databaseConfig=self.dbConfig)
		db = MPDB(_db)

		tableExists = False
		updateData = False
		_table = self.invData['table']
		_fields = self.invData['fields']
		_rows = self.invData['rows']
		_keyVal = self.invData['key']
		_dtObj = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

		# Get AutoField Structure
		if self.invData['autoFields']:
			dfObj = DBField()
			_autoFields = self.invData['autoFields'].split(',')

			for aField in _autoFields:
				if self.dictContainsKeyValue(self.invData['fields'],'name',aField) is False:
					_fields.append(dfObj.getFieldForName(aField,aField))

		# Create Table if needed
		_tables = db.tablesFromDataBase()
		if _table not in _tables:
			logger.info("Create new table %s" % _table)
			if db.createTable(_table,_fields) is False:
				return _result
		else:
			logger.info("Table %s exists." % _table)
			tableExists = True

		# Get columns, verify and alter as nessasary
		cols = db.columnsForTable(_table)
		db.colsToAlterOrAdd(_table,cols,_fields)

		# Purge Data if needed, auto commit if off.
		if tableExists:
			if self.invData['permanentRows'] is False:
				# Remove Client Data Before Insert
				# key = cuuid
				if self.valid_uuid(_keyVal):
					# key is valid
					logger.info("Purging data in %s for %s." % (_table, _keyVal))
					db.removeKeyData(_table,_keyVal)
					if len(_rows) == 0:
						_result = True
						return _result
			else:
				updateData = True

		if updateData:
			# Add or Update Data
			_updates = 0
			_inserts = 0
			logger.info("Adding data to %s for %s." % (_table, _keyVal))
			for row in _rows:
				_row = self.removeUnknownFields(row,_fields)
				if updateData:
					logger.info("Update record")
					if db.updateRowData(_table,_keyVal,_dtObj,_row):
						_updates = _updates + 1
						_result = True
				else:
					#logger.debug("Insert new record")
					_inserts = _inserts + 1
					if db.insertRowData(_table,_keyVal,_dtObj,_row):
						_result = True

			if _updates >= 1:
				logger.info("{} record(s) have been updated.".format(_updates))

			if _inserts >= 1:
				logger.info("{} record(s) have been inserted.".format(_inserts))
		else:
			_result = db.insertRows(tableName=_table, fields=_fields, rows=_rows)

		return _result
	
	# Remove any extra columns/fields that are not in the fields section of the 
	# .mpd inventory file.
	def removeUnknownFields(self, row, fields):
		fieldNames = [d['name'] for d in fields]
		newdict = {k: row[k] for k in fieldNames if k in row}
		return newdict

# --------------------------------------------
# Main Class
# --------------------------------------------

class MPInventory:

	def __init__(self, dbConfig: DBConfig, filesBaseDir, keepProcessedFiles=False, poolCount=2):
		self.dbConfig = dbConfig
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
				if dMgr.parseInvData() is True:
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

	mpi = MPInventory(dbConfig=dbConf, filesBaseDir=args.files)
	while True:
		mpi.processFiles()
		time.sleep(3.0)


if __name__ == '__main__':
	main()