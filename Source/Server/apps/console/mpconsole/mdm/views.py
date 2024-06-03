from flask import render_template, session, request, current_app
from flask_security import login_required
from flask_cors import cross_origin
from sqlalchemy import text, or_, desc
from datetime import datetime

import sys
import json
import humanize
import base64
from collections import OrderedDict

from .  import mdm
from mpconsole.app import db
from mpconsole.model import *
from mpconsole.modes import *
from mpconsole.mplogger import *
from mpconsole.mputil import *
from mpconsole.mptasks import MPIntune, MPTaskJobs


@mdm.route('/enrolledDevices')
@login_required
def enrolledDevices():
	_lastSyncAt = "None"
	columns = []
	try:
		_lastSync = MDMIntuneLastSync.query.filter( MDMIntuneLastSync.tableName == MDMIntuneDevices.__tablename__ ).order_by(desc(MDMIntuneLastSync.lastSyncDateTime)).first()
		if _lastSync is not None:
			_lastSyncAt = _lastSync.lastSyncDateTime

		listCols = MDMIntuneDevices.__table__.columns
	except:
		_lastSyncAt = "Error"

	return render_template('mdm/enrolled_devices.html', data=[], columns=listCols, lastSync=_lastSyncAt)

''' AJAX Request '''
@mdm.route('/enrolledDevices/list',methods=['GET'])
#@login_required
#@cross_origin()
def enrolledDevicesList():
	cols = []
	listCols = MDMIntuneDevices.__table__.columns
	devices = MDMIntuneDevices.query.all()

	for c in listCols:
		if c.info:
			cols.append(c.name)

	_results = []
	for r in devices:
		_dict = r.asDict
		_row = {}
		for col in cols:
			if col in _dict:
				if col == 'totalStorageSpaceInBytes' or col == 'freeStorageSpaceInBytes':
					_row[col] = humanize.naturalsize(_dict[col])
				else:
					_val = None
					if _dict[col] == 0:
						_val = "False"
					elif _dict[col] == 1:
						_val = "True"
					else:
						_val = _dict[col]

					_row[col] = _val
		_results.append(OrderedDict(sorted(_row.items())) )

	return json.dumps(_results, default=json_serial), 200

@mdm.route('/corporateDevices')
@login_required
def corporateDevices():
	_lastSyncAt = "None"
	columns = []
	try:
		_lastSync = MDMIntuneLastSync.query.filter( MDMIntuneLastSync.tableName == 'mdm_intune_corporate_devices' ).order_by(desc(MDMIntuneLastSync.lastSyncDateTime)).first()
		if _lastSync is not None:
			_lastSyncAt = _lastSync.lastSyncDateTime

		schemaColumns = current_app.config["MDM_SCHEMA"]["tables"]["mdm_intune_corporate_devices"]["columns"]
		columns = sorted(schemaColumns, key = lambda i: i['order'])

		joinCols = [{ "column": "cuuid", "displayName": "MP-ClientID", "order": 99,"visible": 0},{ "column": "hostname", "displayName": "MP-Hostname", "order": 99,"visible": 1}]
		columns = columns + joinCols

	except:
		_lastSyncAt = "Error"

	return render_template('mdm/corporate_devices.html', data=[], columns=columns, lastSync=_lastSyncAt)

''' AJAX Request '''
@mdm.route('/corporateDevices/list',methods=['GET'])
@login_required
@cross_origin()
def corporateDevicesList():
	cols = []
	listCols = MDMIntuneCorporateDevices.__table__.columns
	devices = MDMIntuneCorporateDevices.query.outerjoin(MpClient, MpClient.serialno == MDMIntuneCorporateDevices.importedDeviceIdentifier).add_columns(
														MpClient.cuuid, MpClient.hostname).all()

	for c in listCols:
		cols.append(c.name)

	_results = []
	for r in devices:
		_dict = r[0].asDict
		_row = {}
		for col in cols:
			if col in _dict:
				_row[col] = _dict[col]

		_row['cuuid'] = r.cuuid
		_row['hostname'] = r.hostname

		_results.append(OrderedDict(sorted(_row.items())) )

	return json.dumps(_results, default=json_serial), 200

