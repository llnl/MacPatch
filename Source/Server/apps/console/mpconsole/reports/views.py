from flask import render_template, request, session
import json
import sys
import re

from sqlalchemy import text, bindparam
from datetime import datetime

from .  import reports
from mpconsole.app import db, login_manager
from mpconsole.model import *
from mpconsole.mplogger import *
from mpconsole.app_decorators import login_required


# ============================================================================
# SECURITY HELPER FUNCTIONS
# ============================================================================

def get_allowed_tables():
    """Get whitelist of valid table names from database"""
    allowed = {'mp_clients_plist', 'mp_clients'}

    sql_tables = text('''
        SELECT DISTINCT TABLE_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME LIKE 'mpi_%'
        AND TABLE_SCHEMA='MacPatchDB3';''')

    try:
        with db.engine.connect() as conn:
            result = conn.execute(sql_tables)
            for row in result:
                allowed.add(str(row[0]))
    except Exception as e:
        logit(f"Error fetching allowed tables: {e}")

    return allowed


def validate_table_name(table_name):
    """Validate table name against whitelist"""
    allowed = get_allowed_tables()
    if table_name not in allowed:
        raise ValueError(f"Invalid table name: {table_name}")
    return table_name


def validate_column_name(column_name):
    """Validate column name format (alphanumeric, underscore, dot only)"""
    # Allow table.column syntax
    if not re.match(r'^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)?$', column_name):
        raise ValueError(f"Invalid column name: {column_name}")
    return column_name


def validate_column_list(columns_str):
    """Validate comma-separated column list"""
    if columns_str == "*":
        return "*"

    columns = [col.strip() for col in columns_str.split(',')]
    validated = []

    for col in columns:
        if col:  # Skip empty strings
            validated.append(validate_column_name(col))

    if not validated:
        raise ValueError("No valid columns provided")

    return ','.join(validated)


def validate_sql_order(order):
    """Validate SQL order direction"""
    order = order.lower()
    if order not in ['asc', 'desc']:
        return 'desc'
    return order


def sanitize_query_builder_sql(sql_where):
    """
    Basic validation for query builder WHERE clauses.
    Query builder generates SQL - we validate it doesn't contain dangerous patterns.
    """
    if not sql_where or sql_where == "":
        return ""

    # Block dangerous SQL keywords
    dangerous_patterns = [
        r'\bDROP\b', r'\bDELETE\b', r'\bTRUNCATE\b', r'\bUPDATE\b',
        r'\bINSERT\b', r'\bEXEC\b', r'\bEXECUTE\b', r'\bALTER\b',
        r'\bCREATE\b', r'\bREPLACE\b', r'\bGRANT\b', r'\bREVOKE\b',
        r';', r'--', r'/\*', r'\*/', r'\bINTO\s+OUTFILE\b',
        r'\bLOAD_FILE\b', r'\bINTO\s+DUMPFILE\b'
    ]

    for pattern in dangerous_patterns:
        if re.search(pattern, sql_where, re.IGNORECASE):
            raise ValueError(f"Unsafe SQL pattern detected: {pattern}")

    return sql_where


# ============================================================================
# ROUTES
# ============================================================================

