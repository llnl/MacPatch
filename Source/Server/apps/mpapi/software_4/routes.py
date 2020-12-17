from flask import request,current_app
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
from distutils.version import LooseVersion
import base64

from flask_sqlalchemy_cache import FromCache

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *
from .. wsresult import *
from .. extensions import cache
#from .. shared.software import *

parser = reqparse.RequestParser()

import time, datetime
def nowString():
    # we want something like '2007-10-18 14:00+0100'
    mytz="%+4.4d" % (time.timezone / -(60*60) * 100) # time.timezone counts westwards!
    dt  = datetime.datetime.now()
    dts = dt.strftime('%Y-%m-%d %H:%M')  # %Z (timezone) would be empty
    nowstring="%s%s" % (dts,mytz)
    return nowstring

# REST Software Methods
class SoftwareTasksForGroup(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareTasksForGroup, self).__init__()

	def get(self, clientID, groupName, osver="*"):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'SoftwareTask'
		wsResult.result = wsData

		try:
			if self.req_agent == 'iLoad':
				log_Info("[SoftwareTasksForGroup][Get]: iLoad Request from %s" % (clientID))
			else:
				if not isValidClientID(clientID):
					log_Error('[SoftwareTasksForGroup][Get]: Failed to verify ClientID (%s)' % (clientID))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify ClientID'), 424

				if not isValidSignature(self.req_signature, clientID, self.req_uri, self.req_ts):
					log_Error('[SoftwareTasksForGroup][Get]: Failed to verify Signature for client (%s)' % (clientID))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify Signature'), 424

			log_Debug("[SoftwareTasksForGroup][Get][%s]: Args: groupName=%s, osver=%s" % (clientID, groupName, osver))

			_group_id = None
			_group_data = None
			q_sw_group = MpSoftwareGroup.query.filter(MpSoftwareGroup.gName == groupName).first()
			if q_sw_group is not None and q_sw_group.gid is not None:
				_group_id = q_sw_group.gid
			else:
				log_Error('[SoftwareTasksForGroup][Get][%s] Group (%s) Not Found' % (clientID, groupName))
				return wsResult.resultNoSignature(errorno=404, errormsg='Group Not Found'), 404

			tData = tasksForGroup(_group_id, osver)
			wsData.data = tData
			wsResult.data = wsData.toDict()
			return wsResult.resultNoSignature(), 202

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SoftwareTasksForGroup][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, clientID, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# ----------------------------------
# Private
# ----------------------------------

def tasksForGroup(group, osFilter='*'):

	_tasks = []
	_curApp = current_app
	qGetSel = MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.sw_group_id == group, MpSoftwareGroupTasks.selected == 1).all()

	_selected = []
	for s in qGetSel:
		_selected.append(s.sw_task_id)

	# Get All SW Tasks
	qSWTasks = MpSoftwareTask.query.filter(MpSoftwareTask.active == 1).all()


	_qTasks = []
	for t in qSWTasks:
		_qTasks.append(t.asDict)

	# Get All SW
	qSW = MpSoftware.query.options(FromCache(cache)).all()
	_qSW = []
	for s in qSW:
		_qSW.append(s.asDict)

	# Get All Criteria
	qSWCri = MpSoftwareCriteria.query.options(FromCache(cache)).all()
	_qSWC = []
	for c in qSWCri:
		_qSWC.append(c.asDict)

	for t in _selected:
		taskData = swTaskDataNew(t,_qTasks)
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
			swData = swPackageDataNew(taskData['primary_suuid'],_qSW)
			if swData is not None:
				_task['Software'] = swData

			_task['SoftwareCriteria'] = {}
			swCrit = swPackageCriteriaNew(taskData['primary_suuid'],_qSWC)

			_addSwTask = 0
			if swCrit is not None:
				if 'os_vers' in swCrit:
					_os_vers = swCrit['os_vers']
					if osFilter != '*':
						_osFilter=osFilter.replace('*','')
						for allowedOS in _os_vers.split(','):
							if allowedOS == '*':
								_addSwTask=_addSwTask+1
								break
							else:
								allowedOS = allowedOS.replace(".*","")
								#print("{} in {}".format(allowedOS,_osFilter))
								if allowedOS in _osFilter:
									_addSwTask = _addSwTask + 1
									break
					else:
						_addSwTask = _addSwTask + 1
				else:
					continue
				_task['SoftwareCriteria'] = swCrit
			else:
				_task['SoftwareCriteria'] = {}


			_task['SoftwareRequisistsPre'] = {}
			_task['SoftwareRequisistsPost'] = {}

			if _addSwTask >= 1:
				_tasks.append(_task)

	return _tasks

def swTaskDataNew(taskID, tasks):
	for t in tasks:
		if taskID == t['tuuid']:
			return t

	return None

def swPackageDataNew(swID, sw):

	for s in sw:
		if swID == s['suuid']:
			swp = {"name": s['sName'],
				  "vendor": s['sVendor'],
				  "vendorUrl": s['sVendorURL'],
				  "version": s['sVersion'],
				  "description": s['sDescription'],
				  "reboot": str(s['sReboot']),
				  "sw_type": str(s['sw_type']),
				  "sw_url": s['sw_url'],
				  "sw_hash": s['sw_hash'],
				  "sw_size": str(s['sw_size']),
				  "sw_pre_install": b64EncodeAsString(s['sw_pre_install_script'], ''),
				  "sw_post_install": b64EncodeAsString(s['sw_post_install_script'], ''),
				  "sw_uninstall": b64EncodeAsString(s['sw_uninstall_script'], ''),
				  "sw_env_var": s['sw_env_var'],
				  "auto_patch": str(s['auto_patch']),
				  "patch_bundle_id": s['patch_bundle_id'],
				  "state": str(s['sState']),
				  "sid": str(s['suuid']),
				  "sw_img_path": str(s['sw_img_path']),
				  "sw_app_path": str(s['sw_app_path'] or 'None')}
			return swp

	return None

def swPackageCriteriaNew(swID, criteria):

	_cList = []
	for c in criteria:
		if c['suuid'] == swID:
			_cList.append(c)

	result = {}
	if len(_cList) >= 1:
		for x in _cList:
			if x['type'] == 'OSArch':
				result['arch_type'] = x['type_data']
			elif x['type'] == 'OSType':
				result['os_type'] = x['type_data']
			elif x['type'] == 'OSVersion':
				result['os_vers'] = x['type_data']

		return result

	return None

# Add Routes Resources
software_4_api.add_resource(SoftwareTasksForGroup,		'/sw/tasks/<string:clientID>/<string:groupName>')
software_4_api.add_resource(SoftwareTasksForGroup,		'/sw/tasks/<string:clientID>/<string:groupName>/<string:osver>', endpoint='swTasksFilter')