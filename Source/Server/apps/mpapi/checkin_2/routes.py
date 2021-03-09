from flask import request, current_app
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
import syslog
import hashlib

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

from .. register.routes import Registration

parser = reqparse.RequestParser()

# Client Reg Process
class AgentBase(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		mpc = MpClient()
		for column in mpc.columns:
			self.reqparse.add_argument(column, type=str, required=False, location='json')

		super(AgentBase, self).__init__()

	def post(self, cuuid):

		try:
			args = self.reqparse.parse_args()
			_body = request.get_json(silent=True)
			# Need a check to see if registration is required

			if not isValidSignature(self.req_signature, cuuid, request.data, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[AgentBase][Post]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[AgentBase][Post]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": {}, "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			client_obj = MpClient.query.filter_by(cuuid=cuuid).first()
			log_Debug('[AgentBase][Post]: Client (%s) Data %s' % (cuuid, _body))

			if client_obj:
				# Update
				log_Info('[AgentBase][Post]: Updating client (%s) record.' % (cuuid))
				for col in client_obj.columns:
					if col == 'mdate':
						continue
					elif col == 'fileVaultStatus':
						if 'fileVaultStatus' in args:
							setattr(client_obj, 'fileVaultStatus', args['fileVaultStatus'])
						elif 'fileVault' in _body:
							setattr(client_obj, 'fileVaultStatus', _body['fileVault'])
						else:
							setattr(client_obj, 'fileVaultStatus', "NA")
					else:
						if args[col] is not None:
							_args_Val = args[col]
							if not isinstance(_args_Val, int):
								# Remove any new line chars before adding to DB
								_args_Val = _args_Val.replace('\n', '')

							setattr(client_obj, col, _args_Val)

				setattr(client_obj, 'mdate', datetime.now())

				if client_obj:
					if "POST_CHECKIN_TO_SYSLOG" in current_app.config:
						if current_app.config['POST_CHECKIN_TO_SYSLOG'] == True:
							postClientDataToSysLog(client_obj)

				db.session.commit()

				_settings = self.getClientTasksSettingsRev(cuuid)
				return {"errorno": 0, "errormsg": 'none', "result": _settings}, 201

			else:
				# Add
				log_Info('[AgentBase][Post]: Adding client (%s) record.' % (cuuid))
				client_object = MpClient()

				client_object.cuuid = cuuid
				for col in client_object.columns:
					if col == 'mdate':
						continue
					elif col == 'fileVaultStatus':
						if 'fileVaultStatus' in args:
							# Value is none
							if args['fileVaultStatus'] is not None:
								setattr(client_obj, 'fileVaultStatus', args['fileVaultStatus'])
							else:
								setattr(client_obj, 'fileVaultStatus', "NA")
						elif 'fileVault' in _body:
							setattr(client_obj, 'fileVaultStatus', _body['fileVault'])
						else:
							setattr(client_obj, 'fileVaultStatus', "NA")
					else:
						if args[col] is not None:
							_args_Val = args[col]
							if not isinstance(_args_Val, int):
								# Remove any new line chars before adding to DB
								_args_Val = _args_Val.replace('\n', '')
							setattr(client_object, col, _args_Val)


				setattr(client_object, 'mdate', datetime.now())
				db.session.add(client_object)

				if client_object:
					if "POST_CHECKIN_TO_SYSLOG" in current_app.config:
						if current_app.config['POST_CHECKIN_TO_SYSLOG'] == True:
							postClientDataToSysLog(client_object)

				db.session.commit()

				_settings = self.getClientTasksSettingsRev(cuuid)
				return {"errorno": 0, "errormsg": 'none', "result": _settings}, 201

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentBase][Post][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def getClientTasksSettingsRev(self, cuuid):

		group_id = 0
		versions = {'agent':0,'tasks':0,'servers':0,'suservers':0}
		qGroupMembership = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == cuuid).first()
		if qGroupMembership is not None:
			group_id = qGroupMembership.group_id
		else:
			log_Error("No group assignment")
			group_id = self.addClientToDefaultGroup(cuuid)

		qGroupSettings = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
		if qGroupSettings is not None:
			versions["agent"] = qGroupSettings.rev_settings
			versions["tasks"] = qGroupSettings.rev_tasks

		qMPServers = MpServerList.query.filter(MpServerList.listid == 1).first()
		if qMPServers is not None:
			versions["servers"] = qMPServers.version

		qSUServers = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == 1).first()
		if qSUServers is not None:
			versions["suservers"] = qSUServers.version

		qSWTasksForGroup = self.clientGroupSoftwareTasks(cuuid)
		if qSWTasksForGroup is not None:
			versions["swTasks"] = qSWTasksForGroup
		else:
			versions["swTasks"] = []

		return versions

	def addClientToDefaultGroup(self, cuuid):

		log_Info('[AgentBase][Post]: Adding client (%s) to default client group.' % (cuuid))

		defaultGroup = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
		groupMembership = MpClientGroupMembers()
		setattr(groupMembership, 'cuuid', cuuid)
		setattr(groupMembership, 'group_id', defaultGroup.group_id)
		db.session.add(groupMembership)
		db.session.commit()

		return defaultGroup.group_id

	def clientGroupSoftwareTasks(self, client_id):
		try:

			res = []
			client_obj = MpClient.query.filter_by(cuuid=client_id).first()
			client_group = MpClientGroupMembers.query.filter_by(cuuid=client_obj.cuuid).first()

			if client_group is not None:
				swids_Obj = MpClientGroupSoftware.query.filter(
					MpClientGroupSoftware.group_id == client_group.group_id).all()
				for i in swids_Obj:
					res.append({'tuuid': i.tuuid})

			return res

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentBase_v2][softwareTasksForClientGroup][Exception][Line: %d] client_id: %s Message: %s' % (
			exc_tb.tb_lineno, client_id, message))
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


