from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime

import json
import base64

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *
from .. wsresult import *
from .. shared.patches import *

parser = reqparse.RequestParser()

# Get Patch Group Patches Fast & Dynamic
class PatchGroupPatches(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchGroupPatches, self).__init__()

	# @cache.cached(timeout=300)
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
			if group_id is None or group_id == 'NA':
				log_Error('[PatchGroupPatches][Get][%s]: No patch group (%s) found.' % (client_id, group_id))
				return wsResult.resultNoSignature(errorno=404, errormsg='Not Found'), 404

			_data = {}
			_data['Apple'] = []
			_data['Custom'] = []

			_apple_patches = []
			_thrid_patches = []

			# Query all sources needed
			_apple_all = self.appleContent()
			_appMP_all = self.appleMPAdditions()
			_third_all = self.allCustomActiveContent()

			# Get Patch Group Patches
			q_data = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id).all()
			if q_data is not None:
				if len(q_data) >= 1:
					for row in q_data:
						# Parse Apple Patches
						for aRow in _apple_all:
							if row.patch_id == aRow.akey:
								_apple_patches.append(self.getApplePatchData(aRow, _appMP_all))
								break
						# Parse Custom Patches
						for tRow in _third_all:
							if row.patch_id == tRow.puuid:
								patch = tRow.asDict
								del patch['pkg_path']
								del patch['cve_id']
								del patch['patch_severity']
								del patch['cdate']
								_thrid_patches.append(patch)
								break

			_data['Apple'] = _apple_patches
			_data['Custom'] = _thrid_patches

			wsData.data = _data
			wsResult.data = wsData.toDict()
			return wsResult.resultNoSignature(), 200

		except IntegrityError, exc:
			log_Error('[PatchGroupPatches][Get][IntegrityError] CUUID: %s Message: %s' % (client_id, exc.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=exc.message), 500

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[PatchGroupPatches][Get][Exception][Line: %d] CUUID: %s Message: %s' % (exc_tb.tb_lineno, client_id, e.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=e.message), 500

	# Methods for Content, this way I can cache the results as they dont change often
	@cache.cached(timeout=300, key_prefix='AppleCachedList')
	def appleContent(self):
		return ApplePatch.query.all()

	@cache.cached(timeout=300, key_prefix='AppleMPCachedList')
	def appleMPAdditions(self):
		return ApplePatchAdditions.query.all()

	@cache.cached(timeout=300, key_prefix='CustomCachedList')
	def allCustomActiveContent(self):
		return MpPatch.query.filter(MpPatch.active == 1).all()

	# Need to add mac patch apple patch additions to the
	# apple patch object, I'm are creating a model here
	# thats usable :-)
	@cache.cached(timeout=300, key_prefix='AppleCombCachedList')
	def getApplePatchData(self, appleData, patchAdditions):
		patch = {}

		patch['akey'] = appleData.akey
		patch['title'] = appleData.title
		patch['postdate'] = appleData.postdate
		patch['restartaction'] = appleData.restartaction
		patch['patch_reboot'] = '0'
		if appleData.restartaction == 'RequireRestart':
			patch['patch_reboot'] = '1'
		patch['supatchname'] = appleData.supatchname
		patch['version'] = appleData.version

		# MP Addition
		patch['severity'] = 'High'
		patch['severity_int'] = '3'
		patch['patch_state'] = 'Create'
		patch['patch_install_weight'] = '60'

		for row in patchAdditions:
			if row.supatchname == appleData.supatchname:
				patch['severity'] = row.severity
				patch['severity_int'] = row.severity_int
				patch['patch_state'] = row.patch_state
				patch['patch_install_weight'] = row.patch_install_weight
				if appleData.restartaction == 'NoRestart':
					if row.patch_reboot == 1:
						patch['restartaction'] = 'RequireRestart'
						patch['patch_reboot'] = '1'
				break

		return patch

	# Get the patch group id for a client id
	# returns group id or NA
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

# Get Patch Group Patches Fast & Dynamic
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

			_scanList = PatchScanV2(agentSettings.patch_state)
			_list = _scanList.getScanList('*', severity)

			if _list is not None:
				result = {'data': _list}
				return {"result": result, "errorno": 0, "errormsg": 'none'}, 200
			else:
				log_Error('[PatchScanListFilterOS][Get]: Failed to get a scan list for client %s' % (client_id))
				return {"result": {}, "errorno": 0, "errormsg": 'none'}, 404


		except IntegrityError, exc:
			log_Error('[PatchGroupPatches][Get][IntegrityError] CCUID: %s Message: %s' % (client_id, exc.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=exc.message), 500

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[PatchGroupPatches][Get][Exception][Line: %d] CCUID: %s Message: %s' % (exc_tb.tb_lineno, client_id, e.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=e.message), 500


# Get Patch Data for BundleID
class PatchForBundleID(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchForBundleID, self).__init__()

	def get(self, client_id, bundle_id):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'PatchForBundleID'
		wsResult.result = wsData

		try:
			if not isValidClientID(client_id):
				log_Error('[PatchGroupPatches][Get]: Failed to verify ClientID (%s)' % (client_id))
				return wsResult.resultNoSignature(errorno=424,errormsg='Failed to verify ClientID'), 424

			if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
				log_Error('[PatchGroupPatches][Get]: Failed to verify Signature for client (%s)' % (client_id))
				return wsResult.resultNoSignature(errorno=424,errormsg='Failed to verify Signature'), 424

			_data = {}
			_data['Custom'] = []
			_patches = []

			# Query all sources needed
			_sw = self.customContentUsingBundleID(bundle_id)
			for row in _sw:
				patch = row.asDict
				# Remove un-needed attributes
				del patch['pkg_path']
				del patch['cve_id']
				del patch['patch_severity']
				del patch['cdate']
				if row.pkg_preinstall is not None:
					if row.pkg_preinstall != "":
						patch['pkg_preinstall'] = base64.b64encode(row.pkg_preinstall)

				if row.pkg_postinstall is not None:
					if row.pkg_postinstall != "":
						patch['pkg_postinstall'] = base64.b64encode(row.pkg_postinstall)

				_patches.append(patch)

			# Sort the results based on bundle id then version
			_sorted = sorted(_patches, key=lambda elem: "%s %s" % (
				elem['bundle_id'], (".".join([i.zfill(5) for i in elem['patch_ver'].split(".")]))), reverse=True)

			# grab first item from the list, it's the latest version for the bundle id
			wsData.data = _sorted[0]

			wsResult.data = wsData.toDict()
			return wsResult.resultNoSignature(), 200

		except IntegrityError, exc:
			log_Error('[PatchGroupPatches][Get][IntegrityError] CUUID: %s Message: %s' % (client_id, exc.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=exc.message), 500

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[PatchGroupPatches][Get][Exception][Line: %d] CUUID: %s Message: %s' % (exc_tb.tb_lineno, client_id, e.message))
			return wsResult.resultNoSignature(errorno=500, errormsg=e.message), 500

	@cache.cached(timeout=300, key_prefix='CustomCachedList')
	def customContentUsingBundleID(self, bundleID):
		return MpPatch.query.filter(MpPatch.active == 1,
									MpPatch.patch_state == "Production",
									MpPatch.bundle_id == bundleID ).all()

# --------------------------------------------------------------------
# MP Agent 3.1
# Add Routes Resources
# New, Dynamic, no need to save patch group

patches_3_api.add_resource(PatchGroupPatches,		'/client/patch/group/<string:client_id>')

patches_3_api.add_resource(PatchScanList, 			'/client/patch/scan/list/all/<string:client_id>', endpoint='sevAll')
patches_3_api.add_resource(PatchScanList, 			'/client/patch/scan/list/<string:severity>/<string:client_id>', endpoint='sevCustom')

patches_3_api.add_resource(PatchForBundleID,		'/patch/bundleID/<string:bundle_id>/<string:client_id>')