@reports.route('/new')
@login_required
def new():
    inv_tables = []
    inv_tables.append(['mp_clients_plist', 0])
    inv_tables.append(['mp_clients', 0])

    sql_tables = text('''
        SELECT DISTINCT TABLE_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME LIKE 'mpi_%'
        AND TABLE_SCHEMA='MacPatchDB3';''')

    with db.engine.connect() as conn:
        result = conn.execute(sql_tables)

    for row in result:
        inv_tables.append([str(row[0]), 0])

    return render_template('reports/new_report.html', tables=inv_tables, data={}, columns={}, selTables=[], selColumns=[])


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
        SELECT DISTINCT TABLE_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME LIKE 'mpi_%'
        AND TABLE_SCHEMA='MacPatchDB3';''')

    with db.engine.connect() as conn:
        result = conn.execute(sql_tables)

    for row in result:
        _tbl = str(row[0])
        raw_tables.append(_tbl)

    for table in raw_tables:
        _tbl = [table, 0]
        for t in _selTables:
            if t == table:
                _tbl = [table, 1]
                break
        inv_tables.append(_tbl)

    return render_template('reports/new_report.html', tables=inv_tables, data={}, columns={}, filter={},
                          selTables=_selTables, selColumns=_selColumns, selQuery=_selQuery)


# FIX: Use parameterized query
@reports.route('/list')
@login_required
def listOfReports():
    _results = []

    # Use parameterized query instead of f-string
    sql = text("SELECT rid, name FROM mp_inv_reports WHERE owner = :username OR scope = 0")

    with db.engine.connect() as conn:
        res = conn.execute(sql, {"username": session['user']})

    for row in res:
        _row = {}
        _row['id'] = row.rid
        _row['name'] = row.name
        _results.append(_row)

    return json.dumps({'data': _results}), 200


@reports.route('/delete/<id>', methods=['DELETE'])
@login_required
def deleteReport(id):
    _results = []
    qInv = InvReports.query.filter(InvReports.rid == id).first()
    if qInv is not None:
        db.session.delete(qInv)
        db.session.commit()

    return json.dumps({'data': _results}), 200


@reports.route('/show/<id>')
@login_required
def showReportUI(id):
    title = "None"
    owner = False
    columns = []

    qInv = InvReports.query.filter(InvReports.rid == id).first()
    if qInv is not None:
        title = qInv.name
        if qInv.rcolumns == "*":
            columns = columnsForTable(qInv.rtable)
        else:
            columns = qInv.rcolumns.split(",")

        if qInv.owner == session['user']:
            owner = True

    return render_template('reports/report.html', report_id=id, title=title, columns=columns, denied=False, isowner=owner)


@reports.route('/report/<id>/<limit>/<offset>/<search>/<sort>/<order>')
@login_required
def showReportPaged(id, limit, offset, search, sort, order):
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
        session['my_inv_search_name'] = 'showReport'
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
            y = "p." + x.replace('mp_clients.', '').strip()
            if x == 'mdate':
                row[x] = eval(y)
            elif x == 'type':
                row[x] = eval(y).title()
            else:
                row[x] = eval(y)
        _results.append(row)

    return json.dumps({'data': _results, 'total': qResult[1]}, default=json_serial), 200


# FIX: Use parameterized queries and validation
def requiredQuery(queryInfo, filterStr='undefined', page=0, page_size=0, sort='mdate', order='desc', getCount=True):
    useMpClients = False
    rowCounter = 0

    if sort == "undefined":
        sort = 'mdate'

    if order == "undefined":
        order = 'desc'

    # Validate inputs
    table_name = validate_table_name(queryInfo['table'])
    order = validate_sql_order(order)
    sort_column = validate_column_name(sort)

    # Validate columns
    validated_columns = []
    for col in queryInfo['columns']:
        validated_columns.append(validate_column_name(col.strip()))

    if 'mp_clients.' in ','.join(validated_columns):
        useMpClients = True

    # Build WHERE clause with parameterized search
    sql_where = ""
    params = {}

    # Validate the stored query (from query builder)
    if queryInfo['query'] and queryInfo['query'] != "":
        validated_query = sanitize_query_builder_sql(queryInfo['query'])
        sql_where = f"WHERE {validated_query}"

        if filterStr != "undefined" and filterStr:
            sql_where = f"{sql_where} AND ("
            # Use parameterized search
            like_clauses = []
            for idx, col in enumerate(validated_columns):
                param_name = f"search_{idx}"
                like_clauses.append(f"{col} LIKE :{param_name}")
                params[param_name] = f"%{filterStr}%"
            sql_where = sql_where + " OR ".join(like_clauses) + ")"
    else:
        if filterStr != "undefined" and filterStr:
            sql_where = "WHERE "
            like_clauses = []
            for idx, col in enumerate(validated_columns):
                param_name = f"search_{idx}"
                like_clauses.append(f"{col} LIKE :{param_name}")
                params[param_name] = f"%{filterStr}%"
            sql_where = sql_where + " OR ".join(like_clauses)

    # Get row count
    if useMpClients:
        sql_rows = text(
            f"SELECT 1 FROM {table_name}"
            f" LEFT JOIN mp_clients ON {table_name}.cuuid = mp_clients.cuuid"
            f" {sql_where}"
        )
    else:
        sql_rows = text(f"SELECT 1 FROM {table_name} {sql_where}")

    print(f"sql_rows: {sql_rows}")

    with db.engine.connect() as conn:
        raw_result = conn.execute(sql_rows, params)
        query_rows = raw_result.mappings().all()

    rowCounter = len(query_rows)

    _start = page * page_size
    _end = page_size

    # Build main query
    if useMpClients:
        sql = text(
            f"SELECT {','.join(validated_columns)}"
            f" FROM {table_name}"
            f" LEFT JOIN mp_clients ON {table_name}.cuuid = mp_clients.cuuid"
            f" {sql_where}"
            f" ORDER BY {table_name}.{sort_column} {order}"
            f" LIMIT {_start},{_end}"
        )
    else:
        sql = text(
            f"SELECT {','.join(validated_columns)}"
            f" FROM {table_name} {sql_where}"
            f" ORDER BY {sort_column} {order}"
            f" LIMIT {_start},{_end}"
        )

    print(f"sql: {sql}")

    with db.engine.connect() as conn:
        raw_result = conn.execute(sql, params)
        query = raw_result.mappings().all()

    return (query, rowCounter)


# FIX: Use parameterized query for table name validation
def columnsForTable(table):
    # Validate table name first
    table_name = validate_table_name(table)

    columns = []
    sql = text(
        "SELECT COLUMN_NAME FROM information_schema.columns "
        "WHERE TABLE_NAME = :table_name AND table_schema = 'MacPatchDB3' "
        "ORDER BY ordinal_position"
    )

    with db.engine.connect() as conn:
        query = conn.execute(sql, {"table_name": table_name})

    if query is not None:
        for i in query:
            if i[0] != 'rid':
                columns.append(i.COLUMN_NAME)

    return columns


@reports.route('/save')
@login_required
def save():
    return render_template('reports/save_report.html', data={}, columns={})


@reports.route('/save/report', methods=['POST'])
@login_required
def saveReport():
    _form = request.form.to_dict()

    isNewReport = True
    qInv = InvReports()

    # Get Row ID
    if 'id' in _form:
        rid = _form['id']
        qInv = InvReports.query.filter(InvReports.rid == rid).first()
        if qInv is not None:
            isNewReport = False

    try:
        # Validate inputs before saving
        validate_table_name(_form['table'])
        validate_column_list(_form['columns'])
        if _form['query']:
            sanitize_query_builder_sql(_form['query'])

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

        db.session.commit()
        db.session.refresh(qInv)
        return json.dumps({'errorno': 0, 'id': qInv.rid}, default=json_serial), 201

    except ValueError as ve:
        # Validation error
        return json.dumps({'errorno': 400, 'errormsg': str(ve), 'data': {}}), 400
    except Exception as e:
        exc_type, exc_obj, exc_tb = sys.exc_info()
        message = str(e.args[0]).encode("utf-8")
        return json.dumps({'errorno': 500, 'errormsg': message, 'data': {}}), 500

    return json.dumps({'errorno': 0}, default=json_serial), 304


# FIX: Use parameterized query for table fields
@reports.route('/table/fields/<table_name>')
@login_required
def tableFields(table_name):
    _results = []
    _total = 0

    try:
        # Validate table name
        validated_table = validate_table_name(table_name)
    except ValueError as e:
        return json.dumps({'error': str(e), 'data': [], 'total': 0}), 400

    mp_clients_cols = None

    # Use parameterized query
    sql_columns = text(
        "SELECT COLUMN_NAME, DATA_TYPE "
        "FROM information_schema.columns "
        "WHERE TABLE_NAME = :table_name "
        "AND table_schema = 'MacPatchDB3' "
        "ORDER BY ordinal_position"
    )

    if validated_table != 'mp_clients':
        mp_clients_cols = text(
            "SELECT COLUMN_NAME, DATA_TYPE "
            "FROM information_schema.columns "
            "WHERE TABLE_NAME = 'mp_clients' "
            "AND table_schema = 'MacPatchDB3' "
            "ORDER BY ordinal_position"
        )

    with db.engine.connect() as conn:
        query_result = conn.execute(sql_columns, {"table_name": validated_table})

    for row in query_result:
        if row[0] != 'rid':
            _total = _total + 1
            _row = {}
            _row['id'] = row.COLUMN_NAME
            _row['type'] = typeForColumn(row.DATA_TYPE)
            _results.append(_row)

    if mp_clients_cols is not None:
        with db.engine.connect() as conn:
            query_result = conn.execute(mp_clients_cols)
        for row in query_result:
            if row[0] not in ['rid', 'cuuid', 'mdate']:
                _total = _total + 1
                _row = {}
                _row['id'] = f'mp_clients.{row.COLUMN_NAME}'
                _row['type'] = typeForColumn(row.DATA_TYPE)
                _results.append(_row)

    return json.dumps({'data': _results, 'total': _total}), 200


# FIX: Major overhaul with parameterized queries
@reports.route('/table/preview/<table_name>', methods=['POST'])
@login_required
def previewTableData(table_name):
    _form = request.form.to_dict()

    try:
        # Validate table name
        validated_table = validate_table_name(table_name)

        # Validate columns
        _limitCols = False
        validated_columns = []

        if 'columns' in _form and _form['columns'] != "*":
            _limitCols = True
            validated_columns_str = validate_column_list(_form['columns'])
            validated_columns = [col.strip() for col in validated_columns_str.split(',')]

        # Validate WHERE clause from query builder
        where_clause = ""
        params = {}

        if _form.get('sql', '') != "":
            where_clause = sanitize_query_builder_sql(_form['sql'])

        # Build query safely
        useMpClients = False
        columns_to_select = ', '.join(validated_columns) if _limitCols else '*'

        if 'mp_clients.' in columns_to_select or (_form.get('sql', '') and 'mp_clients.' in _form['sql']):
            useMpClients = True

        if useMpClients:
            if where_clause:
                sql_query = text(
                    f"SELECT {columns_to_select} FROM {validated_table} "
                    f"LEFT JOIN mp_clients ON {validated_table}.cuuid = mp_clients.cuuid "
                    f"WHERE {where_clause} LIMIT 10"
                )
            else:
                sql_query = text(
                    f"SELECT {columns_to_select} FROM {validated_table} "
                    f"LEFT JOIN mp_clients ON {validated_table}.cuuid = mp_clients.cuuid "
                    f"LIMIT 10"
                )
        else:
            if where_clause:
                sql_query = text(f"SELECT {columns_to_select} FROM {validated_table} WHERE {where_clause} LIMIT 10")
            else:
                sql_query = text(f"SELECT {columns_to_select} FROM {validated_table} LIMIT 10")

        with db.engine.connect() as conn:
            query_result = conn.execute(sql_query, params)

        # Get columns
        _columns = []
        _jColumns = []

        if _limitCols:
            for col in validated_columns:
                _columns.append(col)
                _jColumns.append({'field': col, 'title': col})
        else:
            # Get all columns for the table
            sql_columns = text(
                "SELECT COLUMN_NAME FROM information_schema.columns "
                "WHERE TABLE_NAME = :table_name AND table_schema = 'MacPatchDB3' "
                "ORDER BY ordinal_position"
            )

            with db.engine.connect() as conn:
                cols_query = conn.execute(sql_columns, {"table_name": validated_table})

            for col in cols_query:
                if col[0] != 'rid':
                    _columns.append(col.COLUMN_NAME)
                    _jColumns.append({'field': col.COLUMN_NAME, 'title': col.COLUMN_NAME})

        # Query Preview Data
        _results = []

        for row in query_result:
            _row = {}
            if _limitCols:
                for idx, val in enumerate(row):
                    _row[_columns[idx]] = val
            else:
                for c in sorted(_columns):
                    _row[c] = row[c]
            _results.append(_row)

        return json.dumps({'error': 0, 'data': _results, 'cols': _jColumns}, default=json_serial), 200

    except ValueError as ve:
        return json.dumps({'error': 1, 'message': str(ve), 'data': [], 'cols': []}, default=json_serial), 400
    except Exception as e:
        logit(f"Error in previewTableData: {e}")
        return json.dumps({'error': 1, 'message': 'Database error', 'data': [], 'cols': []}, default=json_serial), 500


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
