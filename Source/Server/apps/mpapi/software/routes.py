from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
from distutils.version import LooseVersion
import base64

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

# REST Software Methods
class SoftwareTasksForGroup(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareTasksForGroup, self).__init__()

	def get(self, cuuid, groupName, osver="*"):

		try:
			if self.req_agent == 'iLoad':
				log_Info("[SoftwareTasksForGroup][Get]: iLoad Request from %s" % (cuuid))
			else:
				if not isValidClientID(cuuid):
					log_Error('[SoftwareTasksForGroup][Get]: Failed to verify ClientID (%s)' % (cuuid))
					# return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

				if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
					log_Error('[SoftwareTasksForGroup][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			log_Debug("[SoftwareTasksForGroup][Get][%s]: Args: groupName=%s, osver=%s" % (cuuid, groupName, osver))

			_group_id = None
			_group_data = None
			q_sw_group = MpSoftwareGroup.query.filter(MpSoftwareGroup.gName == groupName).first()
			if q_sw_group is not None and q_sw_group.gid is not None:
				_group_id = q_sw_group.gid
			else:
				log_Error('[SoftwareTasksForGroup][Get][%s] Group (%s) Not Found' % (cuuid, groupName))
				return {'errorno': 404, 'errormsg': 'Group Not Found', 'result': ''}, 404

			if _group_id is not None:
				q_sw_group_data = MpSoftwareTasksData.query.filter(MpSoftwareTasksData.gid == _group_id).first()
				if q_sw_group_data is not None and q_sw_group_data.gData is not None:
					_group_data = json.loads(q_sw_group_data.gData)

			_tasks_new = []
			_tasksData = []
			_tasksData = _group_data['result']['Tasks']

			if osver != "*":
				_result = _group_data['result']
				_tasks = _result['Tasks']
				for task in _tasks:
					_sw_criteria = task['SoftwareCriteria']
					if not _sw_criteria:
						log_Error('[SoftwareTasksForGroup][Get][%s] SW Task (%s) does not contain any criteria.' % (cuuid, task['id']))
						continue

					_os_vers = _sw_criteria['os_vers']
					if _os_vers == "*":
						_tasks_new.append(task)
						continue

					for v, ver in enumerate(_os_vers.split(',')):
						if LooseVersion(ver) >= LooseVersion(osver):
							_tasks_new.append(task)
							break

				# Replace old list of tasks with new filtered one
				_group_data['result']['Tasks'] = _tasks_new

			if _group_data is not None:
				return {'errorno': 0, 'errormsg': '', 'result': _group_data['result']}, 200
			else:
				log_Error('[SoftwareTasksForGroup][Get][%s] Group (%s) Not Found' % (cuuid, groupName))
				return {'errorno': 0, 'errormsg': 'No Data for Group', 'result': {}}, 202

		except IntegrityError, exc:
			log_Error('[SoftwareTasksForGroup][Get][IntegrityError] CUUID: %s Message: %s' % (cuuid, exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[SoftwareTasksForGroup][Get][Exception][Line: %d] CUUID: %s Message: %s' % (
				exc_tb.tb_lineno, cuuid, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500

class SaveSoftwareTasksForGroup(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SaveSoftwareTasksForGroup, self).__init__()

	def get(self, cuuid, groupID):

		try:
			if self.req_agent == 'iLoad':
				log_Info("[SaveSoftwareTasksForGroup][Get]: iLoad Request from %s" % (cuuid))

			_group_id = None
			_group_data = None
			q_sw_group = MpSoftwareGroup.query.filter(MpSoftwareGroup.gid == groupID).first()
			if q_sw_group is not None and q_sw_group.gid is not None:
				_group_id = q_sw_group.gid
			else:
				log_Error('[SaveSoftwareTasksForGroup][Get][%s] Group (%s) Not Found' % (cuuid, groupID))
				return {'errorno': 404, 'errormsg': 'Group Not Found', 'result': ''}, 404

			if _group_id is not None:
				q_sw_group_data = MpSoftwareTasksData.query.filter(MpSoftwareTasksData.gid == groupID).first()
				if q_sw_group_data is not None and q_sw_group_data.gData is not None:
					_group_data = json.loads(q_sw_group_data.gData)

			_tasks_new = []
			_tasksData = _group_data['result']['Tasks']
			for task in _tasksData:
				#task['sw_signature'] = signData(task['Software'])
				task['sw_signature'] = self.signSoftwareTask(task['Software'])
				_tasks_new.append(task)

			try:
				_group_data['result']['Tasks'] = _tasks_new
				jData = json.dumps(_group_data)
				setattr(q_sw_group_data, 'gData', jData)
				db.session.commit()
				return {"result": {}, "errorno": 0, "errormsg": ''}, 201
			except IntegrityError, exc:
				log_Error('[SaveSoftwareTasksForGroup][Get][IntegrityError][SAVE] CUUID: %s Message: %s' % (cuuid, exc.message))
				db.session.rollback()


		except IntegrityError, exc:
			log_Error('[SaveSoftwareTasksForGroup][Get][IntegrityError] CUUID: %s Message: %s' % (cuuid, exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[SaveSoftwareTasksForGroup][Get][Exception][Line: %d] CUUID: %s Message: %s' % (exc_tb.tb_lineno, cuuid, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500


	def signSoftwareTask(self,data):
		_keys = ['auto_patch','name','patch_bundle_id','reboot','sid','state','sw_env_var','sw_hash','sw_post_install','sw_pre_install','sw_size','sw_type','sw_uninstall','sw_url','vendor','vendorUrl','version']
		_str_to_sign = None
		_str_chunks = []
		for k in _keys:
			_str_chunks.append(data[k])

		_str_to_sign = ''.join(_str_chunks)
		_signed_str = signData(_str_to_sign)
		return _signed_str

class SoftwareTaskForTaskID(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareTaskForTaskID, self).__init__()

	def get(self, cuuid, taskID):

		try:
			if not isValidClientID(cuuid):
				log_Error('[SoftwareTaskForTaskID][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[SoftwareTaskForTaskID][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			log_Debug("[SoftwareTaskForTaskID][Get][%s]: Args: taskID=%s" % (cuuid, taskID))
			q_task = MpSoftwareTask.query.filter(MpSoftwareTask.tuuid == taskID).first()

			task = {}

			if q_task is not None:
				_task = SWTask()
				_task_data = _task.struct()

				for t in _task.keys():
					if t in q_task.__dict__:
						t_Val = eval("q_task." + t)
						if type(t_Val) is not datetime:
							_task_data[t] = t_Val
						else:
							_task_data[t] = t_Val.strftime("%Y-%m-%d %H:%M:%S")
					else:
						# We have a few fields that dont match the model
						# This needs to be fixed in the future
						if t == "suuid":
							_task_data['suuid'] = q_task.primary_suuid
						elif t == "id":
							_task_data['id'] = q_task.tuuid

				task = _task_data

			q_software = MpSoftware.query.filter(MpSoftware.suuid == task['suuid']).first()

			if q_software is not None:
				_sw = Software()
				_sw_data = _sw.struct()
				for s in _sw.keys():
					if s in q_software.__dict__:
						s_Val = eval("q_software." + s)
						if type(s_Val) is not datetime:
							if s == "sw_pre_install" or s == "sw_post_install" or s == "sw_uninstall":
								_sw_data[s] = base64.b64encode(s_Val)
							else:
								_sw_data[s] = s_Val
						else:
							_sw_data[s] = s_Val.strftime("%Y-%m-%d %H:%M:%S")
					else:
						print s
						if s == "vendorUrl":
							_sw_data['vendorUrl'] = eval("q_software.sVendorURL")

						elif s == "description":
							_sw_data['description'] = eval("q_software.sDescription")

						elif s == "vendor":
							_sw_data['vendor'] = eval("q_software.sVendor")

						elif s == "name":
							_sw_data['name'] = eval("q_software.sName")

						elif s == "state":
							_sw_data['state'] = eval("q_software.sState")

						elif s == "reboot":
							_sw_data['reboot'] = eval("q_software.sReboot")

						elif s == "version":
							_sw_data['version'] = eval("q_software.sVersion")

						elif s == "sid":
							_sw_data['sid'] = eval("q_software.suuid")

						elif s == "sw_post_install":
							_sw_data['sw_post_install'] = base64.b64encode(eval("q_software.sw_post_install_script"))

						elif s == "sw_uninstall":
							_sw_data['sw_uninstall'] = base64.b64encode(eval("q_software.sw_uninstall_script"))

						elif s == "sw_pre_install":
							_sw_data['sw_pre_install'] = base64.b64encode(eval("q_software.sw_pre_install_script"))

				task['Software'] = _sw_data

			q_software_cri = MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == task['suuid']).order_by(MpSoftwareCriteria.type_order.asc()).all()
			if q_software_cri is not None:
				_sw_cri = SoftwareCritera()
				_sw_cri_data = _sw_cri.struct()
				for row in q_software_cri:
					if row.type == "OSType":
						_sw_cri_data['os_type'] = row.type_data

					elif row.type == "OSArch":
						_sw_cri_data['arch_type'] = row.type_data

					elif row.type == "OSVersion":
						_sw_cri_data['os_vers'] = row.type_data

				task['SoftwareCriteria'] = _sw_cri_data

			return {"result": task, "errorno": 0, "errormsg": ''}, 200

		except IntegrityError, exc:
			log_Error('[SoftwareTaskForTaskID][Get][IntegrityError] CUUID: %s Message: %s' % (cuuid, exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[SoftwareTaskForTaskID][Get][Exception][Line: %d] CUUID: %s Message: %s' % (
				exc_tb.tb_lineno, cuuid, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500

class SoftwareDistributionGroups(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareDistributionGroups, self).__init__()

	def get(self, cuuid, state='1'):

		try:
			if self.req_agent == 'iLoad':
				log_Info("[SoftwareDistributionGroups][Get]: iLoad Request from %s" % (cuuid))
			else:
				if not isValidClientID(cuuid):
					log_Error('[SoftwareDistributionGroups][Get]: Failed to verify ClientID (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

				if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
					log_Error('[SoftwareDistributionGroups][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			if int(state) == 1 or int(state) == 2:
				q_sw_groups = MpSoftwareGroup.query.filter(MpSoftwareGroup.state == state).all()
			elif int(state) == 3:
				q_sw_groups = MpSoftwareGroup.query.filter(MpSoftwareGroup.state >= 1).all()
			else:
				log_Error('[SoftwareDistributionGroups][Get][%s]: Not valid state selected (%s)' % (cuuid, state))

			_groups = []
			if q_sw_groups is not None:
				for row in q_sw_groups:
					_group = {"Name": row.gName, "Desc": row.gDescription}
					_groups.append(_group)

			if len(_groups) >= 1:
				return {"result": _groups, "errorno": 0, "errormsg": ''}, 200
			else:
				log_Error('[SoftwareDistributionGroups][Get][%s]: Not groups found.' % (cuuid))
				return {"result": '', "errorno": 0, "errormsg": ''}, 404

		except IntegrityError, exc:
			log_Error('[SoftwareDistributionGroups][Get][IntegrityError] CUUID: %s Message: %s' % (cuuid, exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[SoftwareDistributionGroups][Get][Exception][Line: %d] CUUID: %s Message: %s' % (
				exc_tb.tb_lineno, cuuid, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500

class SoftwareInstallResult(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareInstallResult, self).__init__()

	def post(self, cuuid):

		try:
			if not isValidClientID(cuuid):
				log_Error('[SoftwareInstallResult][Post]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, request.data, self.req_ts):
				log_Error('[SoftwareInstallResult][Post]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			_sw_arr = ["SWTaskID", "SWDistID", "ResultNo", "ResultString", "Action"]
			_sw_col = ["tuuid", "suuid", "result", "resultString", "action"]
			jData = request.get_json(force=True)
			if jData is not None:
				log_Debug('[SoftwareInstallResult][Post][%s]:jData=%s' % (cuuid, jData))
				sw_install = MpSoftwareInstall()
				setattr(sw_install, 'cuuid', cuuid)
				setattr(sw_install, 'cdate', datetime.now())
				for idx, attr in enumerate(_sw_arr):
					if str(jData[attr]):
						setattr(sw_install, _sw_col[idx], jData[attr])

				try:
					db.session.add(sw_install)
					db.session.commit()
				except IntegrityError, exc:
					db.session.rollback()
			else:
				log_Error('[SoftwareInstallResult][Post][%s]:jData=%s' % (cuuid, jData))
				log_Error('[SoftwareInstallResult][Post][%s]: No data found to post.' % (cuuid))
				return {'errorno': 404, "errormsg": "No data found to post.", "result": ""}, 404

			return {'errorno': 0, "errormsg": "", "result": ""}, 201

		except IntegrityError, exc:
			log_Error('[SoftwareInstallResult][Post][IntegrityError] CUUID: %s Message: %s' % (cuuid, exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[SoftwareInstallResult][Post][Exception][Line: %d] CUUID: %s Message: %s' % (
				exc_tb.tb_lineno, cuuid, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500

# ----------------------------------
# Private Class
# ----------------------------------
class Software(object):
	def __init__(self):
		self.name = "1"
		self.vendor = "0"
		self.vendorUrl = "o"
		self.version = "Global"
		self.description = "2000-01-01 00:00:00"
		self.reboot = "2000-01-01 00:00:00"
		self.sw_type = "0"
		self.sw_url = ""
		self.sw_hash = ""
		self.sw_size = ""
		self.sw_pre_install = ""
		self.sw_post_install = ""
		self.sw_uninstall = ""
		self.sw_env_var = ""
		self.auto_patch = ""
		self.patch_bundle_id = ""
		self.state = ""
		self.sid = ""

	def struct(self):
		return(self.__dict__)

	def keys(self):
		return self.__dict__.keys()

class SWTask(object):
	def __init__(self):
		self.name = "ERROR"
		self.id = "1000"
		self.sw_task_type = "o"
		self.sw_task_privs = "Global"
		self.sw_start_datetime = "2000-01-01 00:00:00"
		self.sw_end_datetime = "2000-01-01 00:00:00"
		self.active = "0"
		self.suuid = "0"
		self.Software = {}
		self.SoftwareCriteria = {}
		self.SoftwareRequisistsPre = {}
		self.SoftwareRequisistsPost = {}

	def struct(self):
		return(self.__dict__)

	def keys(self):
		return self.__dict__.keys()

class SoftwareCritera(object):
	def __init__(self):
		self.os_type = "Mac OS X, Mac OS X Server"
		self.os_vers = "10.7.*"
		self.arch_type = "PPC,X86"

	def struct(self):
		return(self.__dict__)

	def keys(self):
		return self.__dict__.keys()

# Add Routes Resources
software_api.add_resource(SoftwareTasksForGroup,         '/sw/tasks/<string:cuuid>/<string:groupName>', endpoint='swTasks')
software_api.add_resource(SoftwareTasksForGroup,         '/sw/tasks/<string:cuuid>/<string:groupName>/<string:osver>', endpoint='swTasksFilter')

software_api.add_resource(SoftwareTaskForTaskID,         '/sw/task/<string:cuuid>/<string:taskID>')

software_api.add_resource(SoftwareDistributionGroups,    '/sw/groups/<string:cuuid>', endpoint='woState')
software_api.add_resource(SoftwareDistributionGroups,    '/sw/groups/<string:cuuid>/<string:state>', endpoint='wState')

software_api.add_resource(SoftwareInstallResult,         '/sw/installed/<string:cuuid>')

# Update will be fixed in 3.1, should be done in console
software_api.add_resource(SaveSoftwareTasksForGroup,     '/sw/update/tasks/<string:cuuid>/<string:groupID>')
