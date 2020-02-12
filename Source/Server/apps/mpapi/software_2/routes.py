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
from .. wsresult import *
from .. shared.software import *

parser = reqparse.RequestParser()

# REST Software Methods
class SoftwareTasksForGroup(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareTasksForGroup, self).__init__()

	def get(self, cuuid, groupName, osver="*"):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'SoftwareTask'
		wsResult.result = wsData

		try:
			if self.req_agent == 'iLoad':
				log_Info("[SoftwareTasksForGroup][Get]: iLoad Request from %s" % (cuuid))
			else:
				if not isValidClientID(cuuid):
					log_Error('[SoftwareTasksForGroup][Get]: Failed to verify ClientID (%s)' % (cuuid))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify ClientID'), 424

				if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
					log_Error('[SoftwareTasksForGroup][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify Signature'), 424

			log_Debug("[SoftwareTasksForGroup][Get][%s]: Args: groupName=%s, osver=%s" % (cuuid, groupName, osver))

			_group_id = None
			_group_data = None
			q_sw_group = MpSoftwareGroup.query.filter(MpSoftwareGroup.gName == groupName).first()

			if q_sw_group is not None and q_sw_group.gid is not None:
				_group_id = q_sw_group.gid
			else:
				log_Error('[SoftwareTasksForGroup][Get][%s] Group (%s) Not Found' % (cuuid, groupName))
				return wsResult.resultNoSignature(errorno=404, errormsg='Group Not Found'), 404

			if _group_id is not None:
				q_sw_group_data = MpSoftwareTasksData.query.filter(MpSoftwareTasksData.gid == _group_id).first()
				if q_sw_group_data is not None and q_sw_group_data.gData is not None:
					_group_data = json.loads(q_sw_group_data.gData)


				# if group request is same as client default group append alt group data
				_sw_group_id, _sw_group_alt_id = self.softwareGroupsForClient(cuuid)
				if _sw_group_id == _group_id:
					q_sw_group_alt_data = MpSoftwareTasksData.query.filter(MpSoftwareTasksData.gid == _sw_group_alt_id).first()
					if q_sw_group_alt_data is not None and q_sw_group_alt_data.gData is not None:
						_group_alt_data = json.loads(q_sw_group_alt_data.gData) # Parse the JSON Data
						_merge_list = _group_data['result']['Tasks'] + _group_alt_data['result']['Tasks'] # Merge Both Tasks Lists
						_new_tasks = list({v['id']:v for v in _merge_list}.values()) # Filter out any duplicates

						# Replace old tasks list with new merged list
						_group_data['result']['Tasks'] = _new_tasks

			# gData from database is pre-formatted {"errorNo":"0","errorMsg":"","result":{"Tasks":[]}}
			if osver != "*":
				_tasks_new = []
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
						if "*" in ver:
							_ver = ver.replace('*','')
							if osver in _ver :
								_tasks_new.append(task)
								break
						elif LooseVersion(ver.strip()) == LooseVersion(osver.strip()):
							_tasks_new.append(task)
							break

				# Replace old list of tasks with new filtered one
				_group_data['result']['Tasks'] = _tasks_new

			if _group_data is not None:
				wsData.data = _group_data['result']['Tasks']
				wsResult.data = wsData.toDict()
				return wsResult.resultWithSignature(), 200

			else:
				log_Error('[SoftwareTasksForGroup][Get][%s] Group (%s) Not Found' % (cuuid, groupName))
				return wsResult.resultNoSignature(errorno=1, errormsg='No Data for Group'), 202

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SoftwareTasksForGroup][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def softwareGroupsForClient(self, clientID):

		group_id = 0
		sw_group_id = ''
		sw_group_alt_id = ''

		qGroupMembership = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == clientID).first()
		if qGroupMembership is not None:
			group_id = qGroupMembership.group_id

			qGroupSettings = MpClientSettings.query.filter(MpClientSettings.group_id == group_id).all()
			if qGroupSettings is not None:
				for row in qGroupSettings:
					if row.key == 'software_group':
						sw_group_id = row.value
					elif row.key == 'inherited_software_group':
						sw_group_alt_id = row.value

		return sw_group_id, sw_group_alt_id

