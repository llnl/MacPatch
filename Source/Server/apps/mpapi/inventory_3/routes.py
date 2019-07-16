from flask import request
from flask_restful import reqparse
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from uuid import UUID
import datetime
import json
import sys
import pprint


from .  import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

class AddInventoryData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(AddInventoryData, self).__init__()

	def post(self, client_id):

		if not isValidClientID(client_id):
			log_Error('[AddInventoryData][Post]: Failed to verify ClientID (%s)' % (client_id))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify ClientID'}, 412

		if not isValidSignature(self.req_signature, client_id, request.data, self.req_ts):
			log_Error('[AddInventoryData][Post]: Failed to verify Signature for client (%s)' % (client_id))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify Signature'}, 412

		jData = request.get_json(force=True)
		if jData:
			
			_table="/tmp/" + jData['table'] + ".log"
			with open(_table, 'w') as f:
				json.dump(jData, f)

			try:
				dMgr = DataMgr(jData)
				if dMgr.parseInvData() is True:
					me = MpInvLog(cuuid=client_id, mp_server=request.host, inv_table=jData['table'],
								error_no=0, error_msg='', json_data='', mdate=datetime.now() )
					db.session.add(me)
					db.session.commit()
				else:
					ilog = MpInvLog(cuuid=client_id, mp_server=request.host, inv_table=jData['table'],
								error_no=1, error_msg='', json_data='', mdate=datetime.now())
					db.session.add(ilog)
					elog = MpInvErrors(cuuid=client_id, inv_table=jData['table'],
								error_msg='Error adding inventory.', json_data=jData, mdate=datetime.now())
					db.session.add(elog)
					db.session.commit()
					return {"result": '', "errorno": 417, "errormsg": 'Error adding inventory.'}, 417

				return {"result": '', "errorno": 0, "errormsg": ''}, 201

			except Exception as e:
				db.session.add(elog)
				db.session.commit()
				exc_type, exc_obj, exc_tb = sys.exc_info()
				message=str(e.args[0]).encode("utf-8")
				log_Error('[AddInventoryData][Post][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
				elog = MpInvErrors(cuuid=client_id, inv_table=jData['table'], error_msg='Error adding inventory.', json_data=jData, mdate=datetime.now())
				return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


		log_Error('[AddInventoryData][Post]: Inventory data is empty.')
		return {"result": '', "errorno": 412, "errormsg": 'Inventory Data empty'}, 412

# Add Routes Resources
inventory_3_api.add_resource(AddInventoryData,    '/client/inventory/<string:client_id>')

# ---------------------------------------------------------------------------
# Inventory Classes
# ---------------------------------------------------------------------------

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

class DataMgr:

	def __init__(self,inventoryData):
		self.invData = inventoryData
		#log_Info("Processing %s data for client id %s." % self.invData['table'], self.invData['key'])
		return

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
		inventory = Inventory()
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
		if _table not in inventory.tables:
			log_Info("Create new table %s" % _table)
			if inventory.createTable(_table,_fields) is False:
				return _result
		else:
			log_Info("Table %s exists." % _table)
			dbExists = True

		cols = inventory.columnsForTable(_table)
		inventory.colsToAlterOrAdd(_table,cols,_fields)

		# Purge Data if needed
		if dbExists:
			if self.invData['permanentRows'] is False:
				# Remove Client Data Before Insert
				# key = cuuid
				if self.valid_uuid(_keyVal):
					# key is valid
					inventory.removeKeyData(_table,_keyVal)
					if len(_rows) == 0:
						_result = True
						return _result
			else:
				updateData = True

		# Add or Update Data
		updated = 0
		added = 0
		for row in _rows:
			_row = self.removeUnknownFields(row,_fields)
			if updateData:
				log_Debug("Update record")
				if inventory.updateRowData(_table,_keyVal,_dtObj,_row):
					_result = True
					updated += 1
			else:
				log_Debug("Insert new record")
				if inventory.insertRowData(_table,_keyVal,_dtObj,_row):
					_result = True
					added += 1

		log_Info("Added {} record(s).".format(str(added)))
		log_Info("Updated {} record(s).".format(str(updated)))

		return _result

	def removeUnknownFields(self, row, fields):
		fieldNames = [d['name'] for d in fields]
		newdict = {k: row[k] for k in fieldNames if k in row}
		return newdict

class Inventory:

	def __init__(self):
		self.tables = self.tablesFromDataBase()
		return

	def tablesFromDataBase(self):
		_tables = []

		# Get Tables
		sqlStr = text("SHOW TABLES;")
		result = db.engine.execute(sqlStr)
		for (table_name,) in result:
			_tables.append(table_name)

		return _tables

	def columnsForTable(self,tableName):

		columns = []
		dbName = current_app.config['DB_NAME']
		sqlStr = text("""
					  SELECT column_name, DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,NUMERIC_PRECISION 
					  FROM information_schema.columns 
					  WHERE table_schema='""" + dbName + """' 
					  AND table_name = '""" + tableName + """'
					  """)

		result = db.engine.execute(sqlStr)
		for row in result:
			tmp = {
				'name': '',
				'dataType': '',
				'length': 0
			}
			tmp['name'] = row.COLUMN_NAME
			tmp['dataType'] = row.DATA_TYPE
			if row.NUMERIC_PRECISION is not None:
				tmp['length'] = row.NUMERIC_PRECISION

			if row.CHARACTER_MAXIMUM_LENGTH is not None:
				tmp['length'] = row.CHARACTER_MAXIMUM_LENGTH

			columns.append(tmp)

		return columns

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
		log_Info("Number of fields to verify: %d" % len(fields))
		for field in fields:
			log_Debug("Verify field %s" % field['name'])
			if self.searchForColNameInFields(field['name'],cols) is False:
				log_Info("Add Field: %s" % field['name'])
				x = self.createColumn(tableName,field)
			else:
				if self.colMatchesDataInField(field['name'],cols,field) is False:
					log_Info("Alter Field: %s" % field['name'])
					x = self.alterColumn(tableName,field)
				else:
					log_Debug("Field Passed: %s" % field['name'])

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
				if str(colRes[key]).lower() == "text" and str(field[key]).lower() == "varchar":
					continue

			if str(colRes[key]).lower() == str(field[key]).lower():
				continue
			else:
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

			if _field['allowNull'] is False and _field['autoIncrement'] is False:
				_sqlStr = _sqlStr + " NOT NULL"

			if len(_field['defaultValue']) > 0:
				if _field['name'] != 'rid' and "date" not in field['name']:
					_sqlStr = _sqlStr + " DEFAULT '" + _field['defaultValue'] + "'"

			if _field['autoIncrement']:
				_sqlStr = _sqlStr + " NOT NULL AUTO_INCREMENT"

			if _field['primaryKey']:
				_sqlPkeyStr = " PRIMARY KEY (`"+_field['name']+"`),"
				# Add Foreign Key, after primary
				_sqlPkeyStr = _sqlPkeyStr + " FOREIGN KEY(cuuid) REFERENCES mp_clients(cuuid)"
				_sqlPkeyStr = _sqlPkeyStr + " ON DELETE CASCADE ON UPDATE NO ACTION"

			_sqlArr.append(_sqlStr)

		_sqlArr.append(_sqlPkeyStr)
		_sqlStrExec = _sqlStrBegin + " " + ','.join(_sqlArr) + ");"
		log_Debug(_sqlStrExec)

		try:
			result = db.engine.execute(_sqlStrExec)
			return True

		except OSError as err:
			log_Error(format(err))
			return False
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return False

		return True

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
		log_Debug(_sqlStr)

		try:
			result = db.engine.execute(_sqlStr)
			return True

		except OSError as err:
			log_Error(format(err))
			return False
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error("Exception: " + message)
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
		log_Debug(_sqlStr)

		try:
			result = db.engine.execute(_sqlStr)
			return True

		except OSError as err:
			log_Error(format(err))
			return False
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error("Exception: " + message)
			return False

	def removeKeyData(self, tableName, keyVal):

		_sqlStr = "Delete from %s where cuuid = '%s'" % (str(tableName), str(keyVal))
		log_Debug(_sqlStr)

		try:
			result = db.engine.execute(_sqlStr)
			return True

		except OSError as err:
			log_Error(format(err))
			return False
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error("Exception: " + message)
			return False

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
		log_Debug(_sqlStr)

		try:
			result = db.engine.execute(_sqlStr)
			return True

		except OSError as err:
			log_Error(format(err))
			return False
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error("Exception: " + message)
			return False

	def insertRowData(self,tableName,keyVal,mdate,row):

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
		log_Debug(_sqlStr)

		try:
			result = db.engine.execute(_sqlStr)
			return True

		except OSError as err:
			log_Error(format(err))
			return False
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error("Exception: " + message)
			return False
