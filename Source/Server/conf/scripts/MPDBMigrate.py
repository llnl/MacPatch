#!/opt/MacPatch/Server/env/server/bin/python3

'''
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
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
	Script: MPDBMigrate.py
	Version: 1.1.0

	Description: This Script is used to migrate tables and data from
	and older version of MacPatch (< 3.0.0) to the new MacPatch 3.0
	schema.

	Prior to use, the MacPatch 3.0 database needs to be created and
	the 3.0 schema needs to be loaded. This is done using the mpapi
	app. Please see the install docs in regards to this.

	Please note, NOT ALL tables will be migrated. Data for the core
	tables from the new schema will be migrated and all of the inventory
	tables will be migrated. Any other custom tables will need to
	be done by your database administrator.

	Info:
	MacPatch 2.x database name = MacPatchDB
	MacPatch 3.x database name = MacPatchDB3

	Usage: Prior to use populate myConfig_new and myConfig_old database
	settings. Please

'''

import argparse
import mysql.connector as mydb
from mysql.connector import errorcode
from datetime import datetime
import getpass


gDebug = False

# MySQL New Database Configuration
myConfig_new = {
  'user': 'mpdbadm',
  'password': '',
  'host': 'localhost',
  'port': '3306',
  'database': 'MacPatchDB3',
  'raise_on_warnings': True,
  'buffered': True,
  'autocommit': True
}

# MySQL Old Database Configuration
myConfig_old = {
  'user': 'mpdbadm',
  'password': '',
  'host': 'localhost',
  'port': '3306',
  'database': 'MacPatchDB',
  'raise_on_warnings': True,
  'buffered': True
}

# Maps Table Data Columns
# New table col as key and old col as value
table_map = {
	'mp_installed_patches': { 'mdate': 'date' }
}

MP_SRV_BASE  = "/opt/MacPatch/Server"
IGNORE_TABLES = ['alembic_version']

# --------------------------------------------
# Define Classes
# --------------------------------------------

class MPMySQL:

	def __init__(self,dbConfig):
		try:
			self.dbConf = dbConfig
			self.db = mydb.connect(**dbConfig)
			self.dbObj = self.db.cursor()
			self.tables = self.tablesFromDataBase()

		except mydb.Error as err:
			if err.errno == mydb.errorcode.ER_ACCESS_DENIED_ERROR:
				print("Something is wrong with your user name or password")
			elif err.errno == mydb.errorcode.ER_BAD_DB_ERROR:
				print("Database does not exists")
			else:
				print(err)
		else:
		  self.db.close()

	def tablesFromDataBase(self,beginsWithStr=None):
		_db = mydb.connect(**self.dbConf)
		_dbCur = _db.cursor()

		tables = []
		try:
			_query = "show full tables where Table_Type = 'BASE TABLE'"
			_dbCur.execute(_query)
			for value in _dbCur.fetchall():
				table = value[0]
				if beginsWithStr != None:
					if table.startswith( beginsWithStr ):
						tables.append(table)
				else:
					tables.append(table)

			_dbCur.close();
		except mydb.Error as e:
			try:
				print(( "MySQL Error [%d]: %s" % (e.args[0], e.args[1])))
			except IndexError:
				print(( "MySQL Error: %s" % str(e)))

		return tables

	def columnsForTable(self,tableName):

		_db = mydb.connect(**self.dbConf)
		_dbCur = _db.cursor()

		result = []
		query = "SELECT column_name, DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,NUMERIC_PRECISION FROM information_schema.columns WHERE table_name = '%s' AND table_schema = '%s'" % (tableName, self.dbConf['database'])
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

			_dbCur.close();
		except mydb.Error as e:
			try:
				print(("MySQL Errors [%d]: %s" % (e.args[0], e.args[1])))
				print(query)
			except IndexError:
				print(("MySQL Errors: %s" % str(e)))
				print(query)

		return result

	def tableExists(self,table):
		if table.upper() in list(map(str.upper, self.tables)):
			return True
		else:
			return False

	def columnExists(self, column, table):
		result = False
		columns = self.columnsForTable(table)

		for x in columns:
			if column.upper() == x['name'].upper():
				result = True
				break

		return result

class MigrateDB:

	def __init__(self, dbConfigNew=None, dbConfigOld=None):
		if dbConfigNew and dbConfigOld:
			self.dbNewConf = dbConfigNew
			self.dbOldConf = dbConfigOld
		else:
			self.dbNewConf = myConfig_new
			self.dbOldConf = myConfig_old

	def migrateCoreTables(self):
		dbNew = MPMySQL(self.dbNewConf)
		dbOld = MPMySQL(self.dbOldConf)

		print("Reading database tables")
		tablesNewFilter = [i for i in dbNew.tables if i not in IGNORE_TABLES]
		if len(tablesNewFilter) <= 2:
			print("No tables to migrate, please check that the new database model is installed.")
			return

		new_tables = []
		old_tables = []
		for table in tablesNewFilter:
			_table = {}
			_table['name'] = table
			_cols = []
			_colsRaw = dbNew.columnsForTable(table)
			for col in _colsRaw:
				_cols.append(col['name'])
			_table['columns'] = _cols
			new_tables.append(_table)


		for nTable in new_tables:
			if nTable['name'] in dbOld.tables:
				_table = {}
				_table['name'] = nTable['name']
				_cols = []
				_colsRaw = dbOld.columnsForTable(nTable['name'])
				for col in _colsRaw:
					_cols.append(col['name'])

				_table['columns'] = _cols
				old_tables.append(_table)


		dbNameNew = myConfig_new['database']
		dbNameOld = myConfig_old['database']

		'''
		mp_clients_table = None
		mp_clients_index = 99999
		for index, table in enumerate(old_tables):
			if table['name'] == 'mp_clients':
				mp_clients_index = index
				mp_clients_table = table
				break

		if mp_clients_index < 99999:
			old_tables.pop(mp_clients_index)
			old_tables.insert(0,mp_clients_table)
		'''

		for oTable in old_tables:
			newColsList = self.colsFromTableList(new_tables,oTable['name'])
			oldColsList = oTable['columns']
			colsList = self.mergedCols(oTable['name'],oldColsList,newColsList)
			colsStrOld = ', '.join(colsList[0])
			colsStrNew = ', '.join(colsList[1])
			_query = """INSERT INTO %s.%s (%s)
						SELECT DISTINCT %s FROM %s.%s;""" % (dbNameNew, oTable['name'], colsStrNew, colsStrOld, dbNameOld, oTable['name'])

			try:

				_db = mydb.connect(**self.dbNewConf)
				_dbCur = _db.cursor()

				_dbCur.execute("SET FOREIGN_KEY_CHECKS=0;")

				print("Migrating %s table" % (oTable['name']))
				_dbCur.execute(_query.encode('ascii',errors='ignore'))

				_dbCur.execute("SET FOREIGN_KEY_CHECKS=1;")
				_dbCur.close()
				_db.close()

			except mydb.Error as err:
				if err.errno == errorcode.ER_BAD_TABLE_ERROR:
					_dbCur.close()
					_db.close()
					print("Creating table spam")
				elif err.errno == 1592:
					_dbCur.close()
					_db.close()
				else:
					_dbCur.close()
					_db.close()
					raise


	def colsFromTableList(self,tables,table):
		cols = None
		for t in tables:
			if t['name'] == table:
				cols = t['columns']
				break

		return cols


	def mergedCols(self,table,oldCols,newCols):
		colsOld = []
		colsNew = []
		#print oldCols
		#print newCols
		for c in newCols:
			_c = c.lower()
			if c == 'rid':
				continue

			for x in oldCols:
				if x.lower() == _c:
					if table in table_map:
						if str(c) in table_map[table]:
							y = str(c)
							colsOld.append(table_map[table][y])
							colsNew.append(str(c))
						else:
							colsOld.append(str(x))
							colsNew.append(str(c))
					else:
						colsOld.append(str(x))
						colsNew.append(str(c))
					break

		#print colsOld
		#print colsNew
		return (colsOld,colsNew)


	def migrateInvTables(self):
		dbNew = MPMySQL(self.dbNewConf)
		dbOld = MPMySQL(self.dbOldConf)

		newTables = dbNew.tablesFromDataBase("mpi_")
		oldTables = dbOld.tablesFromDataBase("mpi_")

		tablesToMigrate = [i for i in oldTables if i not in newTables]

		for table in tablesToMigrate:
			self.copyInvTable(table)
			self.copyInvDate(table)
			if dbNew.columnExists('date', table):
				self.removeColumnsFromTable(table, 'date')


	def copyInvTable(self, table):

		dbNameNew = self.dbNewConf['database']
		dbNameOld = self.dbOldConf['database']

		_query = """CREATE TABLE %s.%s LIKE %s.%s;""" % (dbNameNew, table, dbNameOld, table)

		try:
			#print _query
			_db = mydb.connect(**self.dbNewConf)
			_dbCur = _db.cursor()

			print("[INV] Create %s table" % (table))
			_dbCur.execute(_query.encode('ascii',errors='ignore'))
			_dbCur.close()
			_db.close()

		except mydb.Error as err:
			if err.errno == errorcode.ER_BAD_TABLE_ERROR:
				_dbCur.close()
				_db.close()
			elif err.errno == 1592:
				_dbCur.close()
				_db.close()
			else:
				_dbCur.close()
				_db.close()
				raise


	def copyInvDate(self, table):

		dbNameNew = self.dbNewConf['database']
		dbNameOld = self.dbOldConf['database']

		_query = """INSERT INTO %s.%s SELECT * FROM %s.%s;""" % (dbNameNew, table, dbNameOld, table)

		try:
			#print _query
			_db = mydb.connect(**self.dbNewConf)
			_dbCur = _db.cursor()

			print("[INV] Copy data to %s table" % (table))
			_dbCur.execute(_query.encode('ascii',errors='ignore'))
			_dbCur.close()
			_db.close()

		except mydb.Error as err:
			if err.errno == errorcode.ER_BAD_TABLE_ERROR:
				_dbCur.close()
				_db.close()
			elif err.errno == 1592:
				_dbCur.close()
				_db.close()
			else:
				_dbCur.close()
				_db.close()
				raise


	def removeColumnsFromTable(self, table, column):

		try:
			_query = """ALTER TABLE %s DROP COLUMN %s;""" % (table, column)

			#print _query
			_db = mydb.connect(**self.dbNewConf)
			_dbCur = _db.cursor()

			print("[INV] Delete column (%s) from %s" % (column, table))
			_dbCur.execute(_query.encode('ascii',errors='ignore'))
			_dbCur.close()
			_db.close()

		except mydb.Error as err:
			if err.errno == errorcode.ER_BAD_TABLE_ERROR:
				_dbCur.close()
				_db.close()
			elif err.errno == 1592:
				_dbCur.close()
				_db.close()
			else:
				_dbCur.close()
				_db.close()
				raise

# --------------------------------------------
# Main Class
# --------------------------------------------

def main():
	'''Main command processing'''
	parser = argparse.ArgumentParser(description='Process some args.')
	parser.add_argument('--core',       help='Set log level to debug', action='store_true')
	parser.add_argument('--inventory',  help='Set log level to debug', action='store_true')
	parser.add_argument('--oldHost',    help="Old database host", required=False)
	parser.add_argument('--newHost',    help="New database host", required=False)
	parser.add_argument('--oldDB',      help="Old database name", required=False, default='MacPatchDB')
	parser.add_argument('--newDB',      help="New database name", required=False, default='MacPatchDB3')
	parser.add_argument('--oldUser',    help="Old database user", required=False, default='mpdbadm')
	parser.add_argument('--newUser',    help="New database user", required=False, default='mpdbadm')
	parser.add_argument('--noprompt',   help='Do not prompt for password, use default values.', action='store_true')
	args = parser.parse_args()

	_oldConf = myConfig_old
	_newConf = myConfig_new

	if args.noprompt == False:
		gOldPass = getpass.getpass("OLD Database Password:")
		gNewPass = getpass.getpass("NEW Database Password:")
		_oldConf['password'] = gOldPass
		_newConf['password'] = gNewPass

	if args.oldHost:
		_oldConf['host'] = args.oldHost

	if args.newHost:
		_newConf['host'] = args.newHost

	if args.oldDB:
		_oldConf['database'] = args.oldDB

	if args.newDB:
		_newConf['database'] = args.newDB

	if args.oldUser:
		_oldConf['user'] = args.oldUser

	if args.newUser:
		_newConf['user'] = args.newUser


	mdb = MigrateDB(_newConf, _oldConf)
	if args.core:
		print("Migrating Core Tables")
		mdb.migrateCoreTables()

	if args.inventory:
		print("Migrating Inventory Tables")
		mdb.migrateInvTables()


if __name__ == '__main__':
	main()
