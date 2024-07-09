#!/opt/MacPatch/Server/env/server/bin/python3

'''
    Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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
    Version: 1.7.2
    History:

    1.7.1: Base
    1.7.2: Updated to support new dotfile config

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
import mysql.connector as mydb
from datetime import datetime
from uuid import UUID
import shutil
import json
import os.path

from dotenv import load_dotenv
from multiprocessing import Pool

gDebug = False
gKeepFiles = False

# MySQL Global Config
myConfig = {
    'user': 'dbuser',
    'password': 'password',
    'host': 'localhost',
    'port': 3306,
    'database': 'MacPatchDB3',
    'raise_on_warnings': True,
    'buffered': True
}

# Define logging for global use
logger        = logging.getLogger('MPInventory')

MP_SRV_BASE   = "/opt/MacPatch/Server"
MP_FLASK_FILE = MP_SRV_BASE+"/apps/.mpglobal"
logFile       = MP_SRV_BASE+"/logs/MPInventory.log"
invFilesDir   = MP_SRV_BASE+"/InvData/files"
confFile      = MP_SRV_BASE+"/etc/siteconfig.json"

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

class MPDB:

    def __init__(self,dbConfig):
        try:
            self.dbConfig = dbConfig
            self.connection = mydb.connect(**dbConfig)
            self.connection.autocommit = False
            self.cursor = self.connection.cursor(buffered=True)

        except mydb.Error as err:
            if err.errno == mydb.errorcode.ER_ACCESS_DENIED_ERROR:
                logger.error("Something is wrong with your user name or password")
            elif err.errno == mydb.errorcode.ER_BAD_DB_ERROR:
                logger.error("Database does not exists")
            else:
                logger.error(err)
            
            self.cursor.close()
            self.connection.close

    def setAutoCommit(self,enable):
        self.connection.autocommit = enable

    def tablesFromDataBase(self):

        tables = []
        try:
            self.cursor.execute("SHOW TABLES")
            for (table_name,) in self.cursor:
                tables.append(table_name)

        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
            except IndexError:
                logger.error("MySQL Error: %s" % str(e))

        finally:
            return tables

    def getInventoryTables(self):
        tables = []
        try:    
            #qry = 'SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_SCHEMA = ' + myConfig['database'] + ' AND table_name like \'mpi_%\';'
            qry = 'SELECT TABLE_NAME FROM information_schema.tables WHERE table_name like \'mpi_%\';'
            self.cursor.execute(qry)
            for (table_name,) in self.cursor:
                tables.append(table_name)

        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
                exit(1)
            except IndexError:
                logger.error("MySQL Error: %s" % str(e))
                exit(1)

        finally:
            
            return list(set(tables))
    
    def columnsForTable(self,tableName):
        result = []
        query = "SELECT COLUMN_NAME, DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,NUMERIC_PRECISION FROM information_schema.columns WHERE table_schema='" + self.dbConfig['database'] +"' AND table_name = '" + tableName + "'"
        try:
            id = self.cursor.execute(query)
            columns = self.cursor.description
            result = []
            for value in self.cursor.fetchall():
                tmp = {
                    'name': '',
                    'dataType': '',
                    'length': 0
                }
                for (index,column) in enumerate(value):
                    if columns[index][0] == 'COLUMN_NAME':
                        tmp['name'] = column
                    if columns[index][0] == 'DATA_TYPE':
                        tmp['dataType'] = column
                    if columns[index][0] == 'NUMERIC_PRECISION' or columns[index][0] == 'CHARACTER_MAXIMUM_LENGTH':
                        if column:
                            if len(str(column)) > 0:
                                if columns[index][0] == 'NUMERIC_PRECISION':
                                    tmp['length'] = int(column) + 1
                                else:
                                    tmp['length'] = int(column)

                result.append(tmp)

        except mydb.Error as e:
            try:
                logger.error("MySQL Errors [%d]: %s" % (e.args[0], e.args[1]))
                logger.error(query)
            except IndexError:
                logger.error("MySQL Errors: %s" % str(e))
                logger.error(query)

        return result
    
    def commitAndClose(self):
        try:
            if self.connection.autocommit == False:
                self.connection.commit()
            else:
                logger.debug("Autocommit is enabled. No commit is nessasary.")
        except mydb.Error as err:
             logger.error("Failed to commit to database, will rollback: {}".format(err))
             self.connection.rollback()
        finally:
            self.cursor.close()
            self.connection.close()

    def rollbackAndClose(self):
        self.connection.rollback()
        self.cursor.close()
        self.connection.close()

    def close(self):
        self.cursor.close()
        self.connection.close()

class MPMySQL:

    def __init__(self, mpdb):
        self.database = mpdb.dbConfig['database']
        self.dbCursor = mpdb.cursor
        self.dbConn = mpdb.connection

    def columnsForTable(self,tableName):

        result = []
        query = "SELECT COLUMN_NAME, DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,NUMERIC_PRECISION FROM information_schema.columns WHERE table_schema='" + self.database +"' AND table_name = '" + tableName + "'"
        try:
            id = self.dbCursor.execute(query)
            columns = self.dbCursor.description
            result = []
            for value in self.dbCursor.fetchall():
                tmp = {
                    'name': '',
                    'dataType': '',
                    'length': 0
                }
                for (index,column) in enumerate(value):
                    if columns[index][0] == 'COLUMN_NAME':
                        tmp['name'] = column
                    if columns[index][0] == 'DATA_TYPE':
                        tmp['dataType'] = column
                    if columns[index][0] == 'NUMERIC_PRECISION' or columns[index][0] == 'CHARACTER_MAXIMUM_LENGTH':
                        if column:
                            if len(str(column)) > 0:
                                if columns[index][0] == 'NUMERIC_PRECISION':
                                    tmp['length'] = int(column) + 1
                                else:
                                    tmp['length'] = int(column)

                result.append(tmp)

        except mydb.Error as e:
            try:
                logger.error("MySQL Errors [%d]: %s" % (e.args[0], e.args[1]))
                logger.error(query)
            except IndexError:
                logger.error("MySQL Errors: %s" % str(e))
                logger.error(query)

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

    # Has Cache
    def createTable(self,tableName,fields):

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

        try:
            self.dbCursor.execute(_sqlStrExec.encode('ascii',errors='ignore'))
            self.dbConn.commit()
            _result = True
        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
            except IndexError:
                logger.error("MySQL Error: %s" % str(e))

            self.dbConn.rollback()

        return _result

    # Has Cache
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

        try:
            self.dbCursor.execute(_sqlStr.encode('ascii',errors='ignore'))
            self.dbConn.commit()
            logger.info("%s was altered sucessfully." % _field['name'])
            return True

        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
            except IndexError:
                logger.error("MySQL Error: %s" % str(e))
                
            self.dbConn.rollback()
            return False

    # Has Cache
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

        try:
            self.dbCursor.execute(_sqlStr.encode('ascii',errors='ignore'))
            self.dbConn.commit()
            logger.info("%s was created sucessfully." % _field['name'])

            return True
        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.errno, e.msg))
            except IndexError:
                logger.error("MySQL Error: %s" % str(e.msg))
                
            self.dbConn.rollback()
            return False

    def removeKeyData(self, tableName, keyVal):
        
        _result = False
        _sqlStr = "Delete from %s where cuuid = '%s'" % (str(tableName), str(keyVal))
        if gDebug:
            logger.debug(_sqlStr)
            return True
        try:
            self.dbCursor.execute(_sqlStr)
            _result = True
        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
            except IndexError:
                logger.error("MySQL Error: %s" % str(e))

        return _result

    def updateRowData(self,tableName,keyVal,mdate,row):

        _result = False

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
        try:
            self.dbCursor.execute(_sqlStr.encode('ascii',errors='ignore'))
            _result = True
        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
                logger.error(_sqlStr)
            except IndexError:
                logger.error("MySQL Error: %s" % str(e))
                logger.error(_sqlStr)

        return _result

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
        try:
            self.dbCursor.execute(_sqlStr.encode('ascii',errors='ignore'))
            _result = True
        except mydb.Error as e:
            try:
                logger.error("MySQL Error [%d]: %s" % (e.args[0], e.args[1]))
                logger.error(_sqlStr)
            except IndexError:
                logger.error("MySQL Error: %s" % str(e))
                logger.error(_sqlStr)

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

        mysqlDB = MPDB(myConfig)
        db = MPMySQL(mysqlDB)

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
        _tables = mysqlDB.tablesFromDataBase()
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

        mysqlDB.commitAndClose()
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

    def __init__(self, filesBaseDir, keepProcessedFiles=False, poolCount=2):
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
        
        p = Pool(self.poolCount)
        p.map(self.processFile, self.files)
        p.close()
        logger.info("***************** DONE ***************** ")

    def processFile(self, file):
        if os.path.exists(file):
            # Process the inv File
            try:
                dMgr = DataMgr(file)
                if dMgr.parseInvData() is True:
                    if gKeepFiles is True:
                        self.moveInvFile(file)
                    else:
                        os.remove(file)
                else:
                    self.moveErrorFile(file)

            except Exception as e:
                logger.error('Error reading {0}:\n{1}'.format(file,e))
                self.moveErrorFile(file)    

    def processFilesOld(self):
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

    
    # Parse Config
    if args.config:
        if not os.path.exists(MP_FLASK_FILE):
            print("Unable to open " + MP_FLASK_FILE +". File not found.")
            sys.exit(1)
        else:
            load_dotenv(MP_FLASK_FILE, override=True)

            if 'DB_NAME' in os.environ:
                myConfig['database'] = os.environ.get('DB_NAME')
            else:
                raise ValueError("Error, config missing key DB_NAME.")

            if 'DB_HOST' in os.environ:
                myConfig['host'] = os.environ.get('DB_HOST')
            else:
                raise ValueError("Error, config missing key DB_HOST.")

            if 'DB_USER' in os.environ:
                myConfig['user'] = os.environ.get('DB_USER')
            else:
                raise ValueError("Error, config missing key DB_USER.")

            if 'DB_PASS' in os.environ:
                myConfig['password'] = os.environ.get('DB_PASS')
            else:
                raise ValueError("Error, config missing key DB_PASS.")

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

    mpi = MPInventory(args.files)
    while True:
        mpi.processFiles()
        time.sleep(3.0)


if __name__ == '__main__':
    main()
