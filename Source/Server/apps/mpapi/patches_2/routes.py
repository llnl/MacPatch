from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime

import json

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *
from .. wsresult import *
from .. shared.patches import *

parser = reqparse.RequestParser()

# Get Patch Group Patches
class PatchGroupPatches(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchGroupPatches, self).__init__()

	def get(self, client_id):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'PatchGroupPatches'
		wsResult.result = wsData

		try:
			if not isValidClientID(client_id):
				log_Error('[PatchGroupPatches][Get]: Failed to verify ClientID (%s)' % (client_id))
				return wsResult.resultNoSignature(errorno=424,errormsg='Failed to verify ClientID'), 424

			if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
				log_Error('[PatchGroupPatches][Get]: Failed to verify Signature for client (%s)' % (client_id))
				return wsResult.resultNoSignature(errorno=424,errormsg='Failed to verify Signature'), 424

			# Get Patch Group ID for Client
			group_id = self.getPatchGroupForClient(client_id)

			# Get Patch Group Patches
			q_data = MpPatchGroupData.query.filter(MpPatchGroupData.pid == group_id, MpPatchGroupData.data_type == 'JSON').first()

			if q_data is not None:
				if q_data.data:
					wsData.data = json.loads(q_data.data)

				wsResult.data = wsData.toDict()
				return wsResult.resultWithSignature(), 200

			else:
				log_Error('[PatchGroupPatches][Get][%s]: No patch group (%s) found.' % (client_id, group_id))
				return wsResult.resultNoSignature(errorno=404, errormsg='Not Found'), 404

		except IntegrityError as exc:
			log_Error('[PatchGroupPatches][Get][IntegrityError] CUUID: %s Message: %s' % (client_id, exc.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=exc.message), 500

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[PatchGroupPatches][Get][Exception][Line: %d] CUUID: %s Message: %s' % (exc_tb.tb_lineno, client_id, e.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=e.message), 500

	def getPatchGroupForClient(self, client_id):
		patch_group_id = 'NA'
		group_id = 0
		qGroupMembership = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_id).first()
		if qGroupMembership is not None:
			group_id = qGroupMembership.group_id

		qGroupData = MpClientSettings.query.filter(MpClientSettings.group_id == group_id, MpClientSettings.key == 'patch_group').first()
		if qGroupData is not None:
			patch_group_id = qGroupData.value

		return patch_group_id

# Get Patch Scan List filter on OS Ver e.g. 10.9, 10.10 ... (Third Only)
class PatchScanList(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchScanList, self).__init__()

	def get(self, client_id, severity='all'):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'PatchGroupPatches'
		wsResult.result = wsData

		try:
			if not isValidClientID(client_id):
				log_Error('[PatchScanList][Get]: Failed to verify ClientID (%s)' % (client_id))
				return wsResult.resultNoSignature(errorno=424,errormsg='Failed to verify ClientID'), 424

			if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
				log_Error('[PatchScanList][Get]: Failed to verify Signature for client (%s)' % (client_id))
				return wsResult.resultNoSignature(errorno=424,errormsg='Failed to verify Signature'), 424

			log_Debug('[PatchScanList][Get]: Args: ccuid=(%s) severity=(%s)' % (client_id, severity))


			agentSettings = AgentSettings()
			agentSettings.populateSettings(client_id)

			_scanList = PatchScan(agentSettings.patch_state)
			_list = _scanList.getScanList('*', severity)

			if _list is not None:
				result = {'data': _list}
				return {"result": result, "errorno": 0, "errormsg": 'none'}, 200
			else:
				log_Error('[PatchScanListFilterOS][Get]: Failed to get a scan list for client %s' % (client_id))
				return {"result": {}, "errorno": 0, "errormsg": 'none'}, 404


		except IntegrityError as exc:
			log_Error('[PatchGroupPatches][Get][IntegrityError] CCUID: %s Message: %s' % (client_id, exc.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=exc.message), 500

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[PatchGroupPatches][Get][Exception][Line: %d] CCUID: %s Message: %s' % (exc_tb.tb_lineno, client_id, e.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=e.message), 500

# --------------------------------------------------------------------
# MP Agent 3.1
# Add Routes Resources
patches_2_api.add_resource(PatchGroupPatches,		'/client/patch/group/<string:client_id>')

patches_2_api.add_resource(PatchScanList, 			'/client/patch/scan/list/all/<string:client_id>', endpoint='sevAll')
patches_2_api.add_resource(PatchScanList, 			'/client/patch/scan/list/<string:severity>/<string:client_id>', endpoint='sevCustom')
