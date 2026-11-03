from flask import render_template, request, session, current_app
from sqlalchemy import select, Table, MetaData
from sqlalchemy.exc import NoSuchTableError

import json
import os
import humanize

from . import maint
from mpconsole.app import db, login_manager
from mpconsole.model import *
from mpconsole.modes import *
from mpconsole.mputil import *
from mpconsole.app_decorators import login_required

@maint.route('/maint')
@login_required
def index():
	result = []
	qSW = MpSoftware.query.all()

	for s in qSW:
		files = getFilesInDirToRemove(s.sw_path)
		if len(files) >= 1:
			row = {}
			row['name'] = s.sName
			row['pkgPath'] = s.sw_path
			files = getFilesInDirToRemove(s.sw_path)
			row['rmFiles'] = files
			result.append(row)

	return render_template('maint/maint.html', data=result)

@maint.route('/patches')
@login_required
def index_patches():
	result = []
	qSW = MpPatch.query.all()

	_clistCols = ['name', 'pkgPath', 'rmFile', 'size']
	for s in qSW:
		files = getFilesInDirToRemoveAsDict(s.pkg_path)
		if len(files) >= 1:
			for f in files:
				row = {}
				row['name'] = s.patch_name
				row['pkgPath'] = s.pkg_path
				row['rmFile'] = f['file']
				row['size'] = f['size']
				result.append(row)

	return render_template('maint/patches.html', data=result, columns=_clistCols)

''' AJAX Request '''
@maint.route('/patches/list',methods=['GET'])
@login_required
def maitPatchesList():
	result = []
	qSW = MpPatch.query.all()

	for s in qSW:
		files = getFilesInDirToRemoveAsDict(s.pkg_path)
		if len(files) >= 1:
			for f in files:
				row = {}
				row['name'] = s.patch_name
				row['pkgPath'] = s.pkg_path
				row['rmFile'] = f['file']
				row['size'] = f['size']
				result.append(row)

	_clist = MpPatch.query.order_by(MpPatch.mdate.desc()).all()
	_clistCols = ['name', 'pkgPath', 'rmFile', 'size']

	return json.dumps({'data': result}), 200

''' AJAX Request '''
@maint.route('/patches/delete',methods=['DELETE'])
@login_required
def maitPatchesDelete():
	form = request.form
	ids = request.form['patches']
	files = ids.split(',')

	if not localAdmin() and not adminRole():
		log_Error("{} does not have permission to delete custom patch(s).".format(session.get('user')))
		return json.dumps({'data': {}}), 403

	for file in files:
		# Only allow removing files inside the patch content directory
		if not isPathWithin(file, current_app.config['PATCH_CONTENT_DIR']):
			log_Error("{} unacceptable file path {}".format(session.get('user'), file))
			return json.dumps({'data': {}}), 417

		if os.path.isfile(file):
			try:
				log_Info("{} removing file {}".format(session.get('user'), file))
				os.remove(file)

			except OSError as error:
				log_Error("Error removing file {}".format(file))
				return json.dumps({'data': {}}), 406

	return json.dumps({'data': {}}), 200

def getFilesInDirToRemove(sw_path):
	files = []
	if sw_path is not None:
		if os.path.exists(sw_path):
			_files = []
			path = os.path.dirname(sw_path)
			print(path)
			files = os.listdir(path)
			for f in files:
				fullFileName = os.path.join(path, f)
				if fullFileName == sw_path:
					continue
				elif ".png" in f:
					continue
				elif ".jpg" in f:
					continue
				elif ".gif" in f:
					continue
				_fileInfo = "{} {}".format(fullFileName,humanize.naturalsize(os.path.getsize(fullFileName)))
				_files.append(_fileInfo)

			files = _files

	return files

def getFilesInDirToRemoveAsDict(sw_path):
	files = []
	if sw_path is not None:
		if os.path.exists(sw_path):
			_files = []
			path = os.path.dirname(sw_path)
			files = os.listdir(path)
			for f in files:
				fullFileName = os.path.join(path, f)
				if fullFileName == sw_path:
					continue
				elif ".png" in f:
					continue
				elif ".jpg" in f:
					continue
				elif ".gif" in f:
					continue
				_fileInfo = {"file":fullFileName, "size":humanize.naturalsize(os.path.getsize(fullFileName))}
				_files.append(_fileInfo)

			files = _files

	return files


'''
	Orphaned client data, rows for clients that no longer exist in mp_clients
'''
ORPHAN_TABLES = ('mpi_SPExtensions', 'av_info')

def orphanTable(name):
	# Inventory (mpi_) tables are created by the API, they have no model. Returns None if the table does not exist.
	try:
		return Table(name, MetaData(), autoload_with=db.engine)
	except NoSuchTableError:
		return None

def orphanedClientIDs(table):
	clients = MpClient.__table__
	query = select(table.c.cuuid).distinct() \
		.select_from(table.outerjoin(clients, clients.c.cuuid == table.c.cuuid)) \
		.where(clients.c.cuuid.is_(None))
	return sorted(r[0] for r in db.session.execute(query))

def orphans():
	# Returns {table name: [cuuid, ...]} for each orphan table that exists
	result = {}
	for name in ORPHAN_TABLES:
		table = orphanTable(name)
		if table is not None:
			result[name] = orphanedClientIDs(table)
	return result

@maint.route('/mpi/extensions')
@login_required
def extensions():
	if not adminRole():
		return render_template('error.html', error=403, message='You do not have permission to view this page.'), 403

	data = orphans()
	return render_template('maint/maint.html', data=data, count=sum(len(v) for v in data.values()))

@maint.route('/mpi/extensions/purge', methods=['POST'])
@login_required
def extensions_p():
	if not adminRole():
		log_Error("{} does not have permission to purge orphaned client data.".format(session.get('user')))
		return render_template('error.html', error=403, message='You do not have permission to purge orphaned client data.'), 403

	data = {}
	for name in ORPHAN_TABLES:
		table = orphanTable(name)
		if table is None:
			continue

		ids = orphanedClientIDs(table)
		if ids:
			db.session.execute(table.delete().where(table.c.cuuid.in_(ids)))
			log_Info("{} purged orphaned rows for {} client(s) from {}".format(session.get('user'), len(ids), name))
		data[name] = ids

	db.session.commit()
	return render_template('maint/maint.html', data=data, count=sum(len(v) for v in data.values()), purged=True)
