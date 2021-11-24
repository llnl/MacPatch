from flask import render_template, request
from flask_login import login_required, current_user
from sqlalchemy import text
from datetime import datetime, timedelta
from operator import itemgetter
from flask_cors import cross_origin

import json
import os
import humanize

from . import maint
from .. import login_manager
from .. import db
from ..model import *

from .. modes import *
from .. mputil import *


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
def maitPatchesDelete():
	form = request.form
	ids = request.form['patches']
	files = ids.split(',')

	if not localAdmin() and not adminRole():
		log_Error("{} does not have permission to delete custom patch(s).".format(session.get('user')))
		return json.dumps({'data': {}}), 403

	for file in files:
		if os.path.exists(file):
			try:
				if '/opt/MacPatch/Content/Web/patches' in file:
					log_Info("Removing file {}".format(file))
					os.remove(file)
				else:
					log_Error("Unacceptable file path {}".fomat(file))
					return json.dumps({'data': {}}), 417

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


@maint.route('/mpi/extensions')
@login_required
def extensions():
	result = []
	_clients = []
	_ext_clients = []
	clients = MpClient.query.all()
	for x in clients:
		_clients.append(x.cuuid)

	sql = text("SELECT Distinct cuuid from mpi_SPExtensions")
	_sql_result = db.engine.execute(sql)
	for r in _sql_result:
		_row = dict(r)
		_ext_clients.append(_row['cuuid'])

	result = set(_ext_clients).difference(_clients)

	return render_template('maint/maint.html', data=result, count=len(result))

@maint.route('/mpi/extensions/purge')
@login_required
def extensions_p():
	result = []
	_clients = []
	_ext_clients = []
	clients = MpClient.query.all()
	for x in clients:
		_clients.append(x.cuuid)

	sql = text("SELECT Distinct cuuid from av_info")
	_sql_result = db.engine.execute(sql)
	for r in _sql_result:
		_row = dict(r)
		_ext_clients.append(_row['cuuid'])

	result = set(_ext_clients).difference(_clients)
	x = 0
	for c in result:
		x = x + 1
		sql = text("Delete from av_info Where cuuid = '" + c +"'")
		print(sql)

		_sql_result = db.engine.execute(sql)


	return render_template('maint/maint.html', data=result, count=len(result))
