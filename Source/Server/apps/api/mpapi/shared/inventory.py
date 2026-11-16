"""
Inventory ingest for the API.

Large tables are not loaded during the web request: they are written to a file that
conf/scripts/MPInventoryD.py loads in the background. Only small tables (INVENTORY_PROCESS =
DB, or Hybrid and at most INVENTORY_HYBRID_ROWS_LIMIT rows) are loaded directly.

The validation and database work is in inventory_core.py, shared with MPInventoryD.py.
"""
import json
import os
from datetime import datetime

from flask import current_app, request

from mpapi.extensions import db
from mpapi.model import MpInvErrors, MpInvLog
from mpapi.mplogger import log_Info, log_Error, log_Debug, log_Warn
from mpapi.shared import inventory_core as core
from mpapi.shared.inventory_core import InventoryError

__all__ = ['storeInventory', 'stageInventory', 'InventoryError']


class _Log:
	info = staticmethod(log_Info)
	debug = staticmethod(log_Debug)
	error = staticmethod(log_Error)
	warning = staticmethod(log_Warn)


class _Session:
	"""inventory_core.Session on a SQLAlchemy connection (driver level SQL, %s placeholders)."""

	def __init__(self):
		self.conn = db.engine.connect()

	def execute(self, sql, params=None):
		return self.conn.exec_driver_sql(sql, params).rowcount if params else self.conn.exec_driver_sql(sql).rowcount

	def executemany(self, sql, rows):
		self.conn.exec_driver_sql(sql, rows)

	def fetchall(self, sql, params=None):
		return [tuple(r) for r in (self.conn.exec_driver_sql(sql, params) if params else self.conn.exec_driver_sql(sql)).fetchall()]

	def commit(self):
		self.conn.commit()

	def rollback(self):
		self.conn.rollback()

	def close(self):
		self.conn.close()


def _processDirect(client_id, inv):
	"""Load the table now. Returns (success, http code, message)."""
	plan = core.parse(inv)
	log_Info('Inventory for %s being processed directly to db.' % plan.table)

	session = _Session()
	try:
		core.process(plan, client_id, session, _Log)
		_recordLog(client_id, plan.table, error_no=0)
		return True, 201, ''
	except InventoryError:
		raise
	except Exception as e:
		log_Error('[Inventory][processDirect] Client: %s Table: %s Message: %s' % (client_id, plan.table, e))
		_recordLog(client_id, plan.table, error_no=1)
		_recordError(client_id, plan.table, inv)
		return False, 417, 'Error adding inventory.'
	finally:
		session.close()


def _stageFile(client_id, inv):
	"""Save the table as a .mpd file for MPInventoryD. Returns (success, http code, message)."""
	server_config = current_app.config['MP_SETTINGS']['server']
	if 'inventory_dir' not in server_config:
		log_Error('[Inventory] Inventory directory object not found in config.')
		return False, 412, 'Inventory directory object not found in config.'

	# Table, fields and client ID are checked here (cheap); the rows are checked when loaded.
	core.stamp_client(inv, client_id)

	file_dir = os.path.join(server_config['inventory_dir'], 'files')
	os.makedirs(file_dir, exist_ok=True)

	name = '%s_%s_%s.mpd' % (datetime.now().strftime('%Y%m%d%H%M%S'), inv['table'], client_id)
	path = os.path.join(file_dir, name)
	# Write then rename, MPInventoryD must not see a half written file
	with open(path + '.tmp', 'w') as outfile:
		json.dump(inv, outfile)
	os.replace(path + '.tmp', path)

	log_Info('[Inventory] Wrote inventory file (%s) to disk.' % name)
	return True, 201, ''


def stageInventory(client_id, inv):
	"""Always stage the payload for MPInventoryD (the v1 / v2 API). Returns (success, http code, message)."""
	try:
		if not isinstance(inv, dict) or not inv:
			return False, 400, 'No json data to parse'
		return _stageFile(client_id, inv)
	except InventoryError as e:
		log_Error('[Inventory] Client: %s Message: %s' % (client_id, e.message))
		return False, e.code, e.message


def storeInventory(client_id, inv):
	"""
	Store an inventory payload from an authenticated client, loading it now or staging it for
	MPInventoryD according to INVENTORY_PROCESS. Returns (success, http code, message).
	"""
	try:
		if not isinstance(inv, dict) or not inv:
			return False, 400, 'No json data to parse'

		key = inv.get('key')
		if key is not None and key != client_id:
			log_Warn('[Inventory] Payload key (%s) is not the authenticated client (%s). Using the client.'
					 % (key, client_id))

		mode = current_app.config['INVENTORY_PROCESS']
		if mode == 'DB':
			return _processDirect(client_id, inv)
		if mode == 'Hybrid':
			rows = inv.get('rows')
			if not isinstance(rows, list):
				return False, 400, 'Inventory rows are missing.'
			if len(rows) <= current_app.config['INVENTORY_HYBRID_ROWS_LIMIT']:
				return _processDirect(client_id, inv)
		elif mode != 'File':
			log_Error('Inventory processing type (%s) does not exist. Writing data to disk.' % mode)
		return _stageFile(client_id, inv)

	except InventoryError as e:
		log_Error('[Inventory] Client: %s Message: %s' % (client_id, e.message))
		if isinstance(inv, dict) and isinstance(inv.get('table'), str):
			_recordError(client_id, inv['table'][:100], '', e.message)
		return False, e.code, e.message


def _recordLog(client_id, table, error_no):
	db.session.add(MpInvLog(cuuid=client_id, mp_server=request.host, inv_table=table, error_no=error_no,
							error_msg='', json_data='', mdate=datetime.now()))
	db.session.commit()


def _recordError(client_id, table, inv, message='Error adding inventory.'):
	try:
		db.session.add(MpInvErrors(cuuid=client_id, inv_table=table, error_msg=message, json_data=inv,
								   mdate=datetime.now()))
		db.session.commit()
	except Exception as e:
		db.session.rollback()
		log_Error('[Inventory] Unable to record inventory error: %s' % e)
