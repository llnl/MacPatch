"""
Inventory ingest core: validate an inventory payload, create the table if needed, add or
widen columns for new data, then store the client's rows.

Used by the API (shared/inventory.py, SQLAlchemy) and by conf/scripts/MPInventoryD.py
(pymysql). Standard library only, so MPInventoryD can import this file directly without
loading the API. The database is reached through a small Session object, see `Session`.

Payload (JSON) sent by the agent
	table          mpi_<name>
	fields         [{name, dataType, length, ...}], one per column in the rows
	rows           [{field name: value, ...}]
	permanentRows  false (default): purge the client's rows in the table, then insert the rows
	               true: keep the client's rows; update a row that matches, else insert it
	checkFields    with permanentRows, extra columns (besides cuuid) that identify a row
	key            ignored, the client ID always comes from the authenticated request
	autoFields     ignored, rid / cuuid / mdate are always created

What a client can do is limited on purpose
	- only mpi_* tables, only the three reserved columns plus the columns it declares
	- only a fixed set of column types, columns are only ever added or widened
	- values are always sent to the database as bound parameters
	- only the authenticated client's own rows are purged or changed
There is no limit on the number of rows or the size of a table.
"""
import hashlib
import json
import re
import time

__all__ = ['InventoryError', 'LockTimeout', 'Plan', 'parse', 'process', 'stamp_client', 'classify_error']


class InventoryError(Exception):
	"""The payload is not acceptable (HTTP 400)."""

	def __init__(self, message, code=400):
		super().__init__(message)
		self.code = code
		self.message = message


class LockTimeout(RuntimeError):
	"""Gave up waiting to change a table's structure."""


# ----------------------------------------------------------------------------
# Rules
# ----------------------------------------------------------------------------
TABLE_RE = re.compile(r'^mpi_[A-Za-z0-9_]{1,60}$')                  # 64 characters max in total
CLIENT_ID_RE = re.compile(r'^[A-Za-z0-9._:\-]{1,50}$')              # mp_clients.cuuid is varchar(50)
DEFAULT_VALUE_RE = re.compile(r'^[A-Za-z0-9_ .:\-]{0,255}$')
# Column names come from agents and plugins (system_profiler keys, plugin keys), so be permissive
# but never allow anything that needs escaping in SQL.
BAD_NAME_CHARS_RE = re.compile(r'[\x00-\x1f\x7f`%\\]')
MAX_NAME_LENGTH = 64

RESERVED = ('rid', 'cuuid', 'mdate')

STRING_TYPES = ('char', 'varchar')
TEXT_TYPES = {'tinytext': 255, 'text': 65535, 'mediumtext': 16777215, 'longtext': 4294967295}
INT_TYPES = ('tinyint', 'smallint', 'mediumint', 'int', 'bigint')    # in size order
DATE_TYPES = ('datetime', 'timestamp', 'date', 'time')
TYPE_ALIASES = {'integer': 'int'}
TYPE_EXTENSIONS = ('', 'unsigned')                                  # dataTypeExt values accepted

BATCH_SIZE = 5000


def _is_string_type(data_type):
	return data_type in STRING_TYPES or data_type in TEXT_TYPES


def _capacity(data_type, length):
	"""Characters / bytes a string column holds."""
	return TEXT_TYPES[data_type] if data_type in TEXT_TYPES else length


# ----------------------------------------------------------------------------
# Parsing and validation
# ----------------------------------------------------------------------------
def valid_name(name):
	return (isinstance(name, str) and 0 < len(name) <= MAX_NAME_LENGTH and name == name.strip()
			and BAD_NAME_CHARS_RE.search(name) is None)


def quote(name):
	"""Quote a table/column name that has been validated."""
	if not valid_name(name):
		raise InventoryError('Invalid name (%r).' % (name,))
	return '`%s`' % name


class Column:
	def __init__(self, name, data_type='varchar', length=255, ext='', default='', allow_null=True):
		self.name = name
		self.data_type = data_type
		self.length = length
		self.ext = ext
		self.default = default
		self.allow_null = allow_null

	def definition(self):
		"""SQL type and attributes: `varchar(255) NULL DEFAULT 'x'`."""
		if self.data_type in STRING_TYPES:
			sql = '%s(%d)' % (self.data_type, self.length)
		else:
			sql = self.data_type
		if self.ext:
			sql += ' ' + self.ext
		sql += ' NULL' if self.allow_null else ' NOT NULL'
		if self.default != '' and (_is_string_type(self.data_type) or self.data_type in INT_TYPES):
			# TEXT columns can't have a default
			if self.data_type not in TEXT_TYPES:
				sql += " DEFAULT '%s'" % self.default
		return sql


