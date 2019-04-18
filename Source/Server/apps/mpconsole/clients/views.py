from flask import render_template, session, request, current_app, redirect, url_for
from flask_security import login_required
from sqlalchemy import text
from datetime import datetime
import json
import uuid
import os
import os.path
import sys
from operator import itemgetter

from .  import clients
from .. import login_manager
from .. import db
from .. model import *
from .. modes import *
from .. mplogger import *


'''
----------------------------------------------------------------
'''
@clients.route('')
@login_required
def clientsList():
	cListColNames = [{'name':'cuuid', 'label':'CUUID'},{'name': 'client_group', 'label': 'Client Group'},
					{'name':'hostname','label':'Host Name'},{'name':'computername','label':'Computer Name'},
					{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
					{'name':'ipaddr','label':'IP Address'}, {'name':'macaddr','label':'MAC Address'},
					{'name': 'serialno', 'label': 'Serial No'},{'name': 'fileVaultStatus', 'label': 'FileVault'},
					{'name': 'firmwareStatus', 'label': 'Firmware'},{'name':'osver','label':'OS Ver'},
					{'name':'consoleuser','label':'Console User'},{'name':'needsreboot','label':'Needs Reboot'},
					{'name':'client_version','label':'Client Ver'}, {'name':'mdate','label':'Mod Date'}]

	return render_template('clients.html', cData=[], columns=[], colNames=cListColNames)

# JSON Routes
# This method is called by clients.html for a list of clients
# This is done so that the refresh can be used
@clients.route('/list')
@login_required
def clientsListJSON():
	_results = []
	clients = MpClient.query.outerjoin(MpClientGroupMembers, MpClientGroupMembers.cuuid == MpClient.cuuid).add_columns(MpClientGroupMembers.group_id).outerjoin(
		MPIDirectoryServices, MPIDirectoryServices.cuuid == MpClient.cuuid).add_columns(MPIDirectoryServices.mpa_ADDomain, MPIDirectoryServices.mpa_distinguishedName).all()
	clientGroups = MpClientGroups.query.all()


	colNames = [{'name':'cuuid', 'label':'CUUID'},{'name': 'client_group', 'label': 'Client Group'},
					{'name':'hostname','label':'Host Name'},{'name':'computername','label':'Computer Name'},
					{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
					{'name':'ipaddr','label':'IP Address'}, {'name':'macaddr','label':'MAC Address'},
					{'name': 'serialno', 'label': 'Serial No'},{'name': 'fileVaultStatus', 'label': 'FileVault'},
					{'name': 'firmwareStatus', 'label': 'Firmware'},{'name':'osver','label':'OS Ver'},
					{'name':'consoleuser','label':'Console User'},{'name':'needsreboot','label':'Needs Reboot'},
					{'name':'client_version','label':'Client Ver'}, {'name':'mdate','label':'Mod Date'}]

	_groups = []
	for g in clientGroups:
		_groups.append({'group_id': g.group_id, 'group_name': g.group_name})

	for c in clients:
		_dict = c[0].asDict
		_dict['client_group'] = ''
		_client_group = searchForGroup(c[1], _groups)
		if _client_group is not None:
			_dict['client_group'] = _client_group
		_dict['addomain'] = c.mpa_ADDomain
		_dict['addn'] = c.mpa_distinguishedName
		_results.append(_dict)


	return json.dumps({'data': _results}, default=json_serial), 200

# Helper method to find a group in a list
def searchForGroup(group, list):
	if group is None:
		return "NA"
	res = (item for item in list if item["group_id"] == group).next()
	if res['group_name']:
		return res['group_name']
	else:
		return None
'''
----------------------------------------------------------------
	Client - dashboard
----------------------------------------------------------------
'''
@clients.route('/dashboard/<client_id>')
@login_required
def clientsInfo(client_id):
	qGet = MpClient.query.filter(MpClient.cuuid == client_id).first()
	rCols = [('patch', 'Patch'),('description', 'Description'),('restart', 'Reboot'),('mdate',' Days Needed')]

	return render_template('client_dashboard.html', cData=qGet, columns={'rPatchCols': rCols}, client_id=client_id, invTypes=inventoryTypes())

# JSON Routes
@clients.route('/dashboard/required/<client_id>')
@login_required
def clientRequiredPatches(client_id):

	now = datetime.now()
	columns = [('patch', 'Patch'),('description', 'Description'),('restart', 'Reboot'),('type', 'Type'),('mdate', 'Days Needed')]

	qApple = MpClientPatchesApple.query.filter(MpClientPatchesApple.cuuid == client_id).all()
	qThird = MpClientPatchesThird.query.filter(MpClientPatchesThird.cuuid == client_id).all()

	_results = []
	for p in qApple:
		row = {}
		for c, t in columns:
			y = "p."+c
			if c == 'mdate':
				row[c] = daysFromDate(now, eval(y))
			elif c == 'restart':
				if eval(y)[0] == 'Y':
					row[c] = 'Yes'
				else:
					row[c] = 'No'
			else:
				row[c] = eval(y)

		row['type'] = 'Apple'
		_results.append(row)

	for p in qThird:
		row = {}
		for c, t in columns:
			y = "p."+c
			if c == 'mdate':
				row[c] = daysFromDate(now, eval(y))
			elif c == 'restart':
				if eval(y)[0] == 'Y':
					row[c] = 'Yes'
				else:
					row[c] = 'No'
			else:
				row[c] = eval(y)

		row['type'] = 'Third'
		_results.append(row)

	_columns = []
	for c, t in columns:
		row = {}
		row['field'] = c
		row['title'] = t
		row['sortable'] = 'true'
		_columns.append(row)

	return json.dumps({'data':_results, 'columns': _columns}), 200

# JSON Routes
@clients.route('/dashboard/installed/<client_id>')
@login_required
def clientInstalledPatches(client_id):

	columns = [('patch_name', 'Patch'),('type', 'Type'),('mdate', 'Installed On')]
	query = MpInstalledPatch.query.filter(MpInstalledPatch.cuuid == client_id).order_by(MpInstalledPatch.mdate.desc()).limit(10)

	_results = []
	for p in query:
		row = {}
		for c, t in columns:
			y = "p."+c
			row[c] = eval(y)
		_results.append(row)

	_columns = []
	for c, t in columns:
		row = {}
		row['field'] = c
		row['title'] = t
		row['sortable'] = 'true'
		_columns.append(row)

	return json.dumps({'data':_results, 'columns': _columns}, default=json_serial), 200

# JSON Routes
@clients.route('/dashboard/inventory/<client_id>/<inv_id>')
@login_required
def clientInventoryReport(client_id, inv_id):

	sql = text("select * From {} where cuuid = '{}'".format(inv_id, client_id))
	_q_result = db.engine.execute(sql)

	_results = []
	_columns = []

	for v in _q_result:
		_row = {}
		for column, value in v.items():
			if column != "cdate" or column != "rid" or column != "cuuid":
				if column == "mdate":
					_row[column] = value.strftime("%Y-%m-%d %H:%M:%S")
				else:
					_row[column] = value

		_results.append(_row)

	for column in _q_result.keys():
		if column != "cdate" and column != "rid" and column != "cuuid":
			_col = {}
			_col['field'] = column
			if column == "mdate":
				_col['title'] = 'Inv Date'
			else:
				_col['title'] = column.replace('mpa_', '', 1).replace("_", " ")

			_col['sortable'] = 'true'
			_columns.append(_col)

	return json.dumps({'data':_results, 'columns':_columns}), 200

def daysFromDate(now, date):
	x = now - date
	return x.days

'''
********************************
	Groups
********************************
'''
@clients.route('/groups')
@login_required
def clientGroups():
	groups = MpClientGroups.query.all()
	cols = MpClientGroups.__table__.columns

	# Convert Query Result to Array or Dicts to add the count column
	_data = []
	for g in groups:
		x = g.asDict
		x['count'] = 0
		_data.append(x)

	# Get Reboot Count
	sql = text("""select group_id, count(*) as total
				From mp_client_group_members
				Group By group_id""")

	result = db.engine.execute(sql)
	_results = []
	for v in result:
		_row = {}
		for column, value in v.items():
			_row[column] = value

		_results.append(_row)

	_rights = list(accessToGroups())

	# Return Data
	return render_template('client_groups.html', data=_data, columns=cols, counts=_results, rights=_rights)

@clients.route('/group/add')
@login_required
def clientGroupAdd():
	''' Returns an empty set of data to add a new record '''
	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
	_owner = usr.user_id
	_group_id = str(uuid.uuid4())

	clientGroup = MpClientGroups()
	setattr(clientGroup, 'group_id', _group_id)
	setattr(clientGroup, 'group_owner', _owner)

	log("{} adding new group {}.".format(_owner, _group_id))
	return render_template('update_client_group.html', data=clientGroup, type="add")

@clients.route('/group/modify/<group_id>')
@login_required
def clientGroupModify(group_id):
	''' Returns an empty set of data to add a new record '''
	if not isOwnerOfGroup(group_id):
		return '', 400

	clientGroup = MpClientGroups.query.filter(MpClientGroups.group_id == group_id).first()
	if clientGroup is None:
		return '', 400

	return render_template('update_client_group.html', data=clientGroup)

@clients.route('/group/<id>/user/add',methods=['GET'])
@login_required
def clientGroupUserAdd(id):
	return render_template('client_group_user_mod.html', data={'group_id':id}, type="add")

@clients.route('/group/<id>/<user_id>/remove')
def clientGroupUserRemove(id, user_id):
	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
	if usr.user_id == user_id or isOwnerOfGroup(id):
		uadm = MpClientGroupAdmins().query.filter(MpClientGroupAdmins.group_id == id, MpClientGroupAdmins.group_admin == user_id).first()
		if uadm:
			db.session.delete(uadm)
			db.session.commit()
			log("{} removed user ({}) from client group {}".format(session.get('user'), user_id, id))
		else:
			return json.dumps({'error': 404, 'errormsg': 'User could not be removed.'}), 404

	return json.dumps({'error': 0}), 200

@clients.route('/group/user/modify',methods=['POST'])
@login_required
def clientGroupUserModify():
	id = request.form.get('group_id')
	uid = request.form.get('user_id')
	log("{} added user {} to client group {}".format(session['user'], uid, id))

	try:
		adm = MpClientGroupAdmins().query.filter(MpClientGroupAdmins.group_id == id, MpClientGroupAdmins.group_admin == uid).first()
		if adm:
			setattr(adm, 'group_id', id)
			setattr(adm, 'group_admin', uid)
		else:
			adm = MpClientGroupAdmins()
			setattr(adm, 'group_id', id)
			setattr(adm, 'group_admin', uid)
			db.session.add(adm)

		db.session.commit()

	except:
		log_Error("Error {}".format(sys.exc_info()[0]))

	return clientGroup(id,5)

@clients.route('/group/update/<group_id>',methods=['POST'])
@login_required
def patchGroupUpdate(group_id):

	_add = False
	_group_id    = request.form['group_id']
	_group_name  = request.form['group_name']
	_group_owner = request.form['group_owner']

	clientGroup = MpClientGroups().query.filter(MpClientGroups.group_id == _group_id).first()
	if clientGroup is None:
		_add = True
		clientGroup = MpClientGroups()

	setattr(clientGroup, 'group_name', _group_name)
	setattr(clientGroup, 'group_owner', _group_owner)
	if _add:
		setattr(clientGroup, 'group_id', _group_id)
		db.session.add(clientGroup)
		# Add Default Settings
		groupDefaultSettings(_group_id)

	db.session.commit()
	return clientGroups()

@clients.route('/group/<name>',methods=['GET','DELETE'])
@login_required
def clientGroup(name,tab=1):
	_tab = request.args.get('tab')
	if _tab is not None:
		tab = int(_tab)

	q_defaultGroup = MpClientGroups.query.filter(MpClientGroups.group_id == name, MpClientGroups.group_name == 'Default').first()

	if request.method == 'DELETE':
		if q_defaultGroup:
			return json.dumps({{'errormsg':'Can not delete default group.'}}), 403

		qMembers = MpClientGroupMembers.query.filter(MpClientGroupMembers.group_id == name).all()
		if qMembers is not None and len(qMembers) >= 1:
			return json.dumps({'errormsg':'Group still contains agents. Can not delete group while agents are assigned.'}), 401
		else:
			usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
			if usr is not None or isOwnerOfGroup(name):
				MpClientGroupMembers.query.filter(MpClientGroupMembers.group_id == name).delete()
				MpClientTasks.query.filter(MpClientTasks.group_id == name).delete()
				MpClientSettings.query.filter(MpClientSettings.group_id == name).delete()
				MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.groupID == name).delete()
				MpClientGroups.query.filter(MpClientGroups.group_id == name).delete()
				db.session.commit()

				log("{} deleted client group {}".format(session['user'], name))
				return json.dumps({}), 201
			else:
				log("{} could not delete client group {}. Does not have permission.".format(session['user'], name))
				return json.dumps({}), 403
	else:
		canEditGroup = False
		if not isOwnerOfGroup(name) and not isAdminForGroup(name):
			if q_defaultGroup:
				canEditGroup = True
			else:
				return clientGroups()

		groupResult = {}

		# cList = MpClient.query.all()
		cListCols = MpClient.__table__.columns
		# Cort the Columns based on "doc" attribute
		sortedCols = sorted(cListCols, key=getDoc)

		# Get All Client IDs in with in our group
		_qcg = MpClientGroups.query.filter(MpClientGroups.group_id == name).with_entities(MpClientGroups.group_name).first()

		# Get All Client Group Admins
		_admins = []
		_qadm = MpClientGroupAdmins.query.filter(MpClientGroupAdmins.group_id == name).all()
		if _qadm:
			for u in _qadm:
				_row = {'user_id':u.group_admin,'owner': 'False'}
				_admins.append(_row)

		_owner = MpClientGroups.query.filter(MpClientGroups.group_id == name).first()
		_admins.append({'user_id':_owner.group_owner,'owner': 'True'})
		_admins = sorted(_admins, key=itemgetter('owner'), reverse=True)

		_sortedCols = []
		for x in sortedCols:
			_sortedCols.append({'name':x.name, 'info':x.info})

		_sortedCols.append({'name':'ADDN', 'info':'ADDN'})
		_sortedCols.append({'name': 'ADOU', 'info': 'ADOU'})
		_sortedCols.append({'name': 'SLAM', 'info': 'SLAM'})

		# Client Tasks Columns
		_qTasksCols = MpClientTasks.__table__.columns

		# Data in one dict
		groupResult['Clients'] = {'data': [], 'columns': _sortedCols} # Data comes from ajax request
		groupResult['Group'] = {'name': _qcg.group_name, 'id':name}
		groupResult['Software'] = {'catalogs':softwareCatalogs()}  # Used to populate UI for setting
		groupResult['Patches'] = {'groups': patchGroups()}  # Used to populate UI for setting
		groupResult['Users'] = {'users': _admins, 'columns': [('user_id','User ID'),('owner','Owner')]}
		groupResult['Admin'] = isAdminForGroup(name)
		groupResult['Owner'] = isOwnerOfGroup(name)

		# Group Settings
		_settings = getGroupSettings(name)
		profileCols = [('profileID', 'Profile ID', '0'), ('gPolicyID', 'Policy Identifier', '0'), ('pName', 'Profile Name', '1'), ('title', 'Title', '1'),
						('description', 'Description', '1'), ('enabled', 'Enabled', '1')]

		swCols = [('rid', 'rid', '0'),('name', 'Name', '1'),('tuuid', 'Software Task ID', '1')]
		provCols = [('id', 'ID', '0'), ('name', 'Name Identifier', '1')]

		return render_template('client_group.html', data=[], columns=_sortedCols, group_name=_qcg.group_name, group_id=name,
							tasksCols=_qTasksCols, gResults=groupResult, selectedTab=tab,
							profileCols=profileCols, swCols=swCols, swData=[], provCols=provCols, provData=[],
							readOnly=canEditGroup, settings=_settings)

'''
********************************
	Groups - > Clients
********************************
'''

@clients.route('/group/<group_id>/clients')
def clientGroupClients(group_id):
	# Get All Client IDs in with in our group
	_qcg = MpClientGroups.query.filter(MpClientGroups.group_id == group_id).with_entities(MpClientGroups.group_name).first()
	_res = MpClientGroupMembers.query.filter(MpClientGroupMembers.group_id == group_id).with_entities(MpClientGroupMembers.cuuid).all()
	_cuuids = [r for r, in _res]

	# Run Query of all clients that contain the Client ID
	# sql = text("""select * From mp_clients;""")
	sql = text("""select c. *, mpa_distinguishedName as ADDN,
				  SUBSTRING_INDEX(mpa_distinguishedName,",",-4) as ADOU,
				  mpa_HasSLAM as SLAM
				  from mp_clients c Left Join mpi_DirectoryServices d
				  ON c.cuuid = d.cuuid""")
	_q_result = db.engine.execute(sql)

	_results = []
	for v in _q_result:
		if v.cuuid in _cuuids:
			_row = {}
			for column, value in v.items():
				if column != "cdate":
					if column == "mdate":
						_row[column] = value.strftime("%Y-%m-%d %H:%M:%S")
						_row['clientState'] = clientStatusFromDate(value)
					else:
						_row[column] = value

			for key in _row.keys():
				if not isinstance(_row[key], (long, int)):
					if _row[key]:
						_row[key] = _row[key].replace('\n', '')
					else:
						_row[key] = ''

			_results.append(_row)

	jResult = json.dumps(_results)
	return jResult, 200

# Remove/Delete Client
@clients.route('/group/<id>/remove/clients',methods=['POST'])
def clientGroupClientsRemove(id):

	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
	if usr is not None or isOwnerOfGroup(id):
		for x in request.form['clients'].split(","):
			client = MpClient.query.filter(MpClient.cuuid == x).first()
			clientGroupMember = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == x, MpClientGroupMembers.group_id == id).first()
			if clientGroupMember:
				log("{} delete client group member {} from group {}".format(session.get('user'), x, id))
				db.session.delete(clientGroupMember)
				db.session.commit()

			if client:
				log("{} delete client {} from group {}".format(session.get('user'), x, id))
				db.session.delete(client)
				db.session.commit()

			else:
				return json.dumps({'error': 404, 'errormsg': 'User could not be removed.'}), 404

	return json.dumps({}), 200

