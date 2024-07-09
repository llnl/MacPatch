from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from sqlalchemy import text
from datetime import datetime

import json

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *
from .. wsresult import *
from .. shared.patches import *
from .. mpaws import *

parser = reqparse.RequestParser()

# Get Patch Group Patches Fast & Dynamic

class PatchGroupPatches(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchGroupPatches, self).__init__()

	def get(self, client_id, all=None):

		aws = MPaws()
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
			_third_all = self.allCustomActiveContent()

			# Get Patch Group Patches
			if all == 'all':
				# Apple
				for x in _apple_all:
					_apple_patches.append(x)

				# Custom
				for t in _third_all:
					patch = t.asDict
					# Add S3 Support
					if 'pkg_useS3' in patch:
						if patch['pkg_useS3'] == 1:
							s3url = aws.getS3UrlForPatch(patch['puuid'])
							patch['pkg_url'] = s3url

					del patch['pkg_path']
					del patch['cve_id']
					del patch['patch_severity']
					del patch['cdate']
					_thrid_patches.append(patch)

			else:
				q_data = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id).all()

				if q_data is not None:
					if len(q_data) >= 1:
						for row in q_data:
							rowDict = row.asDict

							# Parse Apple Patches
							aPatchResult = self.getApplePatchData(row.patch_id, _apple_all)
							if aPatchResult is not None:
								_apple_patches.append(aPatchResult)
								continue

							# Parse Custom Patches
							for tRow in _third_all:
								if row.patch_id == tRow.puuid:
									patch = tRow.asDict
									# Add S3 Support
									if 'pkg_useS3' in patch:
										if patch['pkg_useS3'] == 1:
											s3url = aws.getS3UrlForPatch(patch['puuid'])
											patch['pkg_url'] = s3url

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

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchGroupPatches][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return wsResult.resultNoSignature(errorno=500, errormsg=message), 500

	# Methods for Content, this way I can cache the results as they dont change often
	@cache.cached(timeout=300, key_prefix='AppleCachedList')
	def appleContent(self):

		# Combine, apple additions with apple patch
		sql_str = text("""select ap.akey, ap.title, ap.postdate, ap.restartaction, ap.supatchname, ap.version, 
							mpa.severity, mpa.severity_int, mpa.patch_state, mpa.patch_install_weight, mpa.patch_reboot
							from apple_patches ap
							LEFT JOIN apple_patches_mp_additions mpa ON
							ap.supatchname = mpa.supatchname""")

		results_pre = []
		with db.engine.connect() as sql_con:
			res = sql_con.execute(sql_str)
			q_data = res.mappings().all()

		if len(q_data) <= 0:
			return results_pre

		# results from sqlalchemy are returned as a list of tuples; this procedure converts it into a list of dicts
		#for row_number, row in enumerate(q_data):
		#	results_pre.append({})
		#	for column_number, value in enumerate(row):
		#		results_pre[row_number][list(row.keys())[column_number]] = value

		# set the reboot override
		results = []
		for row in q_data:
			if row["restartaction"] == 'NoRestart' and row['patch_reboot'] == 1:
				row['restartaction'] = 'RequireRestart'
			elif row["restartaction"] == 'RequireRestart' and row['patch_reboot'] == 0:
				row['restartaction'] = 'NoRestart'

			results.append(row)

		return results

	@cache.cached(timeout=300, key_prefix='CustomCachedList')
	def allCustomActiveContent(self):
		return MpPatch.query.filter(MpPatch.active == 1).all()

	# return the apple patch for using akey
	def getApplePatchData(self, akey, patchList):
		patch = None
		for x in patchList:
			if x['akey'] == akey:
				patch = x
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


# Get Patch Group Patches
class PatchGroupPatchesDyn(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchGroupPatchesDyn, self).__init__()

	def get(self, client_id, patchGroup="Default"):

		try:
			if not isValidClientID(client_id):
				log_Error('[PatchGroupPatches][Get]: Failed to verify ClientID (%s)' % (client_id))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
				log_Error('[PatchGroupPatches][Get]: Failed to verify Signature for client (%s)' % (client_id))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			# Get Patch Group ID from Name
			group_id = 'NA'
			q_group = MpPatchGroup.query.filter(MpPatchGroup.name == patchGroup).first()
			if q_group is not None:
				if q_group.id:
					group_id = q_group.id

					# Get Patch Group Patches
					'''
					q_data = MpPatchGroupData.query.filter(MpPatchGroupData.pid == group_id, MpPatchGroupData.data_type == 'JSON').first()
					if q_data is not None:
						if q_data.data:
							_patches = []
							_res_data = json.loads(q_data.data)
							_custom_patches = _res_data['CustomUpdates']
							for patch in _custom_patches:
								_str_to_sign = None
								_str_chunks = []
								_keys = ["baseline","env","hash","name","postinst","preinst","reboot","size","type","url"]
								_loc_patches = patch['patches']
								for p in _loc_patches:
									for k in _keys:
										_str_chunks.append(p[k])

								_str_to_sign = ''.join(_str_chunks)
								patch['patch_sig'] = signData(_str_to_sign)
								_patches.append(patch)

							_res_data['CustomUpdates'] = _patches
							return {"result": _res_data, "errorno": 0, "errormsg": ''}, 200
					'''
					patch_data = self.groupPatches(group_id)
					return {"result": patch_data, "errorno": 0, "errormsg": ''}, 200
			else:
				log_Error('[PatchGroupPatches][Get][%s]: No patch group (%s) found.' % (client_id, patchGroup))
				return {"result": '', "errorno": 404, "errormsg": 'Not Found'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchGroupPatches][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def groupPatches(self, group_id):
		_patchData = {}
		_patchData['AppleUpdates'] = []
		_patchData['CustomUpdates'] = []
		_combined_patches = []
		_apple_criteria = []
		_patches_data = []

		sql = text("SELECT * from combined_patches_view")
		with db.engine.connect() as sql_con:
			_result = sql_con.execute(sql)
			result = _result.mappings().all()

		for v in result:
			_combined_patches.append(v)

		_q_apple_criteria = ApplePatchCriteria.query.all()
		for c in _q_apple_criteria:
			_apple_criteria.append(c.asDict)

		_q_patches = MpPatch.query.all()
		for p in _q_patches:
			_patches_data.append(p.asDict)


		_patchGroupPatches = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id).all()
		if _patchGroupPatches is not None:
			for p in _patchGroupPatches:
				row = {}
				patch = self.patchDataForPatchID(p.patch_id, _combined_patches)
				if patch is None:
					# Patch ID no longer exists, delete it from all
					# patch groups
					self.removePatchFromPatchGroups(p.patch_id)
					continue
				else:
					if patch['type'] == "Apple":
						row["name"] = patch['suname']
						row["patch_id"] = patch['id']
						row["baseline"] = "0"
						row["patch_install_weight"] = patch['patch_install_weight']
						row["patch_reboot_override"] = patch['patch_reboot_override']
						row["severity"] = patch['severity']
						row["hasCriteria"] = self.applePatchHasCriteria(patch['id'],_apple_criteria)
						_patchData['AppleUpdates'].append(row)
						continue
					else:
						row["patch_id"] = patch['id']
						row["patch_install_weight"] = patch['patch_install_weight']
						row["severity"] = patch['severity']
						row["patches"] = self.customDataForPatchID(patch['id'], _patches_data)
						_patchData['CustomUpdates'].append(row)
						continue

		return _patchData

	# Private
	def patchDataForPatchID(self, patch_id, data):
		result = None
		for x in data:
			if x['id'] == patch_id:
				return x

		return result

	# Private
	def applePatchHasCriteria(self, patch_id, data):
		res = "FALSE"
		for x in data:
			if patch_id == x['puuid']:
				res = "TRUE"
				break
		return res

	# Private
	def customDataForPatchID(self, patch_id, data):
		_results = []
		#patches = MpPatch.query.filter(MpPatch.puuid == patch_id).all()
		if data is not None:
			for p in data:
				if p['puuid'] == patch_id:
					row = {}
					row["name"] = p['patch_name']
					row["hash"] = p['pkg_hash']
					row["preinst"] = b64EncodeAsString(p['pkg_preinstall'], 'NA')
					row["postinst"] = b64EncodeAsString(p['pkg_postinstall'], 'NA')
					row["env"] = p['pkg_env_var'] or "NA"
					row["reboot"] = p['patch_reboot']
					row["type"] = "1"
					row["url"] = p['pkg_url'] or "NA"
					row["size"] = p['pkg_size']
					row["baseline"] = "0"
					_results.append(row)

		return _results


# --------------------------------------------------------------------
# MP Agent 3.4
# Add S3 Support

patches_4_api.add_resource(PatchGroupPatches,			'/client/patch/group/<string:client_id>', endpoint='patchGroup')
patches_4_api.add_resource(PatchGroupPatches,			'/client/patch/<string:all>/<string:client_id>', endpoint='patchAll')

patches_4_api.add_resource(PatchGroupPatchesDyn,		'/client/patch/groupdata/<string:client_id>')

