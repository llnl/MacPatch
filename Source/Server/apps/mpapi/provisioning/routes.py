from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *
from .. shared.client import *

import base64

parser = reqparse.RequestParser()

class PatchGroups(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchGroups, self).__init__()

	def get(self, cuuid):
		try:
			if self.req_agent == 'iLoad':
				log_Info("[PatchGroups][Get]: iLoad Request from %s" % (cuuid))
			else:
				if not isValidClientID(cuuid):
					log_Error('[PatchGroups][Get]: Failed to verify ClientID (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

				if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
					log_Error('[PatchGroups][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			qGet = MpPatchGroup.query.with_entities(MpPatchGroup.name).distinct('name').all()

			groups = []
			if qGet is not None:
				for row in qGet:
					groups.append(row[0])
			else:
				return {"result": [], "errorno": 0, "errormsg": 'No data found.'}, 204

			log_Debug('[PatchGroups][Get]: Result: %s' % (groups))
			return {"result": groups, "errorno": 0, "errormsg": ''}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchGroups][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class ClientGroups(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ClientGroups, self).__init__()

	def get(self, cuuid):
		try:
			if self.req_agent == 'iLoad':
				log_Info("[ClientGroups][Get]: iLoad Request from %s" % (cuuid))
			else:
				if not isValidClientID(cuuid):
					log_Error('[ClientGroups][Get]: Failed to verify ClientID (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

				if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
					log_Error('[ClientGroups][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			qGet = MpClientPlist.query.with_entities(MpClientPlist.Domain).distinct('Domain').all()

			groups = []
			if qGet is not None:
				for row in qGet:
					if row[0] is not None:
						groups.append(row[0])
			else:
				return {"result": [], "errorno": 0, "errormsg": 'No data found.'}, 204

			log_Debug('[ClientGroups][Get]: Result: %s' % (groups))
			return {"result": groups, "errorno": 0, "errormsg": ''}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ClientGroups][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class OSMigration(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(OSMigration, self).__init__()

	def post(self, cuuid):

		try:
			args = self.reqparse.parse_args()
			_body = request.get_json(silent=True)

			if not isValidClientID(cuuid):
				log_Error('[ClientGroups][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, request.data, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[AgentBase][Post]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[AgentBase][Post]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			if "action" in _body:
				if _body['action'] == "start":
					# If Action is Start, set up the migration
					osMigration = OSMigrationStatus()
					setattr(osMigration, 'startDateTime', datetime.now())
					setattr(osMigration, 'cuuid', cuuid)
					setattr(osMigration, 'preOSVer', _body['os'])
					setattr(osMigration, 'label', _body['label'])
					setattr(osMigration, 'migrationID', _body['migrationID'])
					db.session.add(osMigration)

				elif _body['action'] == "stop":
					# If Action is Stop, end the migration
					osMigration = OSMigrationStatus.query.filter_by(cuuid=cuuid, migrationID=_body['migrationID']).first()
					if osMigration is not None:
						setattr(osMigration, 'stopDateTime', datetime.now())
						setattr(osMigration, 'postOSVer', _body['os'])

					else:
						log_Error('[OSMigration][Post]: Migration not found for client (%s)' % (cuuid))
						return {"result": '', "errorno": 2, "errormsg": 'Migration not found.'}, 424

				else:
					log_Error('[OSMigration][Post]: Action type (%s) is not valid. Client (%s)' % (_body['action'], cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to run action type.'}, 424

				db.session.commit()
			# client_obj = MpClient.query.filter_by(cuuid=cuuid).first()
			# log_Debug('[AgentBase][Post]: Client (%s) Data %s' % (cuuid, _body))

			return {"result": '', "errorno": 0, "errormsg": 'none'}, 201

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[OSMigration][Post][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class SWProvTasks(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SWProvTasks, self).__init__()

	def get(self,client_id):
		try:
			if self.req_agent == 'iLoad':
				log_Info("[SWProvTasks][Get]: iLoad Request from %s" % (client_id))
			else:
				if not isValidClientID(client_id):
					log_Error('[SWProvTasks][Get]: Failed to verify ClientID (%s)' % (client_id))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

				if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
					log_Error('[SWProvTasks][Get]: Failed to verify Signature for client (%s)' % (client_id))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			agentSettings = AgentSettings()
			agentSettings.populateSettings(client_id)
			scope = 1 # production only
			if agentSettings.patch_state is not None:
				scope = agentSettings.patch_state

			qGet = MpProvisionTask.query.filter(MpProvisionTask.active == 1, MpProvisionTask.scope == scope).order_by(MpProvisionTask.order.asc()).all()

			tasks = []
			if qGet is not None:
				for row in qGet:
					if row is not None:
						tasks.append(row.asDict)
			else:
				return {"errorno": 0, "errormsg": 'none', "result": {'type': 'MpProvisionTask', 'data': tasks}, 'signature': signData(json.dumps(tasks))}, 200

			log_Debug('[SWProvTasks][Get]: Result: %s' % (tasks))
			return {"errorno": 0, "errormsg": '', "result": {'type': 'MpProvisionTask', 'data': tasks},
					'signature': signData(json.dumps(tasks))}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SWProvTasks][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class ProvisionData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ProvisionData, self).__init__()

	def get(self,client_id):
		try:
			if self.req_agent == 'iLoad':
				log_Info("[ProvisionData][Get]: iLoad Request from %s" % (client_id))
			else:
				if not isValidClientID(client_id):
					log_Error('[ProvisionData][Get]: Failed to verify ClientID (%s)' % (client_id))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

				if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
					log_Error('[ProvisionData][Get]: Failed to verify Signature for client (%s)' % (client_id))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			agentSettings = AgentSettings()
			agentSettings.populateSettings(client_id)
			scope = 1 # production only
			if agentSettings.patch_state is not None:
				if agentSettings.patch_state == 'QA':
					scope = 0

			qGetSW = MpProvisionTask.query.filter(MpProvisionTask.active == 1, MpProvisionTask.scope == scope).order_by(MpProvisionTask.order.asc()).all()
			qGetSCPre = MpProvisionScript.query.filter(MpProvisionScript.active == 1, MpProvisionScript.scope == scope, MpProvisionScript.type == 0).order_by(MpProvisionScript.order.asc()).all()
			qGetSCPst = MpProvisionScript.query.filter(MpProvisionScript.active == 1, MpProvisionScript.scope == scope, MpProvisionScript.type == 1).order_by(MpProvisionScript.order.asc()).all()

			scriptsPre = []
			scriptsPost = []
			tasks = []
			data = { "tasks": tasks, "scriptsPre": scriptsPre, "scriptsPost": scriptsPost }

			if qGetSW is not None:
				for row in qGetSW:
					if row is not None:
						tasks.append(row.asDict)
				data['tasks'] = tasks

			print(qGetSCPre)
			if qGetSCPre is not None:
				for row in qGetSCPre:
					if row is not None:
						scriptsPre.append(row.asDict)
				data['scriptsPre'] = scriptsPre

			print(qGetSCPst)
			if qGetSCPst is not None:
				for row in qGetSCPst:
					if row is not None:
						scriptsPost.append(row.asDict)
				data['scriptsPost'] = scriptsPost

			log_Debug('[ProvisionData][Get]: Result: %s' % (data))
			return {"errorno": 0, "errormsg": '',
					"result": {'type': 'MpProvisionTask', 'data': data},
					'signature': signData(json.dumps(tasks))}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ProvisionData][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class ProvisionConfig(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ProvisionConfig, self).__init__()

	def get(self, client_id):
		_data = {'config': ''}
		qGet = MpProvisionConfig.query.filter(MpProvisionConfig.active == 1).first()
		if qGet is not None:
			rawData = qGet.config

		return {"errorno": 0, "errormsg": '',
				"result": {'type': 'MpProvisionConfig', 'data': rawData},
				'signature': signData(rawData)}, 200

class ProvisionCriteria(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ProvisionCriteria, self).__init__()

	def get(self, client_id, scope="prod"):
		_data = {"query":[]}
		_criteria = []
		if scope == "prod":
			pc = MpProvisionCriteria.query.filter(MpProvisionCriteria.active == 1, MpProvisionCriteria.scope == 'prod').order_by(MpProvisionCriteria.order.asc()).all()
		else:
			pc = MpProvisionCriteria.query.filter(MpProvisionCriteria.active == 1, MpProvisionCriteria.scope == scope).order_by(MpProvisionCriteria.order.asc()).all()

		if pc is not None:
			for c in pc:
				if c.type.lower() == 'script':
					script_bytes = base64.b64encode(c.type_data.encode('utf-8'))
					_criteria.append({'id': c.order, 'qstr': ("{}@{}").format(c.type, script_bytes.decode('utf-8'))})
				else:
					_criteria.append({'id':c.order,'qstr':("{}@{}").format(c.type,c.type_data)})

			_data['query'] = _criteria

		return {"errorno": 0, "errormsg": '',
				"result": {'type': 'MpProvisionCriteria', 'data': _data},
				'signature': signData(_data)}, 200

# Add Routes Resources
provisioning_api.add_resource(PatchGroups,			'/provisioning/groups/patch/<string:cuuid>')
provisioning_api.add_resource(ClientGroups,			'/provisioning/groups/client/<string:cuuid>')

# Provisioning Status Data
provisioning_api.add_resource(OSMigration,			'/provisioning/migration/<string:cuuid>')

# Provisioning Software Tasks
provisioning_api.add_resource(SWProvTasks,			'/provisioning/tasks/<string:client_id>')
provisioning_api.add_resource(ProvisionData,		'/provisioning/data/<string:client_id>')

# Provisioning UI Config Data
provisioning_api.add_resource(ProvisionConfig,		'/provisioning/config/<string:client_id>')
# Provisioning Criteria
provisioning_api.add_resource(ProvisionCriteria,	'/provisioning/criteria/<string:client_id>', endpoint="base")
provisioning_api.add_resource(ProvisionCriteria,	'/provisioning/criteria/<string:client_id>/<string:scope>', endpoint="filter")