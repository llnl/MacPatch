from flask import render_template, jsonify, request, session
from flask_security import login_required
import json
import base64
import uuid
import sys

from sqlalchemy import text
from datetime import datetime

from .  import reports
from .. import db
from .. import login_manager
from .. model import *
from .. mplogger import *

# This is a UI Request
@reports.route('/new')
@login_required
def new():
	inv_tables = []
	inv_tables.append(['mp_clients_plist',0])
	inv_tables.append(['mp_clients',0])

	sql_tables = text('''
		Select DISTINCT TABLE_NAME
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_NAME LIKE 'mpi_%'
		AND TABLE_SCHEMA='MacPatchDB3';''')
	result = db.engine.execute(sql_tables)
	for row in result:
		inv_tables.append([str(row[0]),0])

	return render_template('reports/new_report.html', tables=inv_tables, data={}, columns={}, selTables=[], selColumns=[])

# This is a UI Request
@reports.route('/edit/<id>')
@login_required
def editReport(id):

	_selTables = []
	_selColumns = []
	_selQuery = ""
	qInv = InvReports.query.filter(InvReports.rid == id).first()
	if qInv is not None:
		_selTables = qInv.rtable.split(",")
		_selColumns = qInv.rcolumns.split(",")
		_selQuery = qInv.rquery

	raw_tables = []
	inv_tables = []
	raw_tables.append('mp_clients_plist')
	raw_tables.append('mp_clients')

	sql_tables = text('''
		Select DISTINCT TABLE_NAME
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_NAME LIKE 'mpi_%'
		AND TABLE_SCHEMA='MacPatchDB3';''')
	result = db.engine.execute(sql_tables)
	for row in result:
		_tbl = str(row[0])
		raw_tables.append(_tbl)

	for table in raw_tables:
		_tbl = [table,0]
		for t in _selTables:
			if t == table:
				_tbl = [table,1]
				break

		inv_tables.append(_tbl)

	return render_template('reports/new_report.html', tables=inv_tables, data={}, columns={}, filter={},
							selTables=_selTables, selColumns=_selColumns, selQuery=_selQuery)

''' AJAX Method '''
@reports.route('/list')
def listOfReports():
	_results = []
	sql = 'Select rid, name FROM mp_inv_reports WHERE owner = \'{}\' OR scope = \'0\';'.format(session['user'])

	res = db.engine.execute(sql)
	for row in res:
		_row = {}
		_row['id'] = row.rid
		_row['name'] = row.name
		_results.append(_row)

	return json.dumps({'data': _results}), 200

''' AJAX Method '''
@reports.route('/delete/<id>',methods=['DELETE'])
def deleteReport(id):
	_results = []
	qInv = InvReports.query.filter(InvReports.rid == id).first()
	if qInv is not None:
		db.session.delete(qInv)
		db.session.commit()

	return json.dumps({'data': _results}), 200

# This is a UI Request
@reports.route('/show/<id>')
@login_required
def showReportUI(id):
	# Check if Owner or Public
	title="None"
	owner=False
	columns = []
	qInv = InvReports.query.filter(InvReports.rid == id).first()
	if qInv is not None:
		title = qInv.name
		if qInv.rcolumns == "*":
			columns = columnsForTable(qInv.rtable)
		else:
			columns = qInv.rcolumns.split(",")

		if qInv.owner == session['user']:
			owner=True

	return render_template('reports/report.html', report_id=id, title=title, columns=columns, denied=False, isowner=owner)

''' AJAX Method '''
@reports.route('/report/<id>/<limit>/<offset>/<search>/<sort>/<order>')
def showReportPaged(id,limit,offset,search,sort,order):

	qInv = InvReports.query.filter(InvReports.rid == id).first()
	if qInv.rcolumns == "*":
		colsForQuery = columnsForTable(qInv.rtable)
	else:
		colsForQuery = qInv.rcolumns.split(",")

	qry_info = {'table': qInv.rtable, 'columns': colsForQuery, 'query': qInv.rquery}

	total = 0
	getNewTotal = True
	if 'my_inv_search_name' in session:
		if session['my_inv_search_name'] == 'showReport':
			if 'my_inv_search' in session and 'my_inv_search_total' in session:
				if session['my_inv_search'] == search:
					getNewTotal = False
					total = session['my_inv_search_total']
	else:
		session['my_inv_search_name'] ='showReport'
		session['my_inv_search_total'] = 0
		session['my_inv_search'] = None

	qResult = requiredQuery(qry_info, search, int(offset), int(limit), sort, order, getNewTotal)
	query = qResult[0]

	session['my_inv_search_name'] = 'showReport'

	if getNewTotal:
		total = qResult[1]
		session['my_inv_search_total'] = total
		session['my_inv_search'] = search

	_results = []
	for p in query:
		row = {}
		for x in colsForQuery:
			y = "p."+x.replace('mp_clients.','').strip()
			if x == 'mdate':
				row[x] = eval(y)
			elif x == 'type':
				row[x] = eval(y).title()
			else:
				row[x] = eval(y)

		_results.append(row)

	return json.dumps({'data': _results, 'total': qResult[1]}, default=json_serial), 200

# Private
def requiredQueryOrig(queryInfo, filterStr='undefined', page=0, page_size=0, sort='mdate', order='desc', getCount=True):

	rowCounter = 0

	sql_where = ""
	sql_and = []
	if queryInfo['query'] != "":
		sql_where = "WHERE " + queryInfo['query']
		if filterStr != "undefined":
			sql_where = '{} AND ('.format(sql_where)
			for col in queryInfo['columns']:
				sql_and.append('{} LIKE \'%{}%\''.format(col,filterStr))
				sql_and.append('OR')

			if len(sql_and) > 1:
				sql_and.pop()

			sql_where = '{} {})'.format(sql_where," ".join(sql_and))
	else:
		if filterStr != "undefined":
			sql_where = 'WHERE '
			for col in queryInfo['columns']:
				sql_and.append('{} LIKE \'%{}%\''.format(col,filterStr))
				sql_and.append('OR')

			if len(sql_and) > 1:
				sql_and.pop()

			sql_where = '{} {}'.format(sql_where," ".join(sql_and))

	sql_rows = 'SELECT 1 FROM {} {};'.format(queryInfo['table'], sql_where)
	query_rows = db.engine.execute(text(sql_rows.strip()))
	rowCounter = query_rows.rowcount

	_start = page*page_size
	_end = page_size

	sql = 'SELECT {} FROM {} {} ORDER BY {} {} LIMIT {},{};'.format(",".join(queryInfo['columns']), queryInfo['table'], sql_where, sort, order, _start, _end)
	query = db.engine.execute(text(sql.strip()))
	return (query, rowCounter)

def requiredQuery(queryInfo, filterStr='undefined', page=0, page_size=0, sort='mdate', order='desc', getCount=True):

	useMpClients = False
	rowCounter = 0
	if 'mp_clients.' in ','.join(queryInfo['columns']):
		useMpClients = True


	sql_where = ""
	sql_and = []
	if queryInfo['query'] != "":
		sql_where = "WHERE " + queryInfo['query']
		if filterStr != "undefined":
			sql_where = '{} AND ('.format(sql_where)
			for col in queryInfo['columns']:
				sql_and.append('{} LIKE \'%{}%\''.format(col,filterStr))
				sql_and.append('OR')

			if len(sql_and) > 1:
				sql_and.pop()

			sql_where = '{} {})'.format(sql_where," ".join(sql_and))
	else:
		if filterStr != "undefined":
			sql_where = 'WHERE '
			for col in queryInfo['columns']:
				sql_and.append('{} LIKE \'%{}%\''.format(col,filterStr))
				sql_and.append('OR')

			if len(sql_and) > 1:
				sql_and.pop()

			sql_where = '{} {}'.format(sql_where," ".join(sql_and))

	# Get row count
	if useMpClients:
		sql_rows = (
					f"SELECT 1 FROM {queryInfo['table']}"
					f" LEFT JOIN mp_clients ON {queryInfo['table']}.cuuid = mp_clients.cuuid"
					f" {sql_where};"
					)
	else:
		sql_rows = 'SELECT 1 FROM {} {};'.format(queryInfo['table'], sql_where)

	query_rows = db.engine.execute(text(sql_rows.strip()))
	rowCounter = query_rows.rowcount

	_start = page*page_size
	_end = page_size
	if useMpClients:
		sql = (
				f"SELECT {','.join(queryInfo['columns'])}"
				f" FROM {queryInfo['table']}"
				f" LEFT JOIN mp_clients ON {queryInfo['table']}.cuuid = mp_clients.cuuid"
				f" {sql_where}"
				f" ORDER BY {queryInfo['table']}.{sort} {order}" 
				f" LIMIT {_start},{_end};"
				)
	else:
		sql = 'SELECT {} FROM {} {} ORDER BY {} {} LIMIT {},{};'.format(",".join(queryInfo['columns']), queryInfo['table'], sql_where, sort, order, _start, _end)
	query = db.engine.execute(text(sql.strip()))
	return (query, rowCounter)

# Private
def columnsForTable(table):
	columns = []
	sql = 'Select COLUMN_NAME FROM information_schema.columns WHERE TABLE_NAME = \'{}\' AND table_schema = \'MacPatchDB3\' order by ordinal_position;'.format(table)
	query = db.engine.execute(sql)

	if query is not None:
		for i in query:
			if i[0] != 'rid':
				columns.append(i.COLUMN_NAME)

	return columns

# This is a UI Request
@reports.route('/save')
@login_required
def save():
	return render_template('reports/save_report.html', data={}, columns={})

''' AJAX Method '''
@reports.route('/save/report',methods=['POST'])
@login_required
def saveReport():

	_form = request.form.to_dict()

	isNewReport=True
	qInv = InvReports()

	# Get Row ID
	if 'id' in _form:
		rid = _form['id']
		qInv = InvReports.query.filter(InvReports.rid == rid).first()
		if qInv is not None:
			isNewReport=False

	# Set Record values
	setattr(qInv, 'name', _form['name'])
	setattr(qInv, 'owner', _form['owner'])
	setattr(qInv, 'scope', _form['scope'])
	setattr(qInv, 'rtable', _form['table'])
	setattr(qInv, 'rcolumns', _form['columns'])
	setattr(qInv, 'rquery', _form['query'])
	setattr(qInv, 'mdate', datetime.now())

	if isNewReport:
		setattr(qInv, 'cdate', datetime.now())
		db.session.add(qInv)

	try:
		db.session.commit()
		db.session.refresh(qInv)
		return json.dumps({'errorno': 0, 'id': qInv.rid}, default=json_serial), 201

	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		message=str(e.args[0]).encode("utf-8")
		return json.dumps({'errorno': 500, 'errormsg': message, 'data': {}}), 500

	return json.dumps({'errorno': 0}, default=json_serial), 304

