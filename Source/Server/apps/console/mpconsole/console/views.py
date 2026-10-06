from flask import render_template, request, session
from sqlalchemy import desc, func, case
from werkzeug.security import generate_password_hash
import json
import re
import uuid
import requests

from datetime import datetime, timedelta
from hashlib import sha1, sha256

from .  import console
from mpconsole.app import db
from mpconsole.model import *
from mpconsole.modes import *
from mpconsole.mplogger import *
from mpconsole.app_decorators import login_required

''' Global '''

'''
	User/Admin Roles
'''
@console.route('/accounts')
@login_required
def accounts():
	_columns = [('user_id', 'User ID', '0'), ('user_type', 'User Type', '1'),
				('number_of_logins', 'No of Logins', '1'), ('last_login', 'Last Login', '1'), ('enabled', 'Enabled', '1')]

	_accounts = AdmUsersInfo.query.all()
	return render_template('admin/accounts.html', data=_accounts, columns=_columns)

''' AJAX Method '''
@console.route('/account/<user_id>',methods=['GET','POST','DELETE'])
@login_required
def deleteAdminAccount(user_id):
	if request.method == 'GET':
		_columns = [('user_id', 'User ID', '1'), ('user_type', 'User Type', '1'),
					('number_of_logins', 'No of Logins', '1'), ('last_login', 'Last Login', '1'), ('enabled', 'Enabled', '1')]

		_accounts = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
		if _accounts:
			return render_template('admin/account_update.html', data=_accounts, columns=_columns)
		else:
			return accounts()

	elif request.method == 'POST':
		data = request.form.to_dict()
		if adminRole():
			log("{} update account {} options.".format(session.get('user'), user_id))
			qAdm = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
			if qAdm is not None:
				for key, value in list(qAdm.asDict.items()):
					log("Orig: {} = {}".format(key, value))

				for key, value in list(data.items()):
					log("Updated: {} = {}".format(key, value))
					setattr(qAdm, key, value)

				db.session.commit()

		return accounts()

	elif request.method == 'DELETE':
		if adminRole():
			qAdm = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
			if qAdm is not None:
				if qAdm.user_type == 1:
					AdmUsers.query.filter(AdmUsers.user_id == user_id).delete()
				db.session.delete(qAdm)
				db.session.commit()

				log("{} deleted account {}.".format(session.get('user'), user_id))
			else:
				return json.dumps({'errorno': 404}), 404

		return json.dumps({'errorno': 0}), 200
	else:
		return json.dumps({'errorno': 0}), 200

@console.route('/account/<user_id>',methods=['GET'])
@login_required
def accountEdit(user_id):
	# TODO: Permissions
	_columns = [('user_id', 'User ID', '1'), ('user_type', 'User Type', '1'),
				('number_of_logins', 'No of Logins', '1'), ('last_login', 'Last Login', '1'), ('enabled', 'Enabled', '1')]

	_accounts = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _accounts:
		return render_template('admin/account_update.html', data=_accounts, columns=_columns)
	else:
		return accounts()

@console.route('/account/add',methods=['GET','POST'])
@login_required
def accountAdd():
	if request.method == 'GET':
		_columns = [('user_id', 'User ID', '0'), ('user_type', 'User Type', '1'), ('user_pass', 'User Password', '1'),
					('number_of_logins', 'No of Logins', '1'), ('last_login', 'Last Login', '1'), ('enabled', 'Enabled', '1')]

		return render_template('admin/account_update.html', data=[], columns=_columns)

	elif request.method == 'POST':
		data = request.form.to_dict()
		if adminRole() or localAdmin():
			usrAttrs = ['user_id','user_pass','enabled']
			usr	= AdmUsers()
			usrInf = AdmUsersInfo()
			for key, value in list(data.items()):
				if key != 'user_type':
					if key in usrAttrs:
						if key == 'user_pass':
							hash_pass = generate_password_hash(value)
							setattr(usr, key, hash_pass)
						else:
							setattr(usr, key, value)

					if key != 'user_pass':
						setattr(usrInf, key, value)

			setattr(usrInf, 'user_type', 1)
			db.session.add(usr)
			db.session.add(usrInf)
			db.session.commit()
			log("{} added user account {}.".format(session.get('user'), data['user_id']))

		return accounts()

'''
----------------------------------------------------------------
	Console
----------------------------------------------------------------
'''
@console.route('/admin')
@login_required
def admin():
	return render_template('blank.html', data={}, columns={})

@console.route('/tasks')
@login_required
def tasks():
	return render_template('console_tasks.html')

@console.route('/tasks/assignClientsToGroups',methods=['POST'])
@login_required
def assignClientsToDefaultGroup():
	if adminRole() or localAdmin():
		q_defaulGroup = MpClientGroups.query.filter(MpClientGroups.group_name == "default").first()
		if q_defaultGroup:
			defaultGroupID = q_defaultGroup.group_id
		else:
			return json.dumps({'error': 404, 'errormsg': 'Default group not found.'}), 404

		clients = MpClient.query.all()
		clientsInGroups = MpClientGroupMembers.query.all()

		for client in clients:
			if client.cuuid not in clientsInGroups:
				log("{} adding client {} to group {}.".format(session.get('user'), cuuid, defaultGroupID))
				addToGroup = MpClientGroupMembers()
				setattr(addToGroup, 'group_id', defaultGroupID)
				setattr(addToGroup, 'cuuid', client.cuuid)
				db.session.add(addToGroup)
				db.session.commit()

		return json.dumps({'error': 0}), 200

	else:
		log_Error("{} does not have permission to assign clients to group.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

'''
----------------------------------------------------------------
	Client Agents
----------------------------------------------------------------
'''
@console.route('/agent/deploy')
@login_required
def agentDeploy(tab=1):

	columns1 = [('puuid', 'puuid', '0'), ('type', 'Type', '0'), ('osver', 'OS Ver', '1'), ('agent_ver', 'Agent Ver', '1'),
			('version', 'Version', '1'), ('build', 'Build', '1'), ('pkg_name', 'Package', '1'), ('pkg_url', 'Package URL', '1'),
			('pkg_hash', 'Package Hash', '1'), ('active', 'Active', '1'), ('state', 'State', '1'), ('mdate', 'Mod Date', '1')]

	columns2 = [('rid', 'rid', '0'), ('type', 'Type', '0'), ('attribute', 'Attribute', '1'), ('attribute_oper', 'Operator', '1'),
			('attribute_filter', 'Filter', '1'), ('attribute_condition', 'Condition', '1')]

	groupResult = {}

	_curAgentID = 0
	qGet0 = MpClientAgent.query.filter(MpClientAgent.active == '1', MpClientAgent.type == 'app').first()
	if qGet0 is not None:
		_curAgentID = qGet0.puuid

	qGet1 = MpClientAgent.query.all()
	cListCols = MpClientAgent.__table__.columns
	# Sort the Columns based on "doc" attribute
	sortedCols = sorted(cListCols, key=getDoc)

	qGet2 = MpClientAgentsFilter.query.all()
	cListFiltersCols = MpClientAgentsFilter.__table__.columns
	# Sort the Columns based on "doc" attribute
	sortedFilterCols = sorted(cListFiltersCols, key=getDoc)

	_agents = []
	for v in qGet1:
		_row = {}
		for column, value in list(v.asDict.items()):
			if column != "cdate":
				if column == "active":
					_row[column] = "Yes" if value == 1 else "No"
				else:
					_row[column] = value

		_agents.append(_row)

	_filters = []
	for v in qGet2:
		_row = {}
		for column, value in list(v.asDict.items()):
			_row[column] = value

		_row['rid'] = v.rid
		_filters.append(_row)

	groupResult['Agents'] = {'data': _agents, 'columns': sortedCols}
	groupResult['Filters'] = {'data': _filters, 'columns': sortedFilterCols}
	groupResult['Admin'] = True

	return render_template('adm_agent_deploy.html', gResults=groupResult, agentCols=columns1, filterCols=columns2, selectedTab=tab, curAgentID=_curAgentID)

@console.route('/agents', methods=['GET'])
@login_required
def agentsList():

	columns = [('rid', 'rid', '0'),('puuid', 'puuid', '0'), ('type', 'Type', '0'), ('osver', 'OS Ver', '1'), ('agent_ver', 'Agent Ver', '1'),
			('version', 'Version', '1'), ('build', 'Build', '1'), ('pkg_name', 'Package', '1'), ('pkg_url', 'Package URL', '1'),
			('pkg_hash', 'Package Hash', '1'), ('active', 'Active', '1'), ('state', 'State', '0'), ('mdate', 'Mod Date', '1')]

	agents = MpClientAgent.query.all()

	_results = []
	for p in agents:
		row = {}
		for c in columns:
			y = "p."+c[0]
			row[c[0]] = eval(y)

		_results.append(row)

	return json.dumps({'data': _results, 'total': 0}, default=json_serial), 200

@console.route('/agents/update/<attr>', methods=['POST'])
@login_required
def agentUpdateAttr(attr):
	if adminRole() or localAdmin():
		key = request.form.get('pk')
		attrVal = request.form.get('value')

		agent = MpClientAgent.query.filter(MpClientAgent.rid == key).first()
		if agent is not None:
			# If active attr, disable all active columns, only 1 active is allowed per type
			if attr == 'active' and attrVal == '1':
				_type = agent.type
				for row in MpClientAgent.query.filter(MpClientAgent.type == _type).all():
					row.active = 0
					db.session.add(row)
					db.session.commit()

			setattr(agent, attr, attrVal)
			setattr(agent, 'mdate', datetime.now())

			log("{} setting {} active to {}.".format(session.get('user'), key, attrVal))
			db.session.commit()

		return json.dumps({'error': 0}), 200

	else:
		log_Error("{} does not have permission to update agent attrs.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

@console.route('/agent/filters', methods=['GET'])
@login_required
def agentsFiltersList():

	columns = [('rid', 'rid', '0'), ('type', 'Type', '0'), ('attribute', 'Attribute', '1'), ('attribute_oper', 'Operator', '1'),
			('attribute_filter', 'Filter', '1'), ('attribute_condition', 'Condition', '1')]

	agents = MpClientAgentsFilter.query.all()

	_results = []
	for p in agents:
		row = {}
		for c in columns:
			y = "p."+c[0]
			row[c[0]] = eval(y)

		_results.append(row)

	return json.dumps({'data': _results, 'total': 0}, default=json_serial), 200

@console.route('/agent/filter/<id>', methods=['GET'])
@login_required
def agentFilter(id):
	_filter = {}
	if id != 0:
		_filter = MpClientAgentsFilter.query.filter(MpClientAgentsFilter.rid == id).first()

	return render_template('agent_filter.html', data=_filter)

@console.route('/agent/filter/<id>', methods=['POST'])
@login_required
def agentFilterPost(id):
	if adminRole() or localAdmin():
		_form = request.form
		if int(id) == 0:
			# Add New
			_filter = MpClientAgentsFilter()
			setattr(_filter, 'type', 'app')
			setattr(_filter, 'attribute', _form['attribute'])
			setattr(_filter, 'attribute_oper', _form['attribute_oper'])
			setattr(_filter, 'attribute_filter', _form['attribute_filter'])
			setattr(_filter, 'attribute_condition', _form['attribute_condition'])

			log("{} adding new filter. {} {} {} {}.".format(session.get('user'), _form['attribute'], _form['attribute_oper'], _form['attribute_filter'], _form['attribute_condition']))
			db.session.add(_filter)

		else:
			# Update
			_filter = MpClientAgentsFilter.query.filter(MpClientAgentsFilter.rid == id).first()
			setattr(_filter, 'attribute', _form['attribute'])
			setattr(_filter, 'attribute_oper', _form['attribute_oper'])
			setattr(_filter, 'attribute_filter', _form['attribute_filter'])
			setattr(_filter, 'attribute_condition', _form['attribute_condition'])
			log("{} updated filter. {} {} {} {}.".format(session.get('user'), _form['attribute'], _form['attribute_oper'], _form['attribute_filter'], _form['attribute_condition']))

		db.session.commit()
		return json.dumps({'error': 0}), 200

	else:
		log_Error("{} does not have permission to update agent filter.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

@console.route('/agent/configure')
@login_required
def agentConfig():
	return render_template('console_tasks.html')

@console.route('/agent/deploy', methods=['DELETE'])
@login_required
def agentDeployRemove():
	if adminRole() or localAdmin():
		_filters = request.form['filters'].split(",")
		for f in _filters:
			q_remove = MpClientAgent.query.filter(MpClientAgent.puuid == str(f)).delete()
			if q_remove:
				log("{} removed agent {}.".format(session.get('user'), str(f)))
				db.session.commit()

		return json.dumps({'error': 0}), 200

	else:
		log_Error("{} does not have permission to delete agent.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

@console.route('/agent/deploy/filter', methods=['DELETE'])
@login_required
def agentDeployFilterRemove():
	if adminRole() or localAdmin():
		_filters = request.form['filters'].split(",")
		for f in _filters:
			q_rm = MpClientAgentsFilter.query.filter(MpClientAgentsFilter.rid == int(f)).first()
			if q_rm is not None:
				log("{} removed agent filter {} {} {}.".format(session.get('user'), q_rm.attribute, q_rm.attribute_oper, q_rm.attribute_filter ))
				db.session.delete(q_rm)
				db.session.commit()

		return json.dumps({'error': 0}), 200
	else:
		log_Error("{} does not have permission to delete agent filter.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

'''
----------------------------------------------------------------
	Agent plugins
----------------------------------------------------------------
'''

@console.route('/agent/plugins')
@login_required
def agentPluginsView():
	columns = [('rid', 'rid', '0'), ('pluginName', 'Name', '1'), ('pluginBundleID', 'Bundle ID', '1'),
				('pluginVersion', 'Version', '1'), ('hash', 'Hash', '1'), ('active', 'Enabled', '1')]

	return render_template('agent_plugins.html', data={}, columns=columns)

@console.route('/agent/plugins/list', methods=['GET'])
@login_required
def agentPluginsList():

	columns = [('rid', 'rid', '0'), ('pluginName', 'Name', '1'), ('pluginBundleID', 'Bundle ID', '1'),
				('pluginVersion', 'Version', '1'), ('hash', 'Hash', '1'), ('active', 'Enabled', '1')]

	plugins = MPPluginHash.query.order_by(MPPluginHash.pluginBundleID).order_by(desc(MPPluginHash.rid)).all()

	_results = []
	for p in plugins:
		row = {}
		for c in columns:
			y = "p."+c[0]
			row[c[0]] = eval(y)

		_results.append(row)

	return json.dumps({'data': _results, 'total': 0}, default=json_serial), 200

@console.route('/agent/plugins/<id>', methods=['GET'])
@login_required
def agentPluginsEdit(id):

	if id != 0:
		_filter = MPPluginHash.query.filter(MPPluginHash.rid == id).first()
	else:
		_filter = {}

	return render_template('agent_plugins_update.html', data=_filter)

@console.route('/agent/plugins/update', methods=['POST'])
@login_required
def agentPluginsUpdate():
	if adminRole() or localAdmin():
		_form = request.form
		isNew = False
		if _form['rid'] == '':
			isNew = True
			x = MPPluginHash()
		else:
			x = MPPluginHash.query.filter(MPPluginHash.rid == _form['rid']).first()

		setattr(x, 'pluginName', _form['pluginName'])
		setattr(x, 'pluginBundleID', _form['pluginBundleID'])
		setattr(x, 'pluginVersion', _form['pluginVersion'])
		setattr(x, 'hash', _form['hash'])
		setattr(x, 'active', _form['active'])

		if isNew:
			db.session.add(x)

		db.session.commit()

		return json.dumps({'error': 0}), 200
	else:
		log_Error("{} does not have permission to add/update agent plugin.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

@console.route('/agent/plugins', methods=['DELETE'])
@login_required
def agentPluginsRemove():
	if adminRole() or localAdmin():
		_rids = request.form['rid'].split(",")
		for r in _rids:
			q_remove = MPPluginHash.query.filter(MPPluginHash.rid == str(r)).delete()
			if q_remove:
				db.session.commit()

		return json.dumps({'error': 0}), 200
	else:
		log_Error("{} does not have permission to delete agent plugin.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

'''
----------------------------------------------------------------
	MacPatch Servers
----------------------------------------------------------------
'''
@console.route('/servers/mp')
@login_required
def mpServerView():
	columns = [('rid', 'rid', '0'), ('server', 'Server', '1'), ('port', 'Port', '1'), ('useSSL', 'Use SSL', '1'),
				('allowSelfSignedCert', 'Allow Self-Signed Cert', '1'),('isMaster', 'Master', '1'), ('isProxy', 'Proxy', '1'),
				('active', 'Enabled', '1')]

	return render_template('mp_servers.html', columns=columns)

@console.route('/servers/mp/list', methods=['GET'])
@login_required
def mpServersList():
	columns = [('rid', 'rid', '0'), ('server', 'Server', '1'), ('port', 'Port', '1'), ('useSSL', 'Use SSL', '1'),
				('allowSelfSignedCert', 'Allow Self-Signed Cert', '1'), ('isMaster', 'Master', '1'),
				('isProxy', 'Proxy', '1'),
				('active', 'Enabled', '1')]

	_servers = MpServer.query.all()

	_results = []
	for p in _servers:
		row = {}
		for c in columns:
			y = "p."+c[0]
			res = eval(y)
			if c[0] != 'rid':
				if res == 1:
					row[c[0]] = 'Yes'
				elif res == 0:
					row[c[0]] = 'No'
				else:
					row[c[0]] = res
			else:
				row[c[0]] = res

		_results.append(row)

	return json.dumps({'data': _results, 'total': 0}, default=json_serial), 200

@console.route('/servers/mp/<id>', methods=['GET'])
@login_required
def mpServerEdit(id):

	if id != 0:
		_filter = MpServer.query.filter(MpServer.rid == id).first()
	else:
		_filter = {}

	return render_template('mp_server_update.html', data=_filter)

@console.route('/servers/mp/update', methods=['POST', 'DELETE'])
@login_required
def mpServerUpdate():
	if adminRole() or localAdmin():
		_form = request.form
		if request.method == 'POST':
			isNew = False
			if _form['rid'] == '':
				isNew = True
				x = MpServer()
			else:
				x = MpServer.query.filter(MpServer.rid == _form['rid']).first()

			setattr(x, 'server', _form['server'])
			setattr(x, 'port', _form['port'])
			setattr(x, 'useSSL', _form['useSSL'])
			setattr(x, 'allowSelfSignedCert', _form['allowSelfSignedCert'])
			setattr(x, 'isMaster', _form['isMaster'])
			setattr(x, 'isProxy', _form['isProxy'])
			setattr(x, 'active', _form['active'])
			setattr(x, 'listid', '1')

			if isNew:
				db.session.add(x)
				log("{} added server {}.".format(session.get('user'), _form['server']))
			else:
				log("{} updated server {}.".format(session.get('user'), _form['server']))

			db.session.commit()
			updateServerRev()
			return json.dumps({'error': 0}), 200

		elif request.method == 'DELETE':

			x = MpServer.query.filter(MpServer.rid == _form['rid']).first()
			if x is not None:
				serverName = x.server
				db.session.delete(x)
				db.session.commit()
				updateServerRev()

			log("{} deleted server {}.".format(session.get('user'), serverName))
			return json.dumps({'error': 0}), 200
	else:
		log_Error("{} does not have permission to update or delete server.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

def updateServerRev():

	q = MpServerList.query.filter(MpServerList.listid == '1').first()
	if q is not None:
		setattr(q, 'version', q.version + 1)
	else:
		setattr(q, 'version', 1)
		db.session.add(q)

	db.session.commit()

@console.route('/servers/db/<server>/<port>', methods=['GET'])
@login_required
def mpServerDBConfig(server,port):

	_uuid = str(uuid.uuid4())
	dt  = datetime.now()
	dts = str((dt - datetime(1970, 1, 1)).total_seconds())
	srvHashStr = "{}{}{}".format(_uuid,dt,type).encode('utf-8')
	srvHash = sha1(srvHashStr).hexdigest()

	_data = []
	_url = "https://{}:{}/api/v1/db/config".format(server,port)
	#_url = "http://0.0.0.0:5000/api/v1/db/config".format(server,port) # For Testing
	headers = {'x-agent-id': '1', 'x-agent-ver': '99'}
	r = requests.get(_url, headers=headers, verify=False)
	if r.status_code == 200:
		rawData = json.loads(r.text)
		_data = rawData['result']

	return render_template('admin/mp_server_db_config.html', server=server, data=_data)

class logline(object):  # no instance of this class should be created

	def __init__(self):
		self.date = ''
		self.app = ''
		self.level = ''
		self.text = ''

	def parseLine(self,line):
		_date = line.split(",")
		self.date = _date[0]
		x = re.search(r'\[(.*?)\]\[(.*?)\]', line)
		self.app = x.group(1)
		self.level = x.group(2)
		self.text = line.split("---")[1]

	def printLine(self):
		row = {}
		row['date'] = self.date
		row['app'] = self.app
		row['level'] = self.level
		row['text'] = self.text
		return row

@console.route('/server/log/<server>/<type>', methods=['GET'])
@login_required
def serversLog(server,type):
	_uuid = str(uuid.uuid4())
	dt  = datetime.now()
	dts = str((dt - datetime(1970, 1, 1)).total_seconds())
	srvHashStr = "{}{}{}".format(_uuid,dt,type).encode('utf-8')
	srvHash = sha1(srvHashStr).hexdigest()

	qry = MpServerLogReq()
	setattr(qry, 'uuid', _uuid)
	setattr(qry, 'dts', dts)
	setattr(qry, 'type', type)
	db.session.add(qry)
	db.session.commit()

	_data = []
	_url = "https://{}:3600/api/v2/server/log/{}/{}/{}".format(server, _uuid, type, srvHash)
	r = requests.get(_url, verify=False)
	if r.status_code == 200:
		rawData = json.loads(r.text)
		_data = rawData['data']

	columns = [('date', 'Date', '1'), ('app', 'App', '1'), ('level', 'Level', '1'), ('text', 'Message', '1')]
	return render_template('logs.html', columns=columns, server=server, data=_data)

'''
----------------------------------------------------------------
	ASUS Servers
----------------------------------------------------------------
'''
@console.route('/servers/asus')
@login_required
def asusServersView():

	columns = [('rid', 'rid', '0'), ('catalog_url', 'Catalog URL', '1'), ('os_major', 'OS Major', '1'),
	('os_minor', 'OS Minor', '1'),('proxy', 'Proxy', '1'), ('active', 'Enabled', '1')]

	return render_template('asus_servers.html', columns=columns)

@console.route('/servers/asus/list', methods=['GET'])
@login_required
def asusServersList():

	columns = [('rid', 'rid', '0'), ('catalog_url', 'Catalog URL', '1'), ('os_major', 'OS Major', '1'),
			   ('os_minor', 'OS Minor', '1'),('proxy', 'Proxy', '1'), ('active', 'Enabled', '1')]

	_servers = MpAsusCatalog.query.order_by(desc(MpAsusCatalog.os_minor)).all()

	_results = []
	for p in _servers:
		row = {}
		for c in columns:
			y = "p."+c[0]
			res = eval(y)
			if c[0] == 'proxy' or c[0] == 'active':
				if res == 1:
					row[c[0]] = 'Yes'
				else:
					row[c[0]] = 'No'
			else:
				row[c[0]] = res

		_results.append(row)

	return json.dumps({'data': _results, 'total': 0}, default=json_serial), 200

@console.route('/servers/asus/<id>', methods=['GET'])
@login_required
def asusServerEdit(id):

	if id != 0:
		# columns = [('rid', 'rid', '0'), ('catalog_url', 'Catalog URL', '1'), ('os_major', 'OS Major', '1'),
		# ('os_minor', 'OS Minor', '1'),('proxy', 'Proxy', '1'), ('active', 'Enabled', '1')]
		_filter = MpAsusCatalog.query.filter(MpAsusCatalog.rid == id).first()
	else:
		_filter = {}

	return render_template('asus_server_update.html', data=_filter)

@console.route('/servers/asus/update', methods=['POST', 'DELETE'])
@login_required
def asusServerUpdate():
	if adminRole() or localAdmin():
		_form = request.form
		if request.method == 'POST':
			suServerURL = _form['catalog_url']
			isNew = False
			if _form['rid'] == '':
				isNew = True
				x = MpAsusCatalog()
			else:
				x = MpAsusCatalog.query.filter(MpAsusCatalog.rid == _form['rid']).first()

			setattr(x, 'catalog_url', suServerURL)
			setattr(x, 'os_major', _form['os_major'])
			setattr(x, 'os_minor', _form['os_minor'])
			setattr(x, 'proxy', _form['proxy'])
			setattr(x, 'active', _form['active'])
			setattr(x, 'catalog_group_name', 'Default')
			setattr(x, 'listid', '1')

			if isNew:
				db.session.add(x)
				log("{} added SU server {}.".format(session.get('user'), suServerURL))
			else:
				log("{} updated SU server {}.".format(session.get('user'), suServerURL))

			db.session.commit()
			updateASUSRev()

			return json.dumps({'error': 0}), 200

		elif request.method == 'DELETE':
			_rid = _form.get('rid')
			_rids = _rid.split(",")
			for r in _rids:
				x = MpAsusCatalog.query.filter(MpAsusCatalog.rid == r).first()
				if x is not None:
					log("{} deleted SU server {}.".format(session.get('user'), x.catalog_url))
					db.session.delete(x)
					db.session.commit()
					updateASUSRev()

			return json.dumps({'error': 0}), 200
	else:
		log_Error("{} does not have permission to add or delete SU server.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

def updateASUSRev():

	q = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == '1').first()
	if q is not None:
		setattr(q, 'version', q.version + 1)
	else:
		setattr(q, 'version', 1)
		db.session.add(q)

	db.session.commit()

'''
----------------------------------------------------------------
	DataSources
----------------------------------------------------------------
'''
@console.route('/server/datasources')
@login_required
def dataSourcesView():
	return render_template('datasources.html')

''' Global '''
def getDoc(col_obj):
	if col_obj.doc is None:
		return 0
	else:
		return col_obj.doc

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.strftime('%Y-%m-%d %H:%M:%S')
		return serial
	raise TypeError("Type not serializable")

'''
----------------------------------------------------------------
	Inventory Statistics
	What MPInventoryD did with the inventory files clients sent
----------------------------------------------------------------
'''
INV_STATS_PERIODS = (1, 7, 30, 120)

@console.route('/inventory/stats')
@login_required
def inventoryStats():
	if not adminRole():
		return render_template('403.html'), 403

	return render_template('admin/inventory_stats.html', periods=INV_STATS_PERIODS)

''' AJAX Method '''
@console.route('/inventory/stats/data')
@login_required
def inventoryStatsData():
	if not adminRole():
		return json.dumps({'errorno': 403}), 403

	try:
		days = min(max(int(request.args.get('days', 7)), 1), 3650)
	except ValueError:
		days = 7

	since = datetime.now() - timedelta(days=days)
	since_day = (datetime.now() - timedelta(days=days - 1)).date()

	def n(value):
		return int(value or 0)

	D, S = MpInvStatsDaily, MpInvStats
	ok = D.result == 'ok'

	# Loads per day, from the daily roll-up
	daily = {}
	for day, result, loads in (db.session.query(D.day, D.result, func.sum(D.loads))
							   .filter(D.day >= since_day).group_by(D.day, D.result).all()):
		d = daily.setdefault(str(day), {'day': str(day), 'ok': 0, 'failed': 0})
		d['ok' if result == 'ok' else 'failed'] += n(loads)

	# Totals per inventory table
	tables = []
	for r in (db.session.query(D.inv_table, func.sum(D.loads), func.sum(case((ok, D.loads), else_=0)),
							   func.sum(D.rows_inserted), func.sum(D.rows_updated), func.sum(D.rows_purged),
							   func.sum(D.file_bytes), func.sum(D.queued_ms_total), func.max(D.queued_ms_max),
							   func.sum(case((ok, D.load_ms_total), else_=0)), func.max(D.load_ms_max))
			  .filter(D.day >= since_day).group_by(D.inv_table).all()):
		loads, loaded = n(r[1]), n(r[2])
		tables.append({'inv_table': r[0] or '(unknown)', 'loads': loads, 'failed': loads - loaded,
					   'rows_inserted': n(r[3]), 'rows_updated': n(r[4]), 'rows_purged': n(r[5]),
					   'file_bytes': n(r[6]),
					   'avg_queued_ms': n(r[7]) // loads if loads else 0, 'max_queued_ms': n(r[8]),
					   'avg_load_ms': n(r[9]) // loaded if loaded else 0, 'max_load_ms': n(r[10])})
	tables.sort(key=lambda t: (-t['failed'], -t['loads']))

	loads = sum(t['loads'] for t in tables)
	failed = sum(t['failed'] for t in tables)
	loaded = loads - failed
	totals = {'loads': loads, 'failed': failed,
			  'success_rate': round(100.0 * loaded / loads, 1) if loads else None,
			  'rows_inserted': sum(t['rows_inserted'] for t in tables),
			  'rows_purged': sum(t['rows_purged'] for t in tables),
			  'file_bytes': sum(t['file_bytes'] for t in tables),
			  'avg_queued_ms': sum(t['avg_queued_ms'] * t['loads'] for t in tables) // loads if loads else 0,
			  'max_queued_ms': max([t['max_queued_ms'] for t in tables] or [0]),
			  'avg_load_ms': sum(t['avg_load_ms'] * (t['loads'] - t['failed']) for t in tables) // loaded if loaded else 0,
			  'max_load_ms': max([t['max_load_ms'] for t in tables] or [0])}

	# Why loads failed, grouped by cause and table (needs the per file rows, kept for a shorter time)
	causes = []
	for r in (db.session.query(S.result, S.inv_table, func.count(S.rid), func.count(func.distinct(S.cuuid)),
							   func.max(S.started), func.max(S.error_no), func.max(S.error_stage), func.max(S.error_msg))
			  .filter(S.started >= since, S.result != 'ok').group_by(S.result, S.inv_table)
			  .order_by(func.count(S.rid).desc()).all()):
		causes.append({'result': r[0], 'inv_table': r[1] or '(unknown)', 'failures': n(r[2]), 'clients': n(r[3]),
					   'last': r[4], 'error_no': r[5], 'error_stage': r[6], 'example': r[7]})

	recent = []
	for r in (S.query.filter(S.started >= since, S.result != 'ok').order_by(S.started.desc()).limit(100).all()):
		recent.append({'started': r.started, 'cuuid': r.cuuid, 'inv_table': r.inv_table, 'result': r.result,
					   'error_no': r.error_no, 'error_stage': r.error_stage, 'error_msg': r.error_msg,
					   'file_name': r.file_name, 'rows_received': n(r.rows_received), 'file_bytes': n(r.file_bytes)})

	return json.dumps({'days': days, 'since': since, 'totals': totals,
					   'daily': [daily[k] for k in sorted(daily)], 'tables': tables,
					   'causes': causes, 'recent': recent}, default=json_serial), 200