class Plan:
	"""A validated inventory payload."""

	def __init__(self, table, columns, rows, permanent_rows, check_fields):
		self.table = table
		self.columns = columns              # [Column], does not include rid / cuuid / mdate
		self.rows = rows                    # [{column name: value}]
		self.permanent_rows = permanent_rows
		self.check_fields = check_fields    # [column name]


def _parse_column(field):
	if not isinstance(field, dict):
		raise InventoryError('Each field must be an object.')

	name = field.get('name')
	if not valid_name(name):
		raise InventoryError('Invalid field name (%r).' % (name,))

	data_type = str(field.get('dataType') or 'varchar').lower()
	data_type = TYPE_ALIASES.get(data_type, data_type)
	if not (data_type in STRING_TYPES or data_type in TEXT_TYPES or data_type in INT_TYPES
			or data_type in DATE_TYPES):
		raise InventoryError('Field (%s) has an unsupported data type (%s).' % (name, data_type))

	length = 255
	if data_type in STRING_TYPES:
		try:
			length = int(field.get('length') or 255)
		except (TypeError, ValueError):
			raise InventoryError('Field (%s) has an invalid length.' % name)
		if not 1 <= length <= (255 if data_type == 'char' else 16383):
			raise InventoryError('Field (%s) has an invalid length (%d).' % (name, length))

	ext = str(field.get('dataTypeExt') or '').strip().lower()
	if ext not in TYPE_EXTENSIONS or (ext and data_type not in INT_TYPES):
		raise InventoryError('Field (%s) has an unsupported data type extension (%s).' % (name, ext))

	default = field.get('defaultValue')
	default = '' if default is None else str(default)
	if not DEFAULT_VALUE_RE.match(default):
		raise InventoryError('Field (%s) has an unsupported default value.' % name)

	return Column(name, data_type, length, ext, default, field.get('allowNull', True) is not False)


def _value(value):
	"""A row value as the database should get it (the agent sends strings)."""
	if value is None or isinstance(value, str):
		return value
	if isinstance(value, bool):
		return '1' if value else '0'
	if isinstance(value, (int, float)):
		return str(value)
	return json.dumps(value)


def parse(inv, with_rows=True):
	"""
	Validate an inventory payload (dict) and return a Plan. Raises InventoryError.
	with_rows=False only checks the table, fields and that rows is a list, it does not go
	through the rows (cheap, for staging a big payload to a file); the Plan then has no rows.
	"""
	if not isinstance(inv, dict):
		raise InventoryError('Inventory data must be a JSON object.')

	table = inv.get('table')
	if not isinstance(table, str) or not TABLE_RE.match(table):
		raise InventoryError('Invalid inventory table name (%r), it must be mpi_ followed by letters, '
							 'numbers or underscores.' % (table,))

	fields, rows = inv.get('fields'), inv.get('rows')
	if not isinstance(fields, list):
		raise InventoryError('Inventory fields are missing.')
	if not isinstance(rows, list):
		raise InventoryError('Inventory rows are missing.')

	columns, seen = [], set(n.lower() for n in RESERVED)
	for field in fields:
		column = _parse_column(field)
		if column.name.lower() in seen:
			continue        # reserved column or a repeat of an earlier field
		seen.add(column.name.lower())
		columns.append(column)

	names = set(c.name for c in columns)
	clean_rows = []
	for row in (rows if with_rows else ()):
		if not isinstance(row, dict):
			raise InventoryError('Each row must be an object.')
		# Only declared columns are stored, anything else in the row is ignored
		clean_rows.append({k: _value(v) for k, v in row.items() if k in names})

	permanent = inv.get('permanentRows', False) is True
	check = inv.get('checkFields') or []
	if isinstance(check, str):
		check = check.split(',')
	check_fields = [c.strip() for c in check if isinstance(c, str) and c.strip() in names]

	return Plan(table, columns, clean_rows, permanent, check_fields)


def stamp_client(inv, client_id):
	"""
	Set the payload's key to the authenticated client ID (used when the payload is saved to a
	file for MPInventoryD to process later). Raises InventoryError if the table, fields or
	client ID are invalid. The rows are checked later, by the process that loads them.
	"""
	if not isinstance(client_id, str) or not CLIENT_ID_RE.match(client_id):
		raise InventoryError('Invalid client ID.')
	parse(inv, with_rows=False)
	inv['key'] = client_id
	return inv