# Client Info/Status
class AgentStatus(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(AgentStatus, self).__init__()

	def get(self,client_id):
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

			client_obj = MpClient.query.filter_by(cuuid=client_id).first()

			if client_obj:
				if "POST_CHECKIN_TO_SYSLOG" in current_app.config:
					if current_app.config['POST_CHECKIN_TO_SYSLOG'] == True:
						postClientDataToSysLog(client_obj)

				_mdate = "{:%B %d, %Y %H:%M:%S}".format(client_obj.mdate)
				_mdateAlt = "{:%m/%d/%Y %H:%M:%S}".format(client_obj.mdate)
				res = {'mdate1':_mdate, 'mdate2': _mdateAlt}
				return {"result": {'data': res, 'type':'AgentStatus'}, "errorno": 0, "errormsg": 'none'}, 200
			else:
				log_Error('[AgentStatus][Get]: Client (%s) not found' % (client_id))
				return {"result": {'data': {}, 'type':'AgentStatus'}, "errorno": 404, "errormsg": 'Client not found.'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentStatus][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


# Post Data To Syslog, for Splunk
def postClientDataToSysLog(client_obj):
	# Collection for Syslog and Splunk
	syslog.openlog(facility=syslog.LOG_DAEMON)
	dataStr = "client_id: {}, hostname: {}, ip: {}, mac_address: {}, fileVault_status: {}, os_ver: {}, loggedin_user: {}".format(client_obj.cuuid,
																															 client_obj.hostname,
																															 client_obj.ipaddr,
																															 client_obj.macaddr,
																															 client_obj.fileVaultStatus,
																															 client_obj.osver,
																															 client_obj.consoleuser)
	syslog.syslog(dataStr)
	syslog.closelog()
	log_Info("Wrote to syslog: " + dataStr)
	return

# Server Public Key Check
class CheckServerKey(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(CheckServerKey, self).__init__()

	def get(self, cuuid):
		try:
			if not isValidClientID(cuuid):
				log_Error('[CheckServerKey][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES'] == True:
					log_Info('[CheckServerKey][Get]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[CheckServerKey][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			clientKey = None
			qKeys = MpSiteKeys.query.filter(MpSiteKeys.active == '1').first()
			cRegData = MPAgentRegistration.query.filter(MPAgentRegistration.cuuid == cuuid).first()
			if cRegData is not None:
				clientKey = cRegData.clientKey
			else:
				log_Error('[CheckServerKey][Get]: Client registration data not found.')
				return {"result": '', "errorno": 404, "errormsg": 'Client registration data not found.'}, 404	

			if qKeys is not None:
				if clientKey is not None:
					stringToHash = clientKey + "" + qKeys.pubKeyHash
					pubKeyHash256 = hashlib.sha256(stringToHash.encode('UTF-8')).hexdigest()
				
				res = {'pubKey': qKeys.pubKey, 'puKeyHash': pubKeyHash256}
				return {"result": res, "errorno": 0, "errormsg": 'none'}, 200
			else:
				log_Error('[CheckServerKey][Get]: Active Server keys not found')
				return {"result": '', "errorno": 404, "errormsg": 'Active Server keys not found'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[CheckServerKey][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Add Routes Resources
checkin_2_api.add_resource(AgentBase,			'/client/checkin/<string:cuuid>')
checkin_2_api.add_resource(AgentStatus, 		'/client/checkin/info/<string:client_id>')

checkin_2_api.add_resource(CheckServerKey,		'/client/server/key/<string:cuuid>')