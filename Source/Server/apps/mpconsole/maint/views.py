from flask import render_template
from flask_login import login_required, current_user
from sqlalchemy import text
from datetime import datetime, timedelta
from operator import itemgetter

import json
import os
import humanize

from . import maint
from .. import login_manager
from .. import db
from ..model import *


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


def getFilesInDirToRemove(sw_path):
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
				_fileInfo = "{} {}".format(fullFileName,humanize.naturalsize(os.path.getsize(fullFileName)))
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

	sql = text("SELECT Distinct cuuid from mpi_SPExtensions")
	_sql_result = db.engine.execute(sql)
	for r in _sql_result:
		_row = dict(r)
		_ext_clients.append(_row['cuuid'])

	result = set(_ext_clients).difference(_clients)

	for c in result:
		sql = text("Delete from mpi_SPExtensions Where cuuid = '" + c +"'")
		_sql_result = db.engine.execute(sql)


	return render_template('maint/maint.html', data=result, count=len(result))