# ----------------------------------------------------------------------------
# Database work
# ----------------------------------------------------------------------------
class Session:
	"""
	What process() needs from a database connection (one connection, one session). SQL uses
	%s placeholders. Implemented for SQLAlchemy in shared/inventory.py and for pymysql in
	conf/scripts/MPInventoryD.py.

		execute(sql, params=None) -> affected rows
		executemany(sql, list of param tuples)
		fetchall(sql, params=None) -> list of tuples
		commit() / rollback()
	"""


class _Log:
	def info(self, *a): pass
	debug = error = warning = info


def _existing_columns(session, table):
	rows = session.fetchall(
		"SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH FROM information_schema.columns "
		"WHERE table_schema = DATABASE() AND table_name = %s", (table,))
	return {r[0].lower(): (str(r[1]).lower(), int(r[2]) if r[2] is not None else 0) for r in rows}


def _create_table(plan):
	columns = ['`rid` bigint unsigned NOT NULL AUTO_INCREMENT',
			   '`cuuid` varchar(50) NOT NULL',
			   '`mdate` datetime NULL']
	columns += ['%s %s' % (quote(c.name), c.definition()) for c in plan.columns]
	columns += ['PRIMARY KEY (`rid`)',
				'FOREIGN KEY (`cuuid`) REFERENCES mp_clients(`cuuid`) ON DELETE CASCADE ON UPDATE NO ACTION']
	return 'CREATE TABLE IF NOT EXISTS %s (%s)' % (quote(plan.table), ', '.join(columns))


def _column_changes(plan, existing, log):
	"""ALTER clauses for new columns and for columns the data no longer fits. Never narrows."""
	changes = []
	for column in plan.columns:
		current = existing.get(column.name.lower())
		if current is None:
			changes.append('ADD COLUMN %s %s' % (quote(column.name), column.definition()))
			continue

		cur_type, cur_length = current
		widen = False
		if _is_string_type(column.data_type) and _is_string_type(cur_type):
			widen = _capacity(column.data_type, column.length) > _capacity(cur_type, cur_length)
		elif column.data_type in INT_TYPES and cur_type in INT_TYPES:
			widen = INT_TYPES.index(column.data_type) > INT_TYPES.index(cur_type)
		elif column.data_type != cur_type:
			log.warning('Column %s.%s is %s, data says %s. Leaving it as is.'
						% (plan.table, column.name, cur_type, column.data_type))

		if widen:
			changes.append('MODIFY COLUMN %s %s' % (quote(column.name), column.definition()))
	return changes


def _ensure_schema(plan, session, log):
	"""Create the table or add / widen columns. Returns True if the table was created."""
	exists = session.fetchall(
		"SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = %s",
		(plan.table,))
	if not exists:
		log.info('Create new table %s' % plan.table)
		session.execute(_create_table(plan))
		return True

	changes = _column_changes(plan, _existing_columns(session, plan.table), log)
	if changes:
		log.info('Updating table %s: %s' % (plan.table, ', '.join(changes)))
		session.execute('ALTER TABLE %s %s' % (quote(plan.table), ', '.join(changes)))
	return False


def _batches(items, size):
	for i in range(0, len(items), size):
		yield items[i:i + size]


def _insert_rows(plan, client_id, mdate, rows, session):
	"""INSERT the rows, rows with the same columns are inserted together."""
	groups = {}
	for row in rows:
		groups.setdefault(tuple(sorted(row)), []).append(row)

	for names, group in groups.items():
		sql = 'INSERT INTO %s (`cuuid`, `mdate`%s) VALUES (%s)' % (
			quote(plan.table), ''.join(', ' + quote(n) for n in names), ', '.join(['%s'] * (len(names) + 2)))
		for batch in _batches(group, BATCH_SIZE):
			session.executemany(sql, [(client_id, mdate) + tuple(r[n] for n in names) for r in batch])


def _upsert_rows(plan, client_id, mdate, rows, session):
	"""permanentRows: update the row that matches (cuuid plus checkFields), else insert it."""
	inserted = updated = 0
	for row in rows:
		keys = [c for c in plan.check_fields if c in row]
		where = ' AND '.join(['`cuuid` = %s'] + ['%s = %%s' % quote(c) for c in keys])
		where_params = (client_id,) + tuple(row[c] for c in keys)

		found = session.fetchall('SELECT 1 FROM %s WHERE %s LIMIT 1' % (quote(plan.table), where), where_params)
		if found:
			sets = ', '.join(['`mdate` = %s'] + ['%s = %%s' % quote(c) for c in row])
			session.execute('UPDATE %s SET %s WHERE %s' % (quote(plan.table), sets, where),
							(mdate,) + tuple(row.values()) + where_params)
			updated += 1
		else:
			_insert_rows(plan, client_id, mdate, [row], session)
			inserted += 1
	return inserted, updated