# Move a client to a new group
@clients.route('/move/client',methods=['POST'])
@login_required
def clientMove():

	_cuuids     = request.form['cuuids'].split(',')
	_o_group_id = request.form['orig_group_id']
	_group_id   = request.form['group_id']

	for c in _cuuids:
		groupMember = MpClientGroupMembers().query.filter(MpClientGroupMembers.cuuid == c).first()
		setattr(groupMember, 'group_id', str(_group_id))
		log("{} moving client {} from {} to {}".format(session.get('user'), c, _o_group_id, _group_id))

	db.session.commit()
	return clientGroup(_o_group_id,1)

# Move a client to a new group
@clients.route('/show/move/client/<id>')
@login_required
def showClientMove(id):
	cGroups = MpClientGroups().query.all()
	return render_template('move_client_to_group.html', groups=cGroups, curGroup=0, cuuid=0)

'''
********************************
	Groups - > Settings
********************************
'''
@clients.route('/group/<id>/settings',methods=['POST'])
@login_required
def groupSettings(id):
	log("{} updating client group {} settings.".format(session.get('user'), id))
	_form = request.form

	# Revision Increment
	cfg = MPGroupConfig().query.filter(MPGroupConfig.group_id == id).first()
	if cfg:
		rev = cfg.rev_settings + 1
		setattr(cfg, 'rev_settings', rev)
	else:
		cfg = MPGroupConfig()
		setattr(cfg, 'group_id', id)
		setattr(cfg, 'rev_settings', 1)
		setattr(cfg, 'rev_tasks', 1)
		db.session.add(cfg)

	# Remove All Settings & Add New, easier than update
	mpc = MpClientSettings().query.filter(MpClientSettings.group_id == id).all()
	if mpc is not None and len(mpc) >= 1:
		for row in mpc:
			log_Debug("Current Group Settings[{}]: {} = {}".format(id, row.key, row.value))

		sql = "DELETE FROM mp_client_settings WHERE group_id='" + id + "'"
		db.engine.execute(sql)

	for f in _form:
		log_Debug("Updated Group Settings[{}]: {} = {}".format(id, f, str(_form[f])))
		mpc = MpClientSettings()
		setattr(mpc, 'group_id', id)
		setattr(mpc, 'key', f)
		setattr(mpc, 'value', str(_form[f]))
		db.session.add(mpc)

	db.session.commit()
	return json.dumps({'error': 0}), 200

# Add Default Settings to new group
def groupDefaultSettings(id):
	mpc = MpClientSettings().query.filter(MpClientSettings.group_id == id).all()
	if mpc is not None and len(mpc) >= 1:
		# Log that group settings already exist
		return False

	patchGroup = MpPatchGroup.query.filter(MpPatchGroup.name == 'Default').first()
	swGroup = MpSoftwareGroup.query.filter(MpSoftwareGroup.gName == 'Default').first()
	form = {'patch_group': patchGroup.id,
			'software_group': swGroup.gid,
			'inherited_software_group':'None',
			'allow_client':'1',
			'allow_server':'1',
			'allow_reboot':'1',
			'verify_signatures':'0',
			'patch_state':'Production',
			'pre_stage_patches':'1'}

	# Revision Increment
	cfg = MPGroupConfig().query.filter(MPGroupConfig.group_id == id).first()
	if cfg:
		rev = cfg.rev_settings + 1
		setattr(cfg, 'rev_settings', rev)
	else:
		cfg = MPGroupConfig()
		setattr(cfg, 'group_id', id)
		setattr(cfg, 'rev_settings', 1)
		setattr(cfg, 'rev_tasks', 1)
		db.session.add(cfg)

	for key, value in form.iteritems():
		mpc = MpClientSettings()
		setattr(mpc, 'group_id', id)
		setattr(mpc, 'key', key)
		setattr(mpc, 'value', str(value))
		db.session.add(mpc)

	db.session.commit()
	return True

def getGroupSettings(id):
	mpc = MpClientSettings().query.filter(MpClientSettings.group_id == id).all()
	result = {}
	if mpc is not None:
		for s in mpc:
			result[s.key] = s.value

	return result

def patchGroups():
	_qget = MpPatchGroup.query.with_entities(MpPatchGroup.id, MpPatchGroup.name).all()
	_results = []
	for x in _qget:
		_results.append((x.id,x.name))

	return _results

def softwareCatalogs():
	_qget = MpSoftwareGroup.query.with_entities(MpSoftwareGroup.gid, MpSoftwareGroup.gName).all()
	_results = []
	for x in _qget:
		_results.append((x.gid,x.gName))

	return _results

'''
********************************
	Groups - > Tasks
********************************
'''
@clients.route('/group/<group_id>/tasks', methods=['GET'])
@login_required
def groupTasks(group_id):

	# Get Tasks from default_tasks.json file, then query db to see if client group
	# is using the correct version of the default tasks. If not, we will
	# add the missing tasks to the group.
	# TODO: Add method to mpconsole.py to upgrade all groups so that admins
	# dont have to click on the tasks tab to refresh

	add_tasks=False
	file_tasks = defaultTasks()
	grp_conf = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
	if "version" in file_tasks:
		if grp_conf is not None:
			if grp_conf.tasks_version != file_tasks['version']:
				add_tasks = True
		else:
			add_tasks = True

	if add_tasks:
		# Add Missing Tasks
		addMissingTasks(group_id, file_tasks['mpTasks'], file_tasks['version'])

	tasks = MpClientTasks.query.filter(MpClientTasks.group_id == group_id).all()
	_results = []
	if tasks is not None and len(tasks) >= 1:
		for t in tasks:
			_row = t.__dict__.copy()
			del _row['_sa_instance_state']
			_results.append(_row)

	return json.dumps({'data': _results, 'total': len(_results)}), 200

# Private Method to Add Missing tasks, used by groupTasks
#
# TODO, need to remove tasks if removed from default_tasks
#
def addMissingTasks(group_id, fileTasks, new_task_version):

	# List of Current commands in db
	_cmds = []
	tasks = MpClientTasks.query.filter(MpClientTasks.group_id == group_id).all()
	if tasks is not None and len(tasks) >= 1:
		for t in tasks:
			_row = t.__dict__.copy()
			_cmds.append(_row['cmd'])

	# Loop over default tasks, if cmd is not found then add it
	for task in fileTasks:
		if task['cmd'] not in _cmds:
			_task = MpClientTasks()
			setattr(_task, 'group_id', group_id)
			for key in task.keys():
				setattr(_task, key, task[key])

			db.session.add(_task)
			db.session.commit()

	# Update Tasks Version to new version
	grp_conf = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
	if grp_conf is not None:
		rev_tasks = grp_conf.rev_tasks + 1
		setattr(grp_conf, "tasks_version", new_task_version)
		setattr(grp_conf, "rev_tasks", rev_tasks)
		db.session.commit()

def revGroupTasks(group_id):
	grp_conf = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
	if grp_conf is not None:
		rev_tasks = grp_conf.rev_tasks + 1
		setattr(grp_conf, "rev_tasks", rev_tasks)
		db.session.commit()

# Tasks inline updates
@clients.route('/group/<id>/task/active',methods=['POST'])
@login_required
def taskState(id):
	if isOwnerOfGroup(id) or isAdminForGroup(id):
		key = request.form.get('pk')
		value = request.form.get('value')
		log("{} set task {} active state to {} ".format(session.get('user'), key, value))
		task = MpClientTasks.query.filter(MpClientTasks.group_id == id, MpClientTasks.cmd == key).first()
		if task is not None:
			setattr(task, 'active', value)
			db.session.commit()
			revGroupTasks(id)

	return clientGroup(id)

@clients.route('/group/<id>/task/interval',methods=['POST'])
@login_required
def taskInterval(id):
	if isOwnerOfGroup(id) or isAdminForGroup(id):
		cmd = request.form.get('pk')
		interval = request.form.get('value')
		log("{} set task {} active state to {} ".format(session.get('user'), cmd, interval))
		task = MpClientTasks.query.filter(MpClientTasks.group_id == id, MpClientTasks.cmd == cmd).first()
		if task is not None:
			setattr(task, 'interval', interval)
			db.session.commit()
			revGroupTasks(id)

	return clientGroup(id)

'''
********************************
	Groups - > Software
********************************
'''
@clients.route('/group/<group_id>/software', methods=['GET'])
@login_required
def groupSoftware(group_id):
	sw = MpSoftwareTask.query.all()
	swIDs = MpClientGroupSoftware.query.filter(MpClientGroupSoftware.group_id == group_id).all()

	_results = []
	if swIDs is not None and len(swIDs) >= 1:
		for sid in swIDs:
			for s in sw:
				if sid.tuuid == s.tuuid:
					_row = s.__dict__.copy()
					del _row['_sa_instance_state']
					_row['rid'] = sid.rid
					_results.append(_row)
					break

	print _results
	return json.dumps({'data': _results, 'total': len(_results)}, default=json_serial), 200

@clients.route('/group/<id>/sw/add',methods=['GET','POST'])
@login_required
def clientGroupSWAdd(id):
	if request.method == 'GET':
		sw = MpSoftwareTask.query.filter(MpSoftwareTask.active == 1).all()
		return render_template('client_group_sw_add.html', data={'group_id':id}, swData=sw, type="add")

	elif request.method == 'POST':
		_form = request.form
		_groupID = request.form.get('group_id')
		_tuuid = request.form.get('tuuid')

		hasSW = MpClientGroupSoftware.query.filter(MpClientGroupSoftware.group_id == _groupID, MpClientGroupSoftware.tuuid == _tuuid).first()
		if hasSW is None:
			clientSW = MpClientGroupSoftware()
			setattr(clientSW , 'group_id', _groupID)
			setattr(clientSW , 'tuuid', _tuuid)
			db.session.add(clientSW)
			db.session.commit()

		return redirect(url_for('.clientGroup',name=id,tab=5))
		# return clientGroup(id, 5)

@clients.route('/group/<id>/sw/remove',methods=['DELETE'])
@login_required
def clientGroupSWDel(id):

	_group_id = id
	_sw_ids = request.form.get('rids').split(",")
	if _sw_ids is not None and len(_sw_ids) > 0:
		for i in _sw_ids:
			MpClientGroupSoftware.query.filter(MpClientGroupSoftware.group_id == _group_id,
											   MpClientGroupSoftware.rid == i).delete()
			db.session.commit()


	return json.dumps({}), 200


'''
********************************
	Global
********************************
'''
def getDoc(col_obj):
	return col_obj.doc

def isOwnerOfGroup(id):
	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
	usrInf = accountInfo() # Check if console admin account

	if usr:
		if usrInf:
			# User_type 0 is the main console admin, has access to everything
			if usrInf.user_type == 0:
				return True

		pgroup = MpClientGroups.query.filter(MpClientGroups.group_id == id).first()
		if pgroup:
			if pgroup.group_owner == usr.user_id:
				return True
			else:
				return False

	return False

def isAdminForGroup(id):
	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
	usrInf = accountInfo()

	if usr:
		if usrInf:
			# User_type 0 is the main console admin, has access to everything
			if usrInf.user_type == 0:
				return True

		q_admin = MpClientGroupAdmins.query.filter(MpClientGroupAdmins.group_id == id).all()
		if q_admin:
			result = False
			for row in q_admin:
				if row.group_admin == usr.user_id:
					result = True
					break

			return result

	return False

def accessToGroups():
	_groups = set([])
	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
	usrInf = accountInfo()
	if usr:
		if usrInf:
			# User_type 0 is the main console admin, has access to everything
			if usrInf.user_type == 0:
				q_groups = MpClientGroups.query.all()
				for row in q_groups:
					_groups.add(row.group_id)
				return _groups

		q_owner = MpClientGroups.query.filter(MpClientGroups.group_owner == usr.user_id).all()
		if q_owner:
			for row in q_owner:
				_groups.add(row.group_id)

		q_admin = MpClientGroupAdmins.query.filter(MpClientGroupAdmins.group_admin == usr.user_id).all()
		if q_admin:
			for row in q_admin:
				_groups.add(row.group_id)

		return _groups
	else:
		return None

def accountInfo():
	usrInf = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == session.get('user')).first()
	if usrInf:
		return usrInf
	else:
		return None

def clientStatusFromDate(date):

	result = 0
	now = datetime.now()
	x = now - date
	if x.days <= 7:
		result = 0
	elif x.days >= 8 and x.days <= 14:
		result = 1
	elif x.days >= 15:
		result = 2

	return result

def inventoryTypes():

	_jData = []
	inv = os.path.join(current_app.config['BASEDIR'], 'static/json', 'inventory.json')
	fileISOk = os.path.exists(inv)
	if fileISOk:
		with open(inv) as data_file:
			_jData = json.load(data_file)

	return _jData
	'''
	return {('HardwareOverview','Hardware Overview'),
			('SoftwareOverview','Software Overview'),
			('NetworkOverview','Network Overview'),
			('Applications','Applications'),
			('ApplicationUsage','Application Usage'),
			('DirectoryService','Directory Service'),
			('Frameworks','Frameworks'),
			('InternetPlugins','Internet Plugins'),
			('ClientTasks','Client Tasks'),
			('DiskInfo','Disk Info'),
			('SWInstalls','Software Installs'),
			('BatteryInfo','Battery Info'),
			('PowerManagment','Power Managment'),
			('FileVault','FileVault Info'),
			('PatchStatus','Patch Status'),
			('PatchHistory','Patch History')}
	'''

def defaultTasks():

	_jData = []
	tasks = os.path.join(current_app.config['BASEDIR'], 'static/json', 'default_tasks.json')
	fileISOk = os.path.exists(tasks)
	if fileISOk:
		with open(tasks) as data_file:
			_jData = json.load(data_file)

	return _jData

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.isoformat()
		return serial
	raise TypeError("Type not serializable")