@mdm.route('/corporateDevice/add',methods=['GET','POST'])
@login_required
def corporateDeviceAdd():
	if request.method == 'POST':
		_form = request.form
		mpTask = MPTaskJobs()
		mpTask.init_app(current_app)
		res = mpTask.AddCorporateDevice(_form['importedDeviceIdentifier'],_form['description'])
		return json.dumps({}, default=json_serial), 200

	else:
		schemaColumns = current_app.config["MDM_SCHEMA"]["tables"]["mdm_intune_corporate_devices"]["columns"]
		columns = sorted(schemaColumns, key = lambda i: i['order'])

		return render_template('mdm/corporate_devices_add.html', columns=columns)

@mdm.route('/corporateDevice/live/query',methods=['GET'])
@login_required
def corporateDeviceQueryForm():
	return render_template('mdm/corporate_device_query.html', columns={})

''' AJAX Request '''
''' Live Query '''
@mdm.route('/corporateDevice/query',methods=['GET'])
@login_required
@cross_origin()
def corporateDeviceQuery():
	_results = {}
	return json.dumps({'data': _results}, default=json_serial), 200

@mdm.route('/corporateDevice/search',methods=['POST'])
@login_required
def corporateDeviceSearch():

	_plain = []
	_dev = request.form['device'] + '%'
	client = MpClient.query.filter( or_( MpClient.computername.like(_dev) ) ).all()
	if client is not None and len(client) >= 1:
		for row in client:
			_plain.append(row.computername)

	return json.dumps({'options': _plain}, default=json_serial), 200

@mdm.route('/corporateDevice/search/host',methods=['POST'])
@login_required
def corporateDeviceSearchHost():
	_res = {}
	_dev = request.form['device']
	client = MpClient.query.filter(MpClient.computername == _dev).first()
	if client is not None:
			_res = {'cuuid':client.cuuid,'serialno':client.serialno}

	return json.dumps({'device': _res}, default=json_serial), 200

@mdm.route('/configProfiles')
@login_required
def configProfiles():
	_lastSyncAt = "None"
	columns = []
	try:
		_lastSync = MDMIntuneLastSync.query.filter( MDMIntuneLastSync.tableName == MDMIntuneConfigProfiles.__tablename__ ).order_by(desc(MDMIntuneLastSync.lastSyncDateTime)).first()
		if _lastSync is not None:
			_lastSyncAt = _lastSync.lastSyncDateTime

		schemaColumns = current_app.config["MDM_SCHEMA"]["tables"]["mdm_intune_devices_config_profiles"]["columns"]
		columns = sorted(schemaColumns, key = lambda i: i['order'])

	except:
		_lastSyncAt = "Error"

	return render_template('mdm/device_config_profiles.html', data=[], columns=columns, lastSync=_lastSyncAt)

''' AJAX Request '''
@mdm.route('/configProfiles/list',methods=['GET'])
@login_required
@cross_origin()
def configProfilesList():
	cols = []
	listCols = MDMIntuneConfigProfiles.__table__.columns
	devices = MDMIntuneConfigProfiles.query.all()

	for c in listCols:
		#if c.info:
		cols.append(c.name)

	_results = []
	for r in devices:
		_dict = r.asDictWithRID
		_row = {}
		for col in cols:
			if col in _dict:
				_row[col] = _dict[col]

		_results.append(OrderedDict(sorted(_row.items())) )

	return json.dumps(_results, default=json_serial), 200

@mdm.route('/configProfiles/payload/<string:id>',methods=['GET'])
@login_required
@cross_origin()
def deviceConfigProfilePayload(id):
	payload = None
	profile = MDMIntuneConfigProfiles.query.filter( MDMIntuneConfigProfiles.id == id ).first()
	if profile is not None:
		_profile = profile.asDict
		payload_b64 = _profile['payload']
		message_bytes = base64.b64decode(payload_b64)
		payload = message_bytes.decode()

	return render_template('mdm/device_config_profile_payload.html', payload=payload)

