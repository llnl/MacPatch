#!/opt/MacPatch/Server/env/server/bin/python

'''
	Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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
	Version: 1.2.0
'''

import logging
import logging.handlers
import argparse
import sys
import os
import time
import glob
import json
import pprint
import re
import mysql.connector as mydb
from datetime import datetime
from urllib.parse import urlparse
import xml.etree.ElementTree as ET
from uuid import UUID
import shutil
import json
import os.path
import platform


gDebug = False
gKeepFiles = False

# MySQL Global Config
myConfig = {
	'user': 'mpdbadm',
	'password': '',
	'host': 'localhost',
	'port': 3306,
	'database': 'MacPatchDB3',
	'raise_on_warnings': True,
	'buffered': True
}

# Define logging for global use
logger        = logging.getLogger('MPInventory')

MP_SRV_BASE   = "/opt/MacPatch/Server"
MP_FLASK_FILE = MP_SRV_BASE+"/apps/config.cfg"
logFile       = MP_SRV_BASE+"/logs/MPInventory.log"
invFilesDir   = MP_SRV_BASE+"/InvData/files"
confFile      = MP_SRV_BASE+"/etc/siteconfig.json"

# ----------------------------------------------------------------------------
# Read flask config data from file
# ----------------------------------------------------------------------------

def read_config_file(file_path):
	config = {}
	with open(file_path) as f:
		lines = (line.rstrip() for line in f)
		for l in lines:
			if l.rstrip():
				if l.startswith("#") == False:
					config[l.split('=')[0].strip()] = l.split('=')[1].strip().replace("'","")

	return config

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

class MPMySQL:

	def __init__(self,dbConfig):
		try:
			self.dbConfig = dbConfig
			self.db = mydb.connect(**dbConfig)
			self.dbObj = self.db.cursor(buffered=True)
			self.tables = self.tablesFromDataBase()

		except mydb.Error as err:
			if err.errno == mydb.errorcode.ER_ACCESS_DENIED_ERROR:
				logger.error("Something is wrong with your user name or password")
			elif err.errno == mydb.errorcode.ER_BAD_DB_ERROR:
				logger.error("Database does not exists")
			else:
				logger.error(err)
		else:
			self.dbObj.close()
			self.db.close()

	def tablesFromDataBase(self):
		_db = mydb.connect(**myConfig)
		_dbCur = _db.cursor(buffered=True)

		tables = []
		try:
			_dbCur.execute("SHOW TABLES")
			for (table_name,) in _dbCur:
				tables.append(table_name)

		except mydb.Error as e:
			try:
				logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
			except IndexError:
				logger.error("MySQL Error: %s" % str(e))

		_dbCur.close()
		_db.close()
		return tables

	def columnsForTable(self,tableName):

		_db = mydb.connect(**myConfig)
		_dbCur = _db.cursor(buffered=True)

		result = []
		query = "SELECT column_name, DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,NUMERIC_PRECISION FROM information_schema.columns WHERE table_schema='" + self.dbConfig['database'] +"' AND table_name = '" + tableName + "'"
		try:
			id = _dbCur.execute(query)
			columns = _dbCur.description
			result = []
			for value in _dbCur.fetchall():
				tmp = {
					'name': '',
					'dataType': '',
					'length': 0
				}
				for (index,column) in enumerate(value):
					if columns[index][0] == 'column_name':
						tmp['name'] = column
					if columns[index][0] == 'DATA_TYPE':
						tmp['dataType'] = column
					if columns[index][0] == 'NUMERIC_PRECISION' or columns[index][0] == 'CHARACTER_MAXIMUM_LENGTH':
						if column:
							if len(str(column)) > 0:
								tmp['length'] = int(column)

				result.append(tmp)

		except mydb.Error as e:
			try:
				logger.error("MySQL Errors [%d]: %s" % (e.args[0], e.args[1]))
				logger.error(query)
			except IndexError:
				logger.error("MySQL Errors: %s" % str(e))
				logger.error(query)

		_dbCur.close()
		_db.close()
		return result

	def tableExists(self,table):
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
			logger.info("Verify field %s" % field['name'])
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
		# print name
		# print cols
		# print field

		for col in cols:
			if col['name'].lower() == name.lower():
				colRes = col
				break

		for key in colRes:
			# If database is set to column type of text, do not change it to varchar
			if key == "dataType":
				# print "eval dataType"
				if str(colRes[key]).lower() == "text" and str(field[key]).lower() == "varchar":
					# print "continue"
					continue

			if str(colRes[key]).lower() == str(field[key]).lower():
				continue
			else:
				# print "False"
				res = False
				break

		return res

	def returnFieldObjectFromField(self,field):
		dfObj = DBField() # Creeat New DBField Obj
		dbField = dfObj.fieldDescription() # Get Default DBField Values
		for key, value in dbField.items():
			if key in field:
				dbField[key] = field[key]

		return dbField

	def createTable(self,tableName,fields):

		_result = False
		_db = mydb.connect(**myConfig)
		_db.autocommit = True
		_dbCur = _db.cursor(buffered=True)

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

		try:
			_dbCur.execute(_sqlStrExec.encode('ascii',errors='ignore'))
			_result = True
		except mydb.Error as e:
			try:
				logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
			except IndexError:
				logger.error("MySQL Error: %s" % str(e))

		_dbCur.close()
		_db.close()
		return _result

	def alterColumn(self,tableName,field):

		_db = mydb.connect(**myConfig)
		_db.autocommit = True
		_dbCur = _db.cursor(buffered=True)

		_field = self.returnFieldObjectFromField(field)
		_sqlStr = "ALTER TABLE %s" % tableName

		# is RID field
		if _field['name'] == 'rid' or _field['name'] == 'mdate' or _field['name'] == 'cuuid':
			_dbCur.close()
			_db.close()
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
			_dbCur.close()
			_db.close()
			return True

		try:
			_dbCur.execute(_sqlStr.encode('ascii',errors='ignore'))
			logger.info("%s was altered sucessfully." % _field['name'])
			_dbCur.close()
			_db.close()
			return True
		except mydb.Error as e:
			try:
				logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
				_dbCur.close()
				_db.close()
				return False
			except IndexError:
				logger.error("MySQL Error: %s" % str(e))
				_dbCur.close()
				_db.close()
				return False

	def createColumn(self, tableName, field):

		_db = mydb.connect(**myConfig)
		_db.autocommit = True
		_dbCur = _db.cursor(buffered=True)

		_field = self.returnFieldObjectFromField(field)
		_sqlStr = "ALTER TABLE %s" % tableName

		# is RID field
		if _field['name'] == 'rid' or _field['name'] == 'mdate' or _field['name'] == 'cuuid':
			_dbCur.close()
			_db.close()
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
			_dbCur.close()
			_db.close()
			return True

		try:
			_dbCur.execute(_sqlStr.encode('ascii',errors='ignore'))
			logger.info("%s was created sucessfully." % _field['name'])
			_dbCur.close()
			_db.close()
			return True
		except mydb.Error as e:
			try:
				logger.error("MySQL Error [%d]: %s" % (e.errno, e.msg))
				_dbCur.close()
				_db.close()
				return False
			except IndexError:
				logger.error("MySQL Error: %s" % str(e.msg))
				_dbCur.close()
				_db.close()
				return False

	def removeKeyData(self, tableName, keyVal):

		_result = False
		_db = mydb.connect(**myConfig)
		_db.autocommit = True
		_dbCur = _db.cursor(buffered=True)

		_sqlStr = "Delete from %s where cuuid = '%s'" % (str(tableName), str(keyVal))
		if gDebug:
			logger.debug(_sqlStr)
			_dbCur.close()
			_db.close()
			return True
		try:
			_dbCur.execute(_sqlStr)
			_dbCur.close()
			_db.close()
			_result = True
		except mydb.Error as e:
			try:
				logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
				_dbCur.close()
				_db.close()
			except IndexError:
				logger.error("MySQL Error: %s" % str(e))
				_dbCur.close()
				_db.close()

		return _result

	def updateRowData(self,tableName,keyVal,mdate,row):

		_result = False
		_db = mydb.connect(**myConfig)
		_db.autocommit = True
		_dbCur = _db.cursor(buffered=True)

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
			_dbCur.close()
			_db.close()
			return True
		try:
			_dbCur.execute(_sqlStr.encode('ascii',errors='ignore'))
			_dbCur.close()
			_db.close()
			_result = True
		except mydb.Error as e:
			try:
				logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
				logger.error(_sqlStr)
				_dbCur.close()
				_db.close()
			except IndexError:
				logger.error("MySQL Error: %s" % str(e))
				logger.error(_sqlStr)
				_dbCur.close()
				_db.close()

		return _result

	def insertRowData(self,tableName,keyVal,mdate,row):

		_result = False
		_db = mydb.connect(**myConfig)
		_db.autocommit = True
		_dbCur = _db.cursor(buffered=True)

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
			_dbCur.close()
			_db.close()
			return True
		try:
			_dbCur.execute(_sqlStr.encode('ascii',errors='ignore'))
			_dbCur.close()
			_db.close()
			_result = True
		except mydb.Error as e:
			try:
				logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
				logger.error(_sqlStr)
				_dbCur.close()
				_db.close()
			except IndexError:
				logger.error("MySQL Error: %s" % str(e))
				logger.error(_sqlStr)
				_dbCur.close()
				_db.close()

		return _result

class DataMgr:

	def __init__(self,aFile):
		self.file = aFile
		try:
			json_data=open(self.file)
			self.invData = json.load(json_data)
			json_data.close()
		except Exception as e:
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

	def displayData(self):
		pprint.pprint(self.invData)

	def dictContainsKeyValue(self, dict, key, value):
		for x in dict:
			if x[key] == value:
				return True

		return False

	def parseInvData(self):

		_result = False
		db = MPMySQL(myConfig)
		dbExists = False
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
		if _table not in db.tables:
			logger.info("Create new table %s" % _table)
			if db.createTable(_table,_fields) is False:
				return _result
		else:
			logger.info("Table %s exists." % _table)
			dbExists = True

		cols = db.columnsForTable(_table)
		db.colsToAlterOrAdd(_table,cols,_fields)

		# Purge Data if needed
		if dbExists:
			if self.invData['permanentRows'] is False:
				# Remove Client Data Before Insert
				# key = cuuid
				if self.valid_uuid(_keyVal):
					# key is valid
					db.removeKeyData(_table,_keyVal)
					if len(_rows) == 0:
						_result = True
						return _result
			else:
				updateData = True

		# Add or Update Data
		for row in _rows:
			_row = self.removeUnknownFields(row,_fields)
			if updateData:
				logger.info("Update record")
				if db.updateRowData(_table,_keyVal,_dtObj,_row):
					_result = True
			else:
				logger.info("Insert new record")
				if db.insertRowData(_table,_keyVal,_dtObj,_row):
					_result = True

		return _result

	def removeUnknownFields(self, row, fields):
		fieldNames = [d['name'] for d in fields]
		newdict = {k: row[k] for k in fieldNames if k in row}
		return newdict

# --------------------------------------------
# Main Class
# --------------------------------------------