class SoftwareTaskForTaskID(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareTaskForTaskID, self).__init__()

	def get(self, cuuid, taskID):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'SoftwareTask'
		wsResult.result = wsData

		try:
			if not isValidClientID(cuuid):
				log_Error('[SoftwareTaskForTaskID][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify ClientID'), 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[SoftwareTaskForTaskID][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify Signature'), 424

			log_Debug("[SoftwareTaskForTaskID][Get][%s]: Args: taskID=%s" % (cuuid, taskID))
			q_task = MpSoftwareTask.query.filter(MpSoftwareTask.tuuid == taskID).first()

			# Main SW Task Data
			task = {}
			if q_task is not None:
				_task = SWTask()
				_task_data = _task.struct()

				for t in list(_task.keys()):
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

			# Software Section of Task
			q_software = MpSoftware.query.filter(MpSoftware.suuid == task['suuid']).first()
			if q_software is not None:
				_sw = Software()
				_sw_data = _sw.struct()
				for s in list(_sw.keys()):
					if s in q_software.__dict__:
						s_Val = eval("q_software." + s)
						if type(s_Val) is not datetime:
							if s == "sw_pre_install" or s == "sw_post_install" or s == "sw_uninstall":
								_sw_data[s] = base64.b64encode(s_Val).decode('utf-8')
							else:
								_sw_data[s] = s_Val
						else:
							_sw_data[s] = s_Val.strftime("%Y-%m-%d %H:%M:%S")
					else:
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
							_sw_data['sw_post_install'] = b64EncodeAsString(rowWithDefault(q_software,"sw_post_install_script",defaultValue=''),defaultValue='')

						elif s == "sw_uninstall":
							_sw_data['sw_uninstall'] = b64EncodeAsString(rowWithDefault(q_software,"sw_uninstall_script",defaultValue=''),defaultValue='')

						elif s == "sw_pre_install":
							_sw_data['sw_pre_install'] = b64EncodeAsString(rowWithDefault(q_software,"sw_pre_install_script",defaultValue=''),defaultValue='')

				task['Software'] = _sw_data

			# Software Criteria Section of Task
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

			# Return Result
			wsData.data = task
			wsResult.data = wsData.toDict()
			return wsResult.resultWithSignature(), 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SoftwareTaskForTaskID][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return wsResult.resultNoSignature(errorno=500, errormsg=message), 500

class SoftwareGroups(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareGroups, self).__init__()

	def get(self, cuuid, state='1'):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'SoftwareGroup'
		wsResult.result = wsData

		try:
			if self.req_agent == 'iLoad':
				log_Info("[SoftwareDistributionGroups][Get]: iLoad Request from %s" % (cuuid))
			else:
				if not isValidClientID(cuuid):
					log_Error('[SoftwareDistributionGroups][Get]: Failed to verify ClientID (%s)' % (cuuid))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify ClientID'), 424

				if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
					log_Error('[SoftwareDistributionGroups][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify Signature'), 424

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
				# Return Result
				wsData.data = _groups
				wsResult.data = wsData.toDict()
				return wsResult.resultWithSignature(), 200

			else:
				log_Error('[SoftwareDistributionGroups][Get][%s]: Not groups found.' % (cuuid))
				return wsResult.resultNoSignature(), 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SoftwareDistributionGroups][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return wsResult.resultNoSignature(errorno=500, errormsg=message), 500

class SoftwareForClientGroup(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareForClientGroup, self).__init__()

	def get(self, client_id):
		try:

			if not isValidClientID(client_id):
				log_Error('[AgentStatus][Get]: Failed to verify ClientID (%s)' % (client_id))
				return {"result": {'data': {}, 'type':'AgentStatus'}, "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES'] == True:
					log_Info('[AgentStatus][Get]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[AgentStatus][Get]: Failed to verify Signature for client (%s)' % (client_id))
					return {"result": {'data': {}, 'type':'AgentStatus'}, "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			res = []
			client_obj = MpClient.query.filter_by(cuuid=client_id).first()
			client_group = MpClientGroupMembers.query.filter_by(cuuid=client_obj.cuuid).first()

			if client_group is not None:
				swids_Obj = MpClientGroupSoftware.query.filter(MpClientGroupSoftware.group_id == client_group.group_id).all()
				for i in swids_Obj:
					res.append({'tuuid':i.tuuid})

			return {"result": {'data': res, 'type':'RequiredSoftware'}, "errorno": 0, "errormsg": 'none'}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentStatus][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {'data': {}, 'type':'AgentStatus'}}, 500

	def criteriaForSUUID(self, suuid):
		res = MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == suuid).all()
		cri = SWObjCri()
		criData = {}
		if res is not None and len(res) >= 1:
			for row in res:
				if row.type == "OSArch":
					criData['os_arch'] = row.type_data
				elif row.type == "OSType":
					criData['os_type'] = row.type_data
				elif row.type == "OSVersion":
					criData['os_vers'] = row.type_data

			cri.importDict(criData)
		return cri.asDict()

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
		self.sw_img_path = ""

	def struct(self):
		return(self.__dict__)

	def keys(self):
		return list(self.__dict__.keys())

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
		return list(self.__dict__.keys())

class SoftwareCritera(object):
	def __init__(self):
		self.os_type = "Mac OS X, Mac OS X Server"
		self.os_vers = "10.7.*"
		self.arch_type = "PPC,X86"

	def struct(self):
		return(self.__dict__)

	def keys(self):
		return list(self.__dict__.keys())

# Add Routes Resources
software_2_api.add_resource(SoftwareTasksForGroup,		'/sw/tasks/<string:cuuid>/<string:groupName>', endpoint='swTasks')
software_2_api.add_resource(SoftwareTasksForGroup,		'/sw/tasks/<string:cuuid>/<string:groupName>/<string:osver>', endpoint='swTasksFilter')

software_2_api.add_resource(SoftwareTaskForTaskID,		'/sw/task/<string:cuuid>/<string:taskID>')

software_2_api.add_resource(SoftwareGroups,				'/sw/groups/<string:cuuid>', endpoint='woState')
software_2_api.add_resource(SoftwareGroups,    			'/sw/groups/<string:cuuid>/<string:state>', endpoint='wState')


software_2_api.add_resource(SoftwareForClientGroup,		'/sw/required/<string:client_id>')

