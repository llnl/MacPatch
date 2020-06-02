from flask import render_template, request, session
from flask_security import login_required
from werkzeug.utils import secure_filename
from sqlalchemy.orm.session import make_transient
from sqlalchemy import or_
import os
import json
import uuid
import base64
import hashlib
import sys
from datetime import datetime

from .  import software
from .. import db
from .. model import *
from .. modes import *
from .. mplogger import *
from .. mputil import *

'''
	-------------------------------------------------
	Groups
	-------------------------------------------------
'''

@software.route('/groups')
@login_required
def groups():

	qGet = MpSoftwareGroup.query.all()
	qGetCols = MpSoftwareGroup.__table__.columns

	_cols = []
	for c in qGetCols:
		if c.name != 'rid' and c.name != 'gHash' and c.name != 'gType' and c.name != 'cdate':
			_row = {}

			if c.name == 'gid':
				_row['visible'] = False
			else:
				_row['visible'] = True

			_row['field'] = c.name
			_row['title'] = c.info
			_row['sortable'] = True
			_cols.append(_row)

	options = {0:"Development", 1:"Production", 2:"QA", 3:"Disabled"}

	_rows = []
	for r in qGet:
		_drow = {}
		for c in _cols:
			_obj = "r." + c['field']
			_objVal = eval(_obj)
			try:
				if c['field'] == 'mdate':
					_drow[c['field']] = _objVal.strftime("%Y-%m-%d %H:%M:%S")
				elif c['field'] == 'state':
					_drow[c['field']] = options[_objVal]
				else:
					_drow[c['field']] = _objVal
			except Exception as e:
				exc_type, exc_obj, exc_tb = sys.exc_info()
				message=str(e.args[0]).encode("utf-8")
				log_Error(message)

		_rows.append(_drow)

	return render_template('software/software_groups.html', data={"columns":_cols, "rows":_rows}, title="Software Groups")

@software.route('/group/add/<id>')
@login_required
def swGroupAdd(id):

	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
	return render_template('software/software_group_modify.html', group_id=id, user=usr.user_id)

@software.route('/group/edit/<id>')
@login_required
def swGroupEdit(id):

	group_name = None
	group_description = None
	group_owner = None

	mpsg = MpSoftwareGroup.query.filter(MpSoftwareGroup.gid == id).first()
	mpsgp = MpSoftwareGroupPrivs.query.filter(MpSoftwareGroupPrivs.gid == id, MpSoftwareGroupPrivs.isowner == 1).first()

	if mpsg:
		group_name = mpsg.gName
		group_description = mpsg.gDescription

	if mpsgp:
		group_owner = mpsgp.uid

	return render_template('software/software_group_modify.html', group_id=id, group_name=group_name, group_description=group_description, user=group_owner)

@software.route('/group/save', methods=['POST'])
@login_required
def swGroupSave():
	group_id = request.form.get('group_id')
	group_name = request.form.get('group_name')
	group_description = request.form.get('group_description')
	group_owner = request.form.get('user_id')

	mpsg = MpSoftwareGroup.query.filter(MpSoftwareGroup.gid == group_id).first()

	if mpsg:
		mpsgp = MpSoftwareGroupPrivs.query.filter(MpSoftwareGroupPrivs.gid == group_id, MpSoftwareGroupPrivs.isowner == 1).first()
		mpsgpUsr = MpSoftwareGroupPrivs.query.filter(MpSoftwareGroupPrivs.gid == group_id, MpSoftwareGroupPrivs.uid == session.get('user')).first()
		# Permissions
		# Owner or Admin = 2, group admin = 1
		is_admin = 0

		# set rights for owner or site admin
		if mpsgp is not None:
			if session.get('user_id') == '1' or mpsgp.uid == session.get('user'):
				is_admin = 2

		if session.get('role')[0] == 1:
			is_admin = 2
			
		# Set rights for standard group admin
		if mpsgpUsr is not None:
			is_admin = 1

		if is_admin >= 1:
			setattr(mpsg, 'gName', group_name)
			setattr(mpsg, 'gDescription', group_description)
		if is_admin == 2:
			setattr(mpsgp, 'uid', group_owner)

	else:
		mpsqp = MpSoftwareGroupPrivs()
		mpsg = MpSoftwareGroup()
		setattr(mpsg, 'gid', group_id)
		setattr(mpsg, 'gName', group_name)
		setattr(mpsg, 'gDescription', group_description)
		setattr(mpsqp, 'gid', group_id)
		setattr(mpsqp, 'uid', group_owner)
		setattr(mpsqp, 'isowner', 1)

		db.session.add(mpsg)
		db.session.add(mpsqp)

	db.session.commit()
	return groups()

''' AJAX Route '''
@software.route('/group/delete/<id>', methods=['DELETE'])
@login_required
def swGroupDelete(id):
	groupPriv = MpSoftwareGroupPrivs.query.filter(MpSoftwareGroupPrivs.gid == id, MpSoftwareGroupPrivs.isowner == 1,
	MpSoftwareGroupPrivs.uid == session.get('user') ).first()
	# Must be owner or default admin
	if groupPriv is not None or session.get('user_id') == '1':
		# Session user is the owner
		MpSoftwareGroup.query.filter(MpSoftwareGroup.gid == id).delete()
		MpSoftwareGroupPrivs.query.filter(MpSoftwareGroupPrivs.gid == id).delete()
		db.session.commit()
		return json.dumps({'error':0}), 202

	return json.dumps({'error':401, 'errormsg':'Unauthorized to remove group. Must be the owner of the group.'}), 401

@software.route('/group/filters/<id>')
@login_required
def showFiltersForGroup(id):
	# sw_Cols MpSoftwareGroupFilters
	columns = [('rid','rid',0),('attribute','Type',1),('datasource','DataSource',1),('attribute_oper','Operator',1),
			('attribute_filter','Filter Value',1),('attribute_condition','Condition',1)]
	return render_template('software/software_group_filters.html', group_id=id, columns=columns)

''' AJAX Route '''
@software.route('/group/filter/list/<id>/<limit>/<offset>/<search>/<sort>/<order>')
def filtersForGroup(id,limit,offset,search,sort,order):

	total = 0
	getNewTotal = True
	if 'my_search_name' in session:
		if session['my_search_name'] == 'filtersForGroup':
			if 'my_search' in session and 'my_search_total' in session:
				if session['my_search'] == search:
					getNewTotal = False
					total = session['my_search_total']
	else:
		session['my_search_name'] ='filtersForGroup'
		session['my_search_total'] = 0
		session['my_search'] = None

	colsForQuery = ['rid', 'attribute', 'datasource', 'attribute_oper', 'attribute_filter', 'attribute_condition']
	qResult = filtersQuery(id, search, int(offset), int(limit), sort, order, getNewTotal)
	query = qResult[0]

	session['my_search_name'] = 'filtersForGroup'

	if getNewTotal:
		total = qResult[1]
		session['my_search_total'] = total
		session['my_search'] = search

	_results = []
	for p in query:
		row = {}
		for x in colsForQuery:
			y = "p."+x
			if x == 'mdate':
				row[x] = eval(y)
			elif x == 'type':
				row[x] = eval(y).title()
			else:
				row[x] = eval(y)

		_results.append(row)

	return json.dumps({'data': _results, 'total': total}), 200

def filtersQuery(id, filterStr='undefined', page=0, page_size=0, sort='rid', order='desc', getCount=True):

	if sort == 'undefined':
		sort = 'mp_software_groups_filters.rid'

	if sort in ['rid', 'attribute', 'datasource', 'attribute_oper', 'attribute_filter', 'attribute_condition']:
		sort = 'mp_software_groups_filters.'+sort

	order_by_str = sort + ' ' + order

	filterStr = str(filterStr)
	if filterStr == 'undefined' or len(filterStr) <= 0:
		query = MpSoftwareGroupFilters.query.filter(MpSoftwareGroupFilters.gid == id).order_by(str(order_by_str))
	else:
		query = MpSoftwareGroupFilters.query.filter(MpSoftwareGroupFilters.gid == id,
											or_(MpSoftwareGroupFilters.attribute.contains(filterStr),
											MpSoftwareGroupFilters.datasource.contains(filterStr),
											MpSoftwareGroupFilters.attribute_oper.contains(filterStr),
											MpSoftwareGroupFilters.attribute_filter.contains(filterStr),
											MpSoftwareGroupFilters.attribute_condition.contains(filterStr))).order_by(str(order_by_str))

	# count of rows
	if getCount:
		rowCounter = query.count()
	else:
		rowCounter = 0

	if page_size:
		query = query.limit(page_size)
	if page:
		query = query.offset(page)
	return (query, rowCounter)

@software.route('/group/filter/add/<group_id>')
@login_required
def addFilterForGroup(group_id):
	_title = "Add Group Filter"
	return render_template('software/software_group_filter_modify.html', title=_title, group_id=group_id, data={})

@software.route('/group/filter/edit/<group_id>/<row_id>', methods=['GET','DELETE'])
@login_required
def editFilterForGroup(group_id, row_id):
	if request.method == 'DELETE':
		MpSoftwareGroupFilters.query.filter(MpSoftwareGroupFilters.gid == group_id, MpSoftwareGroupFilters.rid == row_id).delete()
		db.session.commit()
		return json.dumps({'error':0}), 201

	if request.method == 'GET':
		_title = "Edit Group Filter"
		filter = MpSoftwareGroupFilters.query.filter(MpSoftwareGroupFilters.gid == group_id, MpSoftwareGroupFilters.rid == row_id).first()
		if filter is None:
			filter = {}

		return render_template('software/software_group_filter_modify.html', title=_title, group_id=group_id, data=filter)

''' AJAX Request '''
@software.route('/group/filter/save/<group_id>', methods=['POST'])
@login_required
def saveGroupFilter(group_id):
	_form = request.form.to_dict()

	_is_new_filter=False
	if 'rid' in _form:
		if _form['rid'] == '':
			_is_new_filter=True
			filter = MpSoftwareGroupFilters()
			setattr(filter, 'gid', group_id)
		else:
			filter = MpSoftwareGroupFilters.query.filter(MpSoftwareGroupFilters.rid == _form['rid']).first()

	for key, value in list(_form.items()):
		if key not in ['rid', 'gid']:
			setattr(filter, key, value)

	# Add New Record
	if _is_new_filter:
		db.session.add(filter)

	db.session.commit()
	return json.dumps({'error':0}), 201

'''
	-------------------------------------------------
	Tasks
	-------------------------------------------------
'''

@software.route('/tasks')
@login_required
def tasks():

	columns = [('tuuid','Task ID',0),('primary_suuid','Software ID',0),('name','Name',1),('active','Active',1),('sw_task_type','Task Type',1),
	('sw_start_datetime','Valid From',1),('sw_end_datetime','Valid To',1),('mdate','Mod Date',1)]
	colsForQuery = ['tuuid','primary_suuid','name','active','sw_task_type','sw_start_datetime','sw_end_datetime','mdate']

	qSWTasks = MpSoftwareTask.query.order_by(MpSoftwareTask.mdate.desc()).all()
	_data = []
	for d in qSWTasks:
		row = {}
		for c in colsForQuery:

			if c in ('sw_start_datetime','sw_end_datetime','mdate'):
				dt_obj = eval("d."+c)
				if dt_obj:
					row[c] = eval("d."+c).strftime("%Y-%m-%d %H:%M:%S")
			elif c == 'active':
				_a = eval("d."+c)
				row[c] = "Yes" if _a == 1 else "No"
			else:
				row[c] = eval("d."+c)

		_data.append(row)

	_columns = []
	for c, t, v in columns:
			row = {}
			row['field'] = c
			row['title'] = t
			row['sortable'] = True
			if v == 0:
				row['visible'] = False

			_columns.append(row)

	return render_template('software/software_tasks.html', data={'rows':_data,'columns': _columns}, isAdmin=True)

@software.route('/task/edit/<id>')
@login_required
def taskEdit(id):

	mpst = MpSoftwareTask.query.filter(MpSoftwareTask.tuuid == id).first()
	mps = MpSoftware.query.all()
	_data = {}
	_swPkgs = []
	for s in mps:
		_swPkgs.append((s.suuid,s.sName,s.sVersion))

	_data["Task"] = mpst.asDict
	_data["SoftwareList"] = _swPkgs

	return render_template('software/software_task_modify.html', data=_data, type='edit', isAdmin=True)

@software.route('/task/new')
@login_required
def taskNew():

	_data = {}
	mps = MpSoftware.query.all()

	_swPkgs = []
	for s in mps:
		_swPkgs.append((s.suuid,s.sName,s.sVersion))

	_data["Task"] = {}
	_data["SoftwareList"] = _swPkgs
	_data["NEWID"] = str(uuid.uuid4())

	return render_template('software/software_task_modify.html', data=_data, type='new', isAdmin=True)

''' AJAX Request '''
@software.route('/task/save/<id>', methods=['POST'])
@login_required
def taskSave(id):
	_form = request.form.to_dict()

	_isNewTask=False
	_task = MpSoftwareTask.query.filter(MpSoftwareTask.tuuid == _form['tuuid']).first()
	if _task is None:
		_isNewTask=True
		_task = MpSoftwareTask()

	for key, value in list(_form.items()):
		setattr(_task, key, value)

	setattr(_task, 'mdate', datetime.now())

	if _isNewTask:
		db.session.add(_task)

	db.session.commit()
	return json.dumps({'error':0}), 201

''' AJAX Method '''
@software.route('/task/generate/<id>', methods=['POST'])
def generateTask(id):

	qSW = MpSoftware.query.filter(MpSoftware.suuid == id).first()
	if qSW is not None:
		_tuuid = str(uuid.uuid4())
		_swTask = MpSoftwareTask()
		setattr(_swTask, 'tuuid', _tuuid)
		setattr(_swTask, 'name', qSW.sName)
		setattr(_swTask, 'primary_suuid', id)
		setattr(_swTask, 'active', 0)
		setattr(_swTask, 'sw_start_datetime', datetime.now())
		setattr(_swTask, 'sw_end_datetime', datetime.now())
		setattr(_swTask, 'cdate', datetime.now())
		setattr(_swTask, 'mdate', datetime.now())
		db.session.add(_swTask)
		db.session.commit()
		return json.dumps({'error':0}), 201

	return json.dumps({'error':1,'errormsg':'Software package not found.'}), 404

''' AJAX Request '''
@software.route('/task/remove', methods=['DELETE'])
@login_required
def taskRemove():
	_form = request.form.to_dict()

	if 'tasks' in _form:
		for t in _form['tasks'].split(","):
			_task = MpSoftwareTask.query.filter(MpSoftwareTask.tuuid == t).first()
			if _task is not None:
				log_Info("Delete sw task %s" % (_task.name))
				_tasks = MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.sw_task_id == t).all()
				if _tasks is not None:
					for x in _tasks:
						log_Info("Delete %s from sw group %s" % (x.sw_task_id, x.sw_group_id))
						MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.rid == x.rid).delete()

				db.session.delete(_task)
				db.session.commit()

	return json.dumps({'error':0}), 201

@software.route('/group/<id>/tasks')
@login_required
def swGroupTasks(id):

	tasksForGroup(id)

	columns = [('sw_task_id','Task ID',0),('name','Name',1),('active','Active',1),('sw_task_type','Task Type',1),
	('sw_start_datetime','Start Date',1),('sw_end_datetime','End Date',1)]
	colsForQuery = ['sw_task_id','name','active','sw_task_type','sw_start_datetime','sw_end_datetime']

	qSWTasks = MpSoftwareTask.query.all()
	qGetSel = MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.sw_group_id == id).all()

	_selected = []
	for s in qGetSel:
		row1 = {}
		row1['tuuid'] = s.sw_task_id
		row1['selected'] = s.selected
		_selected.append(row1)

	_data = []
	for d in qSWTasks:
		row2 = {}
		row2['selected'] = False
		for c in colsForQuery:
			if c == 'sw_task_id':
				row2[c] = d.tuuid
			else:
				row2[c] = eval("d."+c)

		_data.append(row2)

	for d in _data:
		for s in _selected:
			if d['sw_task_id'] == s['tuuid']:
				if s['selected'] == 1:
					d['selected'] = True
				else:
					d['selected'] = False
				continue

	_columns = []
	for c, t, v in columns:
			row = {}
			row['field'] = c
			row['title'] = t
			row['sortable'] = True
			if v == 0:
				row['visible'] = False

			_columns.append(row)

	_isOwner = isOwnerOfSWGroup(id)
	_isAdmin = isAdminForSWGroup(id)

	return render_template('software/software_group_tasks.html', data={'rows':_data,'columns': _columns}, group_id=id, isOwner=_isOwner, isAdmin=_isAdmin)

''' AJAX Method '''
@software.route('/group/<id>/task/add/<task_id>')
def swGroupTasksAdd(id, task_id):

	qGet = MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.sw_group_id == id, MpSoftwareGroupTasks.sw_task_id == task_id).first()
	if qGet:
		setattr(qGet, 'selected', 1)
	else:
		mpt = MpSoftwareGroupTasks()
		setattr(mpt, 'sw_group_id', id)
		setattr(mpt, 'sw_task_id', task_id)
		setattr(mpt, 'selected', 1)
		db.session.add(mpt)

	db.session.commit()
	return json.dumps({'error':0}), 200

''' AJAX Method '''
@software.route('/group/<id>/task/remove/<task_id>')
def swGroupTasksRemove(id, task_id):

	qGet = MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.sw_group_id == id, MpSoftwareGroupTasks.sw_task_id == task_id).first()
	if qGet:
		setattr(qGet, 'selected', 0)
	else:
		mpt = MpSoftwareGroupTasks()
		setattr(mpt, 'sw_group_id', id)
		setattr(mpt, 'sw_task_id', task_id)
		setattr(mpt, 'selected', 0)
		db.session.add(mpt)

	db.session.commit()
	return json.dumps({'error':0}), 200

''' AJAX Method '''
@software.route('/group/<id>/tasks/save')
def swGroupTasksSave(id):
	tData = tasksForGroup(id)
	if tData is None:
		log_Error("Error: No data to write to database.")
		return json.dumps({'error':404,'errormsg':"Error: No data to write to database."}), 404

	isNewRecord=False
	qGroup = MpSoftwareGroup.query.filter(MpSoftwareGroup.gid == id).first()
	qData = MpSoftwareTasksData.query.filter(MpSoftwareTasksData.gid == id).first()
	if qData is None:
		isNewRecord=True
		qData = MpSoftwareTasksData()

	setattr(qData, 'gid', id)
	setattr(qData, 'gDataHash', hashlib.md5(tData.encode('utf-8')).hexdigest())
	setattr(qData, 'gData', tData)
	setattr(qData, 'mdate', datetime.now())
	setattr(qGroup, 'mdate', datetime.now())

	if isNewRecord:
		db.session.add(qData)

	db.session.commit()
	return json.dumps({'error':0}), 200

def tasksForGroup(group):

	_tasks = []
	qGetSel = MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.sw_group_id == group, MpSoftwareGroupTasks.selected == 1).all()

	_selected = []
	for s in qGetSel:
		_selected.append(s.sw_task_id)

	for t in _selected:
		taskData = swTaskData(t)
		if taskData:
			_task = {}
			_task['id'] = taskData['tuuid']
			_task['name'] = taskData['name']
			_task['sw_task_type'] = taskData['sw_task_type']
			_task['sw_task_privs'] = taskData['sw_task_privs']
			_task['sw_start_datetime'] = taskData['sw_start_datetime']
			_task['sw_end_datetime'] = taskData['sw_end_datetime']
			_task['active'] = taskData['active']

			_task['Software'] = {}
			swData = swPackageData(taskData['primary_suuid'])
			if swData is not None:
				_task['Software'] = swData

			_task['SoftwareCriteria'] = {}
			swCrit = swPackageCriteria(taskData['primary_suuid'])
			if swCrit is not None:
				_task['SoftwareCriteria'] = swCrit

			_task['SoftwareRequisistsPre'] = {}
			_task['SoftwareRequisistsPost'] = {}

			_tasks.append(_task)

	return json.dumps({"errorNo":"0","errorMsg":"","result":{'Tasks': _tasks}})

def swTaskData(taskID):
	qSWTask = MpSoftwareTask.query.filter(MpSoftwareTask.tuuid == taskID).first()
	if qSWTask is not None:
		return qSWTask.asDict
	else:
		return None

def swPackageData(swID):

	qSW = MpSoftware.query.filter(MpSoftware.suuid == swID).first()
	if qSW is not None:
		sw = {"name":qSW.sName,
		"vendor":qSW.sVendor,
		"vendorUrl":qSW.sVendorURL,
		"version":qSW.sVersion,
		"description":qSW.sDescription,
		"reboot":str(qSW.sReboot),
		"sw_type":str(qSW.sw_type),
		"sw_url":qSW.sw_url,
		"sw_hash":qSW.sw_hash,
		"sw_size":str(qSW.sw_size),
		"sw_pre_install":b64EncodeAsString(qSW.sw_pre_install_script,''),
		"sw_post_install":b64EncodeAsString(qSW.sw_post_install_script,''),
		"sw_uninstall":b64EncodeAsString(qSW.sw_uninstall_script,''),
		"sw_env_var":qSW.sw_env_var,
		"auto_patch":str(qSW.auto_patch),
		"patch_bundle_id":qSW.patch_bundle_id,
		"state":str(qSW.sState),
		"sid":str(qSW.suuid),
		"sw_img_path":str(qSW.sw_img_path)}
		return sw
	else:
		return None

def swPackageCriteria(swID):
	result = {}
	qSWCri = MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == swID).all()
	if qSWCri is not None:
		for x in qSWCri:
			if x.type == 'OSArch':
				result['arch_type'] = x.type_data
			elif x.type == 'OSType':
				result['os_type'] = x.type_data
			elif x.type == 'OSVersion':
				result['os_vers'] = x.type_data

		return result
	else:
		return None

'''
-------------------------------------------------
	Packages
-------------------------------------------------
'''

@software.route('/packages')
@login_required
def packages():
	# MpSoftware
	colsForQuery = ['suuid','sw_url','sName','sVersion','sReboot','sState','sw_type','sw_size','mdate']
	colsToHide = ['suuid','sw_url']

	options = {2:"Production",1:"QA",0:"Create",3:"Disabled"}

	qGet 	 = MpSoftware.query.order_by(MpSoftware.mdate.desc()).all()
	qGetCols = MpSoftware.__table__.columns
	qGetColsSorted = sorted(qGetCols, key=getDoc)

	_data = []
	for d in qGet:
		row = {}
		for c in colsForQuery:
			if c in ('mdate'):
				row[c] = eval("d."+c).strftime("%Y-%m-%d %H:%M:%S")
			elif c == 'sReboot':
				_a = eval("d."+c)
				row[c] = "Yes" if _a == 1 else "No"
			elif c == 'sState':
				_a = eval("d."+c)
				row[c] = options[_a]
			elif c == 'sw_size':
				_a = eval("d."+c)
				row[c] = humansize(_a * 1024)
			else:
				row[c] = eval("d."+c)

		_data.append(row)

	_columns = []
	for c in qGetColsSorted:
		if c.name in colsForQuery:
			row = {}
			row['field'] = c.name
			row['title'] = c.info
			row['sortable'] = True
			if c.name in colsToHide:
				row['visible'] = False

			_columns.append(row)

	return render_template('software/software_packages.html', data={'rows':_data,'columns':_columns}, isAdmin='True')

@software.route('/package/add')
@login_required
def addSWPackage():
	# MpSoftware

	_data = {}
	_data['SUUID'] = str(uuid.uuid4())
	_data['PKG'] = None
	_data['PKGCRI_OSArch'] = None
	_data['PKGCRI_OSType'] = None
	_data['PKGCRI_OSVer'] = None
	_data['SWLIST'] = []

	qGet1 = MpSoftware.query.all()
	for s in qGet1:
		if s.suuid == id:
			_data['PKG'] = s

		_data['SWLIST'].append((s.suuid,s.sName))

	_data['PKGCRILEN'] = 0
	_data['PKGPREREQ'] = []
	_data['PKGPOSTREQ'] = []

	_patchBundleIDs = []
	qGet3 = MpPatch.query.all()
	for y in qGet3:
		_patchBundleIDs.append((y.bundle_id,y.patch_name))

	_data['BUNDLEIDS'] = _patchBundleIDs

	return render_template('software/software_pkg_wizard.html', data=_data, isAdmin='True')

@software.route('/package/edit/<id>')
@login_required
def editSWPackage(id):
	# MpSoftware

	_data = {}
	_data['SUUID'] = id
	_data['PKG'] = None
	_data['PKGCRI_OSArch'] = None
	_data['PKGCRI_OSType'] = None
	_data['PKGCRI_OSVer'] = None
	_data['SWLIST'] = []

	#qGet1 = MpSoftware.query.all()
	qGet1 = MpSoftware.query.filter(MpSoftware.suuid == id).all()
	for s in qGet1:
		if s.suuid == id:
			_data['PKG'] = s

		_data['SWLIST'].append((s.suuid,s.sName))

	qGet2 = MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == id).all()
	for x in qGet2:
		if x.type == 'OSArch':
			_data['PKGCRI_OSArch'] = x.type_data
		elif x.type == 'OSType':
			_data['PKGCRI_OSType'] = x.type_data
		elif x.type == 'OSVersion':
			_data['PKGCRI_OSVer'] = x.type_data

	_data['PKGCRILEN'] = len(qGet2)

	_preReq  = []
	_postReq = []
	swReqPre = MpSoftwareRequisits.query.join(MpSoftware, MpSoftware.suuid == MpSoftwareRequisits.suuid_ref).add_columns(MpSoftware.sName).filter(MpSoftwareRequisits.suuid == id, MpSoftwareRequisits.type == 0).order_by(MpSoftwareRequisits.type_order.asc()).all()
	swReqPst = MpSoftwareRequisits.query.join(MpSoftware, MpSoftware.suuid == MpSoftwareRequisits.suuid_ref).add_columns(MpSoftware.sName).filter(MpSoftwareRequisits.suuid == id, MpSoftwareRequisits.type == 1).order_by(MpSoftwareRequisits.type_order.asc()).all()

	for r in swReqPre:
		_pre = {}
		_pre['suuid'] = r[0].suuid_ref
		_pre['name'] = r.sName
		_pre['order'] = r[0].type_order
		_preReq.append(_pre)

	for r in swReqPst:
		_post = {}
		_post['suuid'] = r[0].suuid_ref
		_post['name'] = r.sName
		_post['order'] = r[0].type_order
		_postReq.append(_post)

	_data['PKGPREREQ'] = _preReq
	_data['PKGPOSTREQ'] = _postReq

	_patchBundleIDs = []
	qGet3 = MpPatch.query.all()
	for y in qGet3:
		_patchBundleIDs.append((y.bundle_id,y.patch_name))

	_data['BUNDLEIDS'] = _patchBundleIDs

	return render_template('software/software_pkg_wizard.html', data=_data, isAdmin='True')

''' AJAX Method '''
@software.route('/package/save', methods=['POST'])
def saveSWPackage():

	# Check for SUUID, if missing gen one
	# it should be a new sw item
	_suuid = request.form.get('suuid')
	if _suuid is None:
		_suuid = str(uuid.uuid4())

	''' Process Requisists '''
	_reqsPre = []
	_reqsPost = []
	for v in request.form:
		if "preSWPKG_Order_" in v or "postSWPKG_Order_" in v:
			_rowPre = {}
			_rowPost = {}
			x = 0
			if "preSWPKG_Order_" in v:
					x = v.split("_")[-1]
					_rowPre['suuid'] = _suuid
					_rowPre['suuid_ref'] = eval("request.form.get('preSWPKG_"+x+"')")
					_rowPre['type'] = 0
					_rowPre['type_txt'] = "PRE"
					_rowPre['type_order'] = eval("request.form.get('preSWPKG_Order_"+x+"')")
					_reqsPre.append(_rowPre)

			elif "postSWPKG_Order_" in v:
					x = v.split("_")[-1]
					_rowPost['suuid'] = _suuid
					_rowPost['suuid_ref'] = eval("request.form.get('postSWPKG_"+x+"')")
					_rowPost['type'] = 1
					_rowPost['type_txt'] = "POST"
					_rowPost['type_order'] = eval("request.form.get('postSWPKG_Order_"+x+"')")
					_reqsPost.append(_rowPost)

	_new = False
	qSW = MpSoftware.query.filter(MpSoftware.suuid == _suuid).first()
	qSWC = MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == _suuid).all()
	qSWR = MpSoftwareRequisits.query.filter(MpSoftwareRequisits.suuid == _suuid).all()
	if not qSW:
		_new = True
		qSW = MpSoftware()
		setattr(qSW, 'suuid', _suuid)
		setattr(qSW, 'cdate', datetime.now())

	for v in request.form:
		if v != 'suuid':
			setattr(qSW, v, request.form[v])

	setattr(qSW, 'mdate', datetime.now())

	if qSWC:
		for c in qSWC:
			db.session.delete(c)

	''' Criteria '''
	qSWCAdd = MpSoftwareCriteria()
	setattr(qSWCAdd, 'type', 'OSType')
	setattr(qSWCAdd, 'type_data', request.form['req_os_type'])
	setattr(qSWCAdd, 'type_order', 1)
	setattr(qSWCAdd, 'suuid', _suuid)
	db.session.add(qSWCAdd)

	qSWCAdd = MpSoftwareCriteria()
	setattr(qSWCAdd, 'type', 'OSVersion')
	setattr(qSWCAdd, 'type_data', request.form['req_os_ver'])
	setattr(qSWCAdd, 'type_order', 2)
	setattr(qSWCAdd, 'suuid', _suuid)
	db.session.add(qSWCAdd)

	qSWCAdd = MpSoftwareCriteria()
	setattr(qSWCAdd, 'type', 'OSArch')
	setattr(qSWCAdd, 'type_data', request.form['req_os_arch'])
	setattr(qSWCAdd, 'type_order', 3)
	setattr(qSWCAdd, 'suuid', _suuid)
	db.session.add(qSWCAdd)

	''' Requisits '''
	if qSWR:
		for r in qSWR:
			db.session.delete(r)

	if len(_reqsPre) >= 1 or len(_reqsPost) >= 1:

		for rpre in _reqsPre:
			qSWRAdd = MpSoftwareRequisits()
			for k, v in list(rpre.items()):
				setattr(qSWRAdd, k, v)

			db.session.add(qSWRAdd)

		for rpst in _reqsPost:
			qSWRAdd = MpSoftwareRequisits()
			for k, v in list(rpst.items()):
				setattr(qSWRAdd, k, v)

			db.session.add(qSWRAdd)

	'''
		Save the img file
	'''
	_imgFile = None
	_imgFileData = None
	if 'sw_img_path' in request.files:
		_imgFile = request.files['sw_img_path']
		_imgFileData = saveImageFile(_suuid, _imgFile)

	if _imgFileData is not None:
		if _imgFileData['filePath'] is not None:
			setattr(qSW, 'sw_img_path', _imgFileData['filePath'])

	'''
		Save the pkg file
	'''
	_file = None
	_fileData = None
	if 'mainPackage' in request.files:
		mainFile = request.files['mainPackage']
		_fileData = saveSoftwareFile(_suuid, mainFile)

	# Save SW Package Info
	if _fileData is not None:
		if _fileData['fileName'] is not None:
			setattr(qSW, 'sw_size', _fileData['fileSize'])
			setattr(qSW, 'sw_hash', _fileData['fileHash'].upper())
			setattr(qSW, 'sw_path', _fileData['filePath'])
			setattr(qSW, 'sw_url', _fileData['fileURL'])

	if _new:
		db.session.add(qSW)

	db.session.commit()
	return {'error': 0}, 200

''' Private '''
def saveSoftwareFile(suuid, file):

	result = {}
	result['fileName'] = None
	result['filePath'] = None
	result['fileURL']  = None
	result['fileHash'] = None
	result['fileSize'] = 0

	# Save uploaded files
	upload_dir = os.path.join(current_app.config['SW_CONTENT_DIR'], suuid)
	if not os.path.isdir(upload_dir):
		os.makedirs(upload_dir)

	if file is not None and len(file.filename) > 4:
		filename = secure_filename(file.filename)
		_file_path = os.path.join(upload_dir, filename)
		result['fileName'] = filename
		result['filePath'] = _file_path
		result['fileURL']  = os.path.join('/sw', suuid, filename)

		if os.path.exists(_file_path):
			log_Info('Removing existing file (%s)' % (_file_path))
			os.remove(_file_path)

		file.save(_file_path)

		md5 = hashlib.md5()
		with open(_file_path,'rb') as f: 
			for chunk in iter(lambda: f.read(8192), b''): 
				md5.update(chunk)

		result['fileHash'] = md5.hexdigest()
		result['fileSize'] = (os.path.getsize(_file_path)/float(1000))

	return result

def saveImageFile(suuid, file):

	result = {}
	result['filePath'] = None

	# Save uploaded files
	upload_dir = os.path.join(current_app.config['SW_CONTENT_DIR'], suuid)
	if not os.path.isdir(upload_dir):
		os.makedirs(upload_dir)

	if file is not None and len(file.filename) > 4:
		filename = secure_filename(file.filename)
		_file_path = os.path.join(upload_dir, filename)
		result['filePath'] = os.path.join('/sw', suuid, filename)

		if os.path.exists(_file_path):
			log_Info('Removing existing file (%s)' % (_file_path))
			os.remove(_file_path)

		log_Info("Saving image file {}".format(_file_path))
		file.save(_file_path)

	return result

''' AJAX Method '''
@software.route('/package/duplicate/<id>')
def duplicateSWPackage(id):

	_suuid = str(uuid.uuid4())
	qSW = MpSoftware.query.filter(MpSoftware.suuid == id).first()
	qSWC = MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == id).all()
	qSWR = MpSoftwareRequisits.query.filter(MpSoftwareRequisits.suuid == id).all()

	if qSW is not None:
		db.session.expunge(qSW)
		make_transient(qSW)
		qSW.rid = ''
		qSW.suuid = _suuid
		qSW.sName = "%s_copy" % (qSW.sName)
		db.session.add(qSW)

	if qSWC is not None:
		for c in qSWC:
			db.session.expunge(c)
			make_transient(c)
			c.rid = ''
			c.suuid = _suuid
			db.session.add(c)

	if qSWR is not None:
		for r in qSWR:
			db.session.expunge(r)
			make_transient(r)
			c.rid = ''
			c.suuid = _suuid
			db.session.add(r)

	db.session.commit()

	return json.dumps({'error': 0}), 200

''' AJAX Method '''
@software.route('/package/delete/<id>')
def deleteSWPackage(id):

	qSW = MpSoftware.query.filter(MpSoftware.suuid == id).first()
	qSWC = MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == id).all()
	qSWR = MpSoftwareRequisits.query.filter(MpSoftwareRequisits.suuid == id).all()

	sw_path = qSW.sw_path
	if os.path.exists(sw_path):
		parDir = os.path.dirname(sw_path)
		log_Info('Removing sw package file (%s)' % (sw_path))
		if os.path.exists(parDir):
			try:
				shutil.rmtree(parDir)
			except OSError as e:
				log_Error("Error Delete Dir: %s - %s." % (e.filename, e.strerror))

	db.session.delete(qSW)

	if qSWC:
		for c in qSWC:
			db.session.delete(c)

	if qSWR:
		for c in qSWR:
			db.session.delete(c)

	db.session.commit()

	return json.dumps({'error': 0}), 200


'''
-------------------------------------------------
	Global
-------------------------------------------------
'''
def getDoc(col_obj):
	if col_obj.doc is None:
		return 0
	else:
		return col_obj.doc

def isOwnerOfSWGroup(id):

	result = False
	# If User is admin user then, user can do anything
	if session.get('role')[0] == 1:
		return True

	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()

	if usr:
		pgroup = MpSoftwareGroupPrivs.query.filter(MpSoftwareGroupPrivs.gid == id).first()
		if pgroup:
			if pgroup.uid == usr.user_id:
				if pgroup.isowner == 1:
					result = True

	return result

def isAdminForSWGroup(id):

	result = False
	# If User is admin user then, user can do anything
	if session.get('role')[0] == 1:
		return True

	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()

	if usr:
		q_admin = MpSoftwareGroupPrivs.query.filter(MpSoftwareGroupPrivs.gid == id).all()
		if q_admin:
			for row in q_admin:
				if row.uid == usr.user_id:
					result = True
					break

	return result

suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
def humansize(nbytes):
	if nbytes == 0:
		return '0 B'
	i = 0
	while nbytes >= 1024 and i < len(suffixes)-1:
		nbytes /= 1024.
		i += 1
	f = ('%.2f' % nbytes).rstrip('0').rstrip('.')
	return '%s %s' % (f, suffixes[i])