# MySQL error numbers by what they mean for an inventory load
_ERRNO_CATEGORIES = {
	'data_error': (1048, 1264, 1265, 1292, 1366, 1367, 1406),       # data doesn't fit the column
	'schema_limit': (1059, 1067, 1071, 1074, 1117, 1118, 1166),     # too many columns, row too big
	'unknown_client': (1452,),                                       # client ID is not in mp_clients
	'db_contention': (1205, 1213),                                   # lock wait timeout, deadlock
	'db_connection': (1040, 1053, 2002, 2003, 2006, 2013, 2055),    # can't reach / lost the database
	'db_permission': (1044, 1045, 1142, 1143, 1227),
}


def classify_error(exc):
	"""
	Why a load failed: returns (category, MySQL error number or None). Categories:
	invalid_payload, bad_file, file_error, lock_timeout, unknown_client, data_error,
	schema_limit, db_contention, db_connection, db_permission, db_error, unknown.
	"""
	if isinstance(exc, InventoryError):
		return 'invalid_payload', None
	if isinstance(exc, LockTimeout):
		return 'lock_timeout', None
	if isinstance(exc, (json.JSONDecodeError, UnicodeDecodeError)):
		return 'bad_file', None

	# Operating system errors also have a number first (ENOENT is 2), so they are told apart first
	if isinstance(exc, ConnectionError):
		return 'db_connection', None
	if isinstance(exc, OSError):
		return 'file_error', None

	# SQLAlchemy wraps the driver's error in .orig, pymysql errors carry the MySQL error number first
	orig = getattr(exc, 'orig', exc)
	errno = orig.args[0] if getattr(orig, 'args', None) and isinstance(orig.args[0], int) else None
	if errno is not None:
		for category, numbers in _ERRNO_CATEGORIES.items():
			if errno in numbers:
				return category, errno
		return 'db_error', errno

	return 'unknown', None


def process(plan, client_id, session, log=None, now=None):
	"""
	Store a validated inventory Plan for a client. Raises InventoryError for a bad client ID and
	lets database errors through (the transaction is rolled back). A raised error has an
	`inv_stage` attribute, 'schema' or 'load', telling where it happened.

	Schema changes run first (under a per table lock, MySQL commits them on their own), then the
	purge and inserts run in one transaction, so a failed load never leaves the client with no data.
	Returns {'created': bool, 'inserted': int, 'updated': int, 'purged': int, 'schema_ms': int,
	'load_ms': int}.
	"""
	log = log or _Log()
	if not isinstance(client_id, str) or not CLIENT_ID_RE.match(client_id):
		raise InventoryError('Invalid client ID.')
	if now is None:
		import datetime
		now = datetime.datetime.now()
	mdate = now.strftime('%Y-%m-%d %H:%M:%S')

	started = time.monotonic()
	lock = 'mpinv_' + hashlib.sha1(plan.table.encode('utf-8')).hexdigest()[:40]
	locked = False
	try:
		got = session.fetchall('SELECT GET_LOCK(%s, 60)', (lock,))
		if not got or got[0][0] != 1:
			raise LockTimeout('Timed out waiting to change table %s.' % plan.table)
		locked = True
		created = _ensure_schema(plan, session, log)
		session.commit()
	except Exception as e:
		session.rollback()
		e.inv_stage = 'schema'
		raise
	finally:
		if locked:
			try:
				session.fetchall('SELECT RELEASE_LOCK(%s)', (lock,))
			except Exception:
				pass    # the lock goes away with the connection
	schema_ms = int((time.monotonic() - started) * 1000)

	loading = time.monotonic()
	try:
		inserted = updated = purged = 0
		if plan.permanent_rows:
			inserted, updated = _upsert_rows(plan, client_id, mdate, plan.rows, session)
		else:
			if not created:
				purged = session.execute('DELETE FROM %s WHERE `cuuid` = %%s' % quote(plan.table), (client_id,))
				log.info('Purged %s rows in %s for %s.' % (purged, plan.table, client_id))
			_insert_rows(plan, client_id, mdate, plan.rows, session)
			inserted = len(plan.rows)
		session.commit()
	except Exception as e:
		session.rollback()
		e.inv_stage = 'load'
		raise

	log.info('%s: %d row(s) added, %d updated for %s.' % (plan.table, inserted, updated, client_id))
	return {'created': created, 'inserted': inserted, 'updated': updated, 'purged': purged or 0,
			'schema_ms': schema_ms, 'load_ms': int((time.monotonic() - loading) * 1000)}