class MPInventory:

	def __init__(self,filesBaseDir,keepProcessedFiles=False):
		self.filesBaseDir = filesBaseDir
		self.files = ''
		self.keepProcessedFiles = keepProcessedFiles

	def getFiles(self):
		if os.path.exists(self.filesBaseDir) and os.path.isdir(self.filesBaseDir):
			self.files = glob.glob(self.filesBaseDir + '/*.mpd')
			logger.debug("Files: found in " + self.filesBaseDir)
		else:
			logger.error("Error: " + self.filesBaseDir + " does not exist.")

	def displayFiles(self):
		self.getFiles()
		for x in self.files:
			print(x)

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
		logger.info("---------------------------------------------")
		logger.info("%d file(s) found to process."% len(self.files))
		for iFile in self.files:
			if os.path.exists(iFile):
				# Process the inv File
				try:
					dMgr = DataMgr(iFile)
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
	'''Main command processing'''
	parser = argparse.ArgumentParser(description='Process some args.')
	parser.add_argument('--config', help="Flask Global config file", required=False, default=None)
	parser.add_argument('--config-old', help="SiteConfig.json file", required=False, default=None)
	parser.add_argument('--debug', help='Set log level to debug', action='store_true')
	parser.add_argument('--files', help="JSON files to process", required=True)
	parser.add_argument('--save', help='Saves JSON files', action='store_true')
	parser.add_argument('--echo', help='Saves JSON files', required=False, action='store_true')
	args = parser.parse_args()

	# Setup Logging
	try:
		hdlr = logging.handlers.RotatingFileHandler(logFile, maxBytes=100 << 20, backupCount=5) # 100MB
		if args.debug:
			logger.setLevel(logging.DEBUG)
		else:
			logger.setLevel(logging.INFO)

		formatter = logging.Formatter('%(asctime)s %(levelname)s --- %(message)s')
		hdlr.setFormatter(formatter)
		logger.addHandler(hdlr)

		if args.echo:
			hdlrStdOut = logging.StreamHandler(sys.stdout)
			hdlrStdOut.setFormatter(formatter)
			logger.addHandler(hdlrStdOut)

	except Exception as e:
		print("%s" % e)
		sys.exit(1)

	# Make Sure the Config Exists
	useOldConfig=False
	confData = []
	if args.config_old:
		if not os.path.exists(args.config_old):
			print("Unable to open " + args.config_old +". File not found.")
			sys.exit(1)
		else:
			useOldConfig=True
			confFile = MP_FLASK_FILE

	elif args.config:
		if not os.path.exists(args.config):
			print("Unable to open " + args.config +". File not found.")
			sys.exit(1)
		else:
			confFile = MP_FLASK_FILE

	else:
		# Fall back to default flask
		if not os.path.exists(MP_FLASK_FILE):
			print("Unable to open " + MP_FLASK_FILE +". File not found.")
			sys.exit(1)

	try:
		if useOldConfig:
			with open(confFile) as data_file:
				confData = json.load(data_file)
		else:
			confData = read_config_file(confFile)

	except OSError:
		print("Error opening and loading json config file.")
		sys.exit(1)

	_cnf = None
	if useOldConfig:
		if 'prod' in confData['settings']['database']:
			_cnf = confData['settings']['database']['prod']
			# pprint.pprint(_cnf)
		else:
			raise ValueError("Error, prod was not defined in db config")
			return None

		if 'dbName' in _cnf:
			myConfig['database'] = _cnf['dbName']
		else:
			raise ValueError("Error, config missing key.")

		if 'dbHost' in _cnf:
			myConfig['host'] = _cnf['dbHost']
		else:
			raise ValueError("Error, config missing key.")

		if 'dbPort' in _cnf:
			myConfig['port'] = int(_cnf['dbPort'])
		else:
			raise ValueError("Error, config missing key.")

		if 'username' in _cnf:
			myConfig['user'] = _cnf['username']
		else:
			raise ValueError("Error, config missing key.")

		if 'password' in _cnf:
			myConfig['password'] = _cnf['password']
		else:
			raise ValueError("Error, config missing key.")
	else:
		if 'DB_NAME' in confData:
			myConfig['database'] = confData['DB_NAME']
		else:
			raise ValueError("Error, config missing key DB_NAME.")

		if 'DB_HOST' in confData:
			myConfig['host'] = confData['DB_HOST']
		else:
			raise ValueError("Error, config missing key DB_HOST.")

		if 'DB_USER' in confData:
			myConfig['user'] = confData['DB_USER']
		else:
			raise ValueError("Error, config missing key DB_USER.")

		if 'DB_PASS' in confData:
			myConfig['password'] = confData['DB_PASS']
		else:
			raise ValueError("Error, config missing key DB_PASS.")

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

	mpi = MPInventory(args.files)
	while True:
		mpi.processFiles()
		time.sleep(3.0)


if __name__ == '__main__':
	main()