''' AJAX Method '''
''' Used for querybuilder '''
@reports.route('/table/fields/<table_name>')
def tableFields(table_name):
	_results = []
	_total = 0
	mp_clients_cols = None

	sql_columns = """
		Select COLUMN_NAME, DATA_TYPE
		FROM information_schema.columns
		WHERE TABLE_NAME = \'""" + table_name + """\'
		AND table_schema = 'MacPatchDB3'
		order by ordinal_position;"""

	if table_name != 'mp_clients':
		mp_clients_cols = """
				Select COLUMN_NAME, DATA_TYPE
				FROM information_schema.columns
				WHERE TABLE_NAME = 'mp_clients'
				AND table_schema = 'MacPatchDB3'
				order by ordinal_position;"""

	query_result = db.engine.execute(sql_columns)
	for row in query_result:
		if row[0] != 'rid':
			_total = _total + 1
			_row = {}
			_row['id'] = row.COLUMN_NAME
			_row['type'] = typeForColumn(row.DATA_TYPE)
			_results.append(_row)

	if mp_clients_cols is not None:
		query_result = db.engine.execute(mp_clients_cols)
		for row in query_result:
			if row[0] != 'rid' or row[0] != 'cuuid' or row[0] != 'mdate':
				_total = _total + 1
				_row = {}
				_row['id'] = f'mp_clients.{row.COLUMN_NAME}'
				_row['type'] = typeForColumn(row.DATA_TYPE)
				_results.append(_row)

	return json.dumps({'data': _results, 'total': _total}), 200

@reports.route('/table/preview/<table_name>', methods=['POST'])
def previewTableData(table_name):
	from ast import literal_eval

	_form = request.form.to_dict()
	_cols = 'Select * FROM '
	_limitCols=False
	if 'columns' in _form:
		if _form['columns'] != "*":
			_limitCols=True
			_cols = 'Select %s FROM ' % (_form['columns'])

	if _form['sql'] == "":
		qStr = [_cols, ' LIMIT 0, 10;']
		qStr.insert(1, table_name)
		if 'mp_clients.' in " ".join(qStr):
			qStr.insert(2, f' LEFT JOIN mp_clients ON {table_name}.cuuid = mp_clients.cuuid ')
	else:
		qStr = [_cols,' WHERE ', ' LIMIT 0, 10;']
		qStr.insert(1, table_name)
		if 'mp_clients.' in " ".join(qStr):
			qStr.insert(2, f' LEFT JOIN mp_clients ON {table_name}.cuuid = mp_clients.cuuid ')
			qStr.insert(4, _form['sql'])
		else:
			qStr.insert(3, _form['sql'])

	sql_query = " ".join(qStr)
	sql_query = sql_query.replace('%', '%%') # pymysql addition
	query_result = db.engine.execute(sql_query)

	_columns = []
	_jColumns = []
	if _limitCols:
		colList = _form['columns'].split(",")
		for col in colList:
				_columns.append(col)
				_jColumns.append({'field':col, 'title':col})
	else:
		sql_columns = """
			Select COLUMN_NAME
			FROM information_schema.columns
			WHERE TABLE_NAME = \'""" + table_name + """\'
			AND table_schema = 'MacPatchDB3'
			order by ordinal_position;"""

		# Get Columns for table
		cols_query = db.engine.execute(sql_columns)
		for col in cols_query:
			if col[0] != 'rid':
				_columns.append(col.COLUMN_NAME)
				_jColumns.append({'field':col.COLUMN_NAME, 'title':col.COLUMN_NAME})

		# Python3 does not support sorted properly anymore
		#_jColumns = sorted(_jColumns)

	# Query Preview Data
	_results = []

	for row in query_result:
		_row = {}
		if _limitCols:
			for idx, val in enumerate(row):
				_row[_columns[idx]] = val
			_results.append(_row)
		else:
			for c in sorted(_columns):
				_row[c] = row[c]
			_results.append(_row)

	return json.dumps({'error': 0, 'data': _results, 'cols': _jColumns}, default=json_serial), 200

def typeForColumn(type):
	if 'int' in type:
		return 'integer'
	elif 'double' in type:
		return 'double'
	elif 'date' == type:
		return 'date'
	elif 'time' == type:
		return 'time'
	elif 'datetime' == type or 'timestamp' == type:
		return 'datetime'
	elif 'text' in type:
		return 'string'
	else:
		return 'string'

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.strftime('%Y-%m-%d %H:%M:%S')
		return serial
	raise TypeError("Type not serializable")