@mdm.route('/runSync/<string:id>',methods=['GET'])
@login_required
@cross_origin()
def runIntuneDataSync(id):
	_lastSyncAt = "Error getting sync data."
	tasks = MPTaskJobs()
	tasks.init_app(current_app,session['user'])
	try:
		if id == "corporateDevices":
			tasks.GetCorpDevices()
			_lastSync = MDMIntuneLastSync.query.filter( MDMIntuneLastSync.tableName == 'mdm_intune_corporate_devices' ).order_by(desc(MDMIntuneLastSync.lastSyncDateTime)).first()
		elif id == "enrolledDevices":
			log("id == enrolledDevices")
			tasks.GetEnrolledDevices()
			log("enrolledDevices done")
			_lastSync = MDMIntuneLastSync.query.filter( MDMIntuneLastSync.tableName == MDMIntuneDevices.__tablename__ ).order_by(desc(MDMIntuneLastSync.lastSyncDateTime)).first()
			log("_lastSync done")
		elif id == "deviceProfiles":
			tasks.GetDeviceConfigProfiles()
			_lastSync = MDMIntuneLastSync.query.filter( MDMIntuneLastSync.tableName == MDMIntuneConfigProfiles.__tablename__ ).order_by(desc(MDMIntuneLastSync.lastSyncDateTime)).first()

		if _lastSync is not None:
			_lastSyncAt = _lastSync.lastSyncDateTime

		return json.dumps({'lastSync': _lastSyncAt}, default=json_serial), 200
	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		message=str(e.args[0]).encode("utf-8")
		log_Error('[runIntuneDataSync][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
		return json.dumps({'lastSync': _lastSyncAt}, default=json_serial), 401

@mdm.route('/groups',methods=['GET'])
@login_required
@cross_origin()
def getMDMGroups():
	columns = []
	try:
		schemaColumns = current_app.config["MDM_SCHEMA"]["tables"]["mdm_intune_groups"]["columns"]
		columns = sorted(schemaColumns, key=lambda i: i['order'])

	except:
		_lastSyncAt = "Error"

	return render_template('mdm/mdm_groups.html', data=[], columns=columns)

''' AJAX Request '''
@mdm.route('/groups/list',methods=['GET'])
@login_required
@cross_origin()
def getMDMGroupsList():
	_results = []

	schemaColumns = current_app.config["MDM_SCHEMA"]["tables"]["mdm_intune_groups"]["columns"]
	columns = sorted(schemaColumns, key=lambda i: i['order'])

	mpi = MPIntune()
	mpi.init_app(current_app)
	groups = mpi.GetGroups()

	for group in groups:
		_row = {}
		for c in columns:
			_row[c['column']] = group[c['column']]

		_results.append(_row)

	return json.dumps({'data': _results}, default=json_serial), 200


@mdm.route('/groups/members/<string:id>',methods=['GET'])
@login_required
@cross_origin()
def getMDMGroupsMembers(id):
	columns = []
	groupName = "ERR"
	mpi = MPIntune()
	mpi.init_app(current_app)
	groupName = mpi.GetGroup(id)

	try:

		schemaColumns = current_app.config["MDM_SCHEMA"]["tables"]["mdm_intune_group_membership"]["columns"]
		columns = sorted(schemaColumns, key=lambda i: i['order'])

	except:
		_lastSyncAt = "Error"

	return render_template('mdm/mdm_group_membership.html', data=[], groupid=id, groupname=groupName, columns=columns)


@mdm.route('/groups/members/<string:id>/list',methods=['GET'])
@login_required
@cross_origin()
def getMDMGroupsMembersList(id):
	_results = []

	schemaColumns = current_app.config["MDM_SCHEMA"]["tables"]["mdm_intune_group_membership"]["columns"]
	columns = sorted(schemaColumns, key=lambda i: i['order'])

	mpi = MPIntune()
	mpi.init_app(current_app)
	groups = mpi.GetGroupMembers(id)

	for group in groups:
		_row = {}
		for c in columns:
			_row[c['column']] = group[c['column']]

		_results.append(_row)

	print(_results)
	return json.dumps({'data': _results}, default=json_serial), 200

@mdm.route('/groups/members/<string:groupid>/<string:deviceid>',methods=['DELETE'])
@login_required
@cross_origin()
def deleteMDMGroupsMember(groupid, deviceid):
	print("deleteMDMGroupsMember")
	mpi = MPIntune()
	mpi.init_app(current_app)
	groups = mpi.DeleteMemberFromGroup(groupid,deviceid)

	return json.dumps({'data': {}}, default=json_serial), 200