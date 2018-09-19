from flask import render_template, session, request, current_app, redirect, url_for
from flask_security import login_required
from sqlalchemy import text
from datetime import datetime
import json
import uuid

from .  import registration
from .. import login_manager
from .. import db
from .. model import *
from .. modes import *
from .. mplogger import *

'''
----------------------------------------------------------------
'''
@registration.route('/')
@login_required
def index():

	_keyCols = []
	_regClientCols = []
	_prkClientCols = []
	qKeyCols = MpRegKeys.__table__.columns
	for col in qKeyCols:
		_keyCols.append({'name':col.name, 'label': col.info})

	qRegCols = MPAgentRegistration.__table__.columns
	for col in qRegCols:
		if 'Key' not in col.name:
			_regClientCols.append({'name':col.name, 'label': col.info})

	# Add Group Name Col
	_regClientCols.insert(4,{'name': 'group_name', 'label': 'Client Group'})

	qPrkCols = MpClientsWantingRegistration.__table__.columns
	for col in qPrkCols:
		_prkClientCols.append({'name':col.name, 'label': col.info})

	qGetSettings = MpClientsRegistrationSettings.query.first()

	return render_template('registration.html', data={}, columns={}, group_name='name', group_id='name',
						selectedTab=1,
						settings=qGetSettings,
						keyCols=_keyCols, regCols=_regClientCols, prkClientCols=_prkClientCols)

# JSON
@registration.route('/settings',methods=['POST'])
@login_required
def settings():
	data = request.form.to_dict()
	autoreg = request.form.get('autoreg')
	client_parking = request.form.get('client_parking')

	qGet = MpClientsRegistrationSettings.query.first()
	if qGet is not None:
		setattr(qGet, 'autoreg', autoreg)
		setattr(qGet, 'client_parking', client_parking)
		db.session.commit()

	return json.dumps({}), 200

# JSON
@registration.route('/keys')
@login_required
def keys():

	_results = []
	_columns = []
	qCols = MpRegKeys.__table__.columns
	qGet = MpRegKeys.query.filter_by(active=1).all()

	for col in qCols:
		_columns.append({'name':col.name, 'label': col.info})

	for x in qGet:
		_results.append(x.asDictWithRID)

	return json.dumps({'data': _results, 'total': 0}, default=json_serial), 200

# JSON
@registration.route('/clients')
@login_required
def clients():
	_results = []
	qGetGrps = MpClientGroups.query.all()
	qGet = MPAgentRegistration.query.join(MpClientGroupMembers, MpClientGroupMembers.cuuid == MPAgentRegistration.cuuid).add_columns(MpClientGroupMembers.group_id).all()

	_groups = []
	for g in qGetGrps:
		_groups.append({'group_id':g.group_id,'group_name':g.group_name})

	for x in qGet:
		d = x[0].asDictWithRID
		# Remove Keys, dont want this data handed back
		d.pop('pubKeyPem', None)
		d.pop('clientKey', None)
		d.pop('pubKeyPemHash', None)
		d['group_name'] = searchForGroup(x[1], _groups)
		_results.append(d)

	return json.dumps({'data': _results, 'total': len(_results)}, default=json_serial), 200

def searchForGroup(group, list):
	res = (item for item in list if item["group_id"] == group).next()
	return res['group_name']

# JSON
@registration.route('/registered/client/<client_id>',methods=['DELETE'])
@login_required
def editClients(client_id):
	if request.method == 'DELETE':
		qKey = MPAgentRegistration.query.filter(MPAgentRegistration.cuuid == client_id).first()
		db.session.delete(qKey)
		db.session.commit()

		return json.dumps({}), 200
	else:
		return json.dumps({}), 404

# Inline Update of registered client - Enabled
# JSON
@registration.route('/registered/client/state',methods=['POST'])
@login_required
def stateClient():

	key = request.form.get('pk')
	name = request.form.get('name')
	value = request.form.get('value')

	qGet = MPAgentRegistration.query.filter(MPAgentRegistration.cuuid == key).first()
	if qGet is not None:
		setattr(qGet, name, value)
		db.session.commit()

	return json.dumps({'data': [], 'total': 0}, default=json_serial), 200

# JSON
@registration.route('/parked')
@login_required
def parked():
	_results = []
	_columns = []
	qCols = MpClientsWantingRegistration.__table__.columns
	qGet = MpClientsWantingRegistration.query.all()

	for col in qCols:
		_columns.append({'name':col.name, 'label': col.info})

	for x in qGet:
		_results.append(x.asDictWithRID)

	return json.dumps({'data': _results, 'total': 0}, default=json_serial), 200

@registration.route('/key/add',methods=['GET','POST'])
@login_required
def addKey():
	if request.method == 'GET':
		return render_template('registration_key.html', data={})
	else:
		data = request.form.to_dict()
		if data['rid'] == '0':
			key = MpRegKeys()
			for i in data.keys():
				setattr(key, i, data[i])

			setattr(key, 'regKey', str(uuid.uuid4()))
			db.session.add(key)

		else:
			key = MpRegKeys.query.filter(MpRegKeys.rid == data['rid']).first()
			if key is not None:
				for i in data.keys():
					setattr(key, i, data[i])

		db.session.commit()
		return json.dumps({}), 200

@registration.route('/key/edit/<rid>',methods=['GET','POST','DELETE'])
@login_required
def editKey(rid):
	if request.method == 'GET':
		qKey = MpRegKeys.query.filter(MpRegKeys.rid == rid).first()
		return render_template('registration_key.html', data=qKey)

	elif request.method == 'DELETE':
		qKey = MpRegKeys.query.filter(MpRegKeys.rid == rid).first()
		db.session.delete(qKey)
		db.session.commit()

		return json.dumps({}), 200
	else:
		data = request.form.to_dict()
		if data['rid'] == '0':
			key = MpRegKeys()
			for i in data.keys():
				setattr(key, i, data[i])

			setattr(key, 'regKey', str(uuid.uuid4()))
			db.session.add(key)

		else:
			key = MpRegKeys.query.filter(MpRegKeys.rid == data['rid']).first()
			if key is not None:
				for i in data.keys():
					setattr(key, i, data[i])

		db.session.commit()
		return json.dumps({}), 200

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.strftime('%Y-%m-%d %H:%M:%S')
		return serial
	raise TypeError("Type not serializable")
