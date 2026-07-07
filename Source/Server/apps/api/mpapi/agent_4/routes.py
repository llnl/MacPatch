from flask import request, abort, current_app
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from sqlalchemy import text
from distutils.version import LooseVersion, StrictVersion
from werkzeug.utils import secure_filename
from datetime import datetime
from ast import literal_eval
import sys
import plistlib
import json

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *
from mpapi.servers_2.routes import serverListForID, suServerListForID
from mpapi.agent.routes import AgentUpdates
from mpapi.extensions import cache

parser = reqparse.RequestParser()

class _AgentConfig(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(_AgentConfig, self).__init__()

	def get(self, client_id):
		try:
			if not isValidClientID(client_id):
				log_Error('[AgentConfig][GET]: Failed to verify ClientID (' + client_id + ')')
				return {'result': '', 'errorno': 424, 'errormsg': 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[AgentConfig][GET]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[AgentConfig][GET]: Failed to verify Signature for client (' + client_id + ')')
					return {'result': '', 'errorno': 424, 'errormsg': 'Failed to verify Signature'}, 424

			qClient = MpClient.query.filter(MpClient.cuuid == client_id).first()

			# Return Payload Struct
			agentConfig = {'schema': 330, 'revs': {}, 'settings': { 'agent': { 'rev': 0, 'data': {} }, 'servers': { 'rev': 0, 'data': [] },
													'suservers': {'rev': 0, 'data': []}, 'tasks': { 'rev': 0, 'data': [] }, 'software': {'data': []} }}

			d_revs = {'agent':0,'servers':0,'suservers':0,'tasks':0,'swrestrictions':0}
			d_agent = {}

			group_id = 0
			qGroupMembership = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_id).first()
			if qGroupMembership is not None:
				group_id = qGroupMembership.group_id
			else:
				# No Group Membership, return Default for now
				qGroup = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
				group_id = qGroup.group_id


			#qAgentSettings= MpClientSettings.query.filter(MpClientSettings.group_id == group_id).all()
			#if qAgentSettings is not None:
			#	for row in qAgentSettings:
			#		if row.key == "patch_group":
			#			d_agent["patch_group_id"] = row.value
			#			d_agent[row.key] = self.patchGroupName(row.value)
			#		elif row.key == "inherited_software_group":
			#			d_agent["inherited_software_group_id"] = row.value
			#			d_agent[row.key] = self.swGroupName(row.value)
			#		elif row.key == "software_group":
			#			d_agent["software_group_id"] = row.value
			#			d_agent[row.key] = self.swGroupName(row.value)
			#		else:
			#			d_agent[row.key] = row.value

			# New Agent Settings for Client Group
			qAgentSettings= MpClientSettings.query.filter(MpClientSettings.group_id == group_id).all()
			if qAgentSettings is not None:
				pass


			qClientGroup = MpClientGroups.query.filter(MpClientGroups.group_id == group_id).first()
			if qClientGroup is not None:
				d_agent['client_group'] = qClientGroup.group_name
				d_agent['client_group_id'] = group_id

			d_revs['agent'] = self.agentSettingsRev(group_id)
			agentConfig['settings']['agent']['rev'] = d_revs['agent']
			agentConfig['settings']['agent']['data'] = d_agent

			_serversData = serverListForID(1)
			agentConfig['settings']['servers']['rev'] = _serversData['version']
			agentConfig['settings']['servers']['data'] = _serversData['data']
			d_revs['servers'] = _serversData['version']

			if qClient is not None:
				_suserversData = suServerListForID(1, qClient.osver)
				agentConfig['settings']['suservers']['rev'] = _suserversData['version']
				agentConfig['settings']['suservers']['data'] = _suserversData['data']
				d_revs['suservers'] = _suserversData['version']

			agentConfig['settings']['tasks'] = self.getTasksData(group_id)
			d_revs['tasks'] = agentConfig['settings']['tasks']['rev']

			sw_data = self.clientGroupSoftwareTasks(client_id)
			agentConfig['settings']['software']['data'] = []

			agentConfig['revs'] = d_revs

			if group_id != 0:
				return {"errorno": 0, "errormsg": 'none', "result": {'type': 'AgentConfig', 'data': agentConfig}, 'signature': signData(json.dumps(agentConfig))}, 200
			else:
				return {"errorno": 404, "errormsg": 'Settings version or client group membersion not found.', "result": {'type': 'AgentConfig', 'data': {}}}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentConfig][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def agentSettingsRev(self,group_id):
		qGroupInf = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
		return qGroupInf.rev_settings

	def swGroupName(self, id):
		res = MpSoftwareGroup.query.filter(MpSoftwareGroup.gid == id).first()
		if res is not None:
			return res.gName
		else:
			return "NA"

	def patchGroupName(self, id):
		res = MpPatchGroup.query.filter(MpPatchGroup.id == id).first()
		if res is not None:
			return res.name
		else:
			return "NA"

	def getTasksData(self, group_id):

		result = {'rev': 0, 'data': []}
		tasks = []
		qGroupInf = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
		result['rev'] = qGroupInf.rev_tasks

		qTasks = MpClientTasks.query.filter(MpClientTasks.group_id == group_id).all()
		for row in qTasks:
			tasks.append(row.asDict)

		result['data'] = tasks
		return result

	def clientGroupSoftwareTasks(self, client_id):
		try:

			res = []
			client_obj = MpClient.query.filter(MpClient.cuuid == client_id).first()
			client_group = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_obj.cuuid).first()

			if client_group is not None:
				swids_Obj = MpClientGroupSoftware.query.filter(MpClientGroupSoftware.group_id == client_group.group_id).all()
				for i in swids_Obj:
					res.append({'tuuid':i.tuuid})

			return res

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentBase_v2][softwareTasksForClientGroup][Exception][Line: %d] client_id: %s Message: %s' % (exc_tb.tb_lineno, client_id, message))
			return []

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


# Add Routes Resources
agent_4_api.add_resource(_AgentConfig,          '/agent/config/data/<string:client_id>')