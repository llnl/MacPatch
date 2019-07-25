from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
from collections import OrderedDict

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *
from .. shared.patches import *


parser = reqparse.RequestParser()

# Clientin Info/Status
class ClientPatchStatus(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ClientPatchStatus, self).__init__()

	def get(self, cuuid):
		try:
			if not isValidClientID(cuuid):
				log_Error('[ClientPatchStatus][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[ClientPatchStatus][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			apple_obj = MpClientPatchesApple.query.filter_by(cuuid=cuuid).all()
			custom_obj = MpClientPatchesThird.query.filter_by(cuuid=cuuid).all()

			apple = []
			third = []
			for row in apple_obj:
				apple.append(row.asDict)

			for row in custom_obj:
				third.append(row.asDict)

			# Return Results
			res = {'apple': apple, 'third': third, 'total': (len(apple) + len(third))}
			log_Debug('[ClientPatchStatus][Get]: Result: %s' % (res))
			return {"result": res, "errorno": 0, "errormsg": 'none'}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ClientPatchStatus][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Get Patch Scan List (Third Only)
class PatchScanList(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchScanList, self).__init__()

	def get(self, cuuid):
		try:
			if not isValidClientID(cuuid):
				log_Error('[PatchScanList][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[PatchScanList][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			_scanList = PatchScan()
			_list = _scanList.getScanList()

			if _list is not None:
				result = {'patches': _list}
				return {"result": result, "errorno": 0, "errormsg": 'none'}, 200
			else:
				log_Error('[PatchScanList][Get]: Failed to get a scan list for client %s' % (cuuid))
				return {"result": {}, "errorno": 0, "errormsg": 'none'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchScanList][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Get Patch Scan List filter on OS Ver e.g. 10.9, 10.10 ... (Third Only)
class PatchScanListFilterOS(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchScanListFilterOS, self).__init__()

	def get(self, cuuid, osver='*', state='Production', severity='All'):
		try:
			if not isValidClientID(cuuid):
				log_Error('[PatchScanListFilterOS][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[PatchScanListFilterOS][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			log_Debug('[PatchScanListFilterOS][Get]: Args: cuuid=(%s) osver=(%s) state=(%s)' % (cuuid, osver, state))

			_scanList = PatchScan()
			_list = _scanList.getScanList(osver, severity)

			if _list is not None:
				result = {'patches': _list}
				return {"result": result, "errorno": 0, "errormsg": 'none'}, 200
			else:
				log_Error('[PatchScanListFilterOS][Get]: Failed to get a scan list for client %s' % (cuuid))
				return {"result": {}, "errorno": 0, "errormsg": 'none'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchScanListFilterOS][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Get Patch Group Patches
class PatchGroupPatches(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchGroupPatches, self).__init__()

	def get(self, cuuid, patchGroup="Default"):

		try:
			if not isValidClientID(cuuid):
				log_Error('[PatchGroupPatches][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[PatchGroupPatches][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			# Get Patch Group ID from Name
			group_id = 'NA'
			q_group = MpPatchGroup.query.filter(MpPatchGroup.name == patchGroup).first()
			if q_group is not None:
				if q_group.id:
					group_id = q_group.id

					# Get Patch Group Patches
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
			else:
				log_Error('[PatchGroupPatches][Get][%s]: No patch group (%s) found.' % (cuuid, patchGroup))
				return {"result": '', "errorno": 404, "errormsg": 'Not Found'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchGroupPatches][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Get Patch Group Patches Rev
class PatchGroupPatchesRev(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchGroupPatchesRev, self).__init__()

	def get(self, cuuid, patchGroup="Default"):

		try:
			if not isValidClientID(cuuid):
				log_Error('[PatchGroupPatches][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[PatchGroupPatches][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			# Get Patch Group ID from Name
			group_id = 'NA'
			q_group = MpPatchGroup.query.filter(MpPatchGroup.name == patchGroup).first()
			if q_group is not None:
				if q_group.id:
					group_id = q_group.id

					# Get Patch Group Patches
					q_data = MpPatchGroupData.query.filter(MpPatchGroupData.pid == group_id, MpPatchGroupData.data_type == 'JSON').first()
					if q_data is not None:
						if q_data.rev:
							return {"result": str(q_data.rev), "errorno": 0, "errormsg": ''}, 200
			else:
				log_Error('[PatchGroupPatches][Get][%s]: No patch group (%s) found.' % (cuuid, patchGroup))
				return {"result": '', "errorno": 404, "errormsg": 'Not Found'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchGroupPatches][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Post Client Patch Scan Data
class PatchScanData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchScanData, self).__init__()

	def post(self, cuuid, patch_type):
		# Type: 0 = error, 1 = Apple, 2 = Third

		try:
			_body = request.get_json(silent=True)

			if not isValidClientID(cuuid):
				log_Error('[PatchScanData][Post]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": {}, "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, request.data, self.req_ts):
				log_Error('[PatchScanData][Post]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": {}, "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			if patch_type == "0":
				log_Error('[PatchScanData][Post][%s]: Type (%s) not accepted ' % (cuuid, patch_type))
				return {"result": {}, "errorno": 404, "errormsg": "Type not accepted"}, 404

			elif patch_type == "1":
				# Apple Patches
				log_Debug('[PatchScanData][Post][%s]: Type (%s) selected' % (cuuid, patch_type))
				MpClientPatchesApple.query.filter(MpClientPatchesApple.cuuid == cuuid).delete()
				db.session.commit()

				if _body is not None and 'rows' in _body:

					self.addClientPatch(cuuid, 1, _body)

					for row in _body['rows']:
						apple_object = MpClientPatchesApple()
						# Set All of the column values
						for col in apple_object.columns:
							if col in row:
								setattr(apple_object, col, row[col])

						# Set the Mod DateTime
						setattr(apple_object, 'mdate', datetime.now())
						setattr(apple_object, 'cuuid', cuuid)

						try:
							log_Debug('[PatchScanData][Post][%s]: Adding Apple: %s' % (cuuid, apple_object.asDict))
							db.session.add(apple_object)
							db.session.commit()
						except IntegrityError as exc:
							db.session.rollback()
							log_Error('[PatchScanData][Post][%s]: Error adding apple record. %s' % (cuuid, exc.message))
							return {"result": {}, "errorno": 0, "errormsg": exc.message}, 406

				# Rows have been added
				return {"result": {}, "errorno": 0, "errormsg": 'none'}, 201
			elif patch_type == "2":
				# Custom Patches
				log_Debug('[PatchScanData][Post][%s]: Type (%s) selected' % (cuuid, patch_type))
				MpClientPatchesThird.query.filter(MpClientPatchesThird.cuuid == cuuid).delete()
				db.session.commit()

				if _body is not None and 'rows' in _body:

					self.addClientPatch(cuuid, 2, _body)

					for row in _body['rows']:
						third_object = MpClientPatchesThird()
						# Set All of the column values
						for col in third_object.columns:
							if col in row:
								setattr(third_object, col, row[col])

						# Set the Mod DateTime
						setattr(third_object, 'mdate', datetime.now())
						setattr(third_object, 'cuuid', cuuid)

						try:
							log_Debug('[PatchScanData][Post][%s]: Adding Custom: %s' % (cuuid, third_object.asDict))
							db.session.add(third_object)
							db.session.commit()
						except IntegrityError as exc:
							db.session.rollback()
							log_Error('[PatchScanData][Post][%s]: Error adding custom record. %s' % (cuuid, exc.message))
							return {"result": {}, "errorno": 0, "errormsg": exc.message}, 406

					# Rows have been added
					return {"result": {}, "errorno": 0, "errormsg": 'none'}, 201
			else:
				log_Error('[PatchScanData][Post][%s]: Type (%s) not found' % (cuuid, patch_type))
				return {"result": {}, "errorno": 404, "errormsg": "Type not found"}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchScanData][Post][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def addClientPatch(self, cuuid, type, data):

		MpClientPatches.query.filter(MpClientPatches.cuuid == cuuid, MpClientPatches.type_int == type).delete()
		db.session.commit()

		if 'rows' in data:
			patch = None

			for row in data['rows']:
				patch = MpClientPatches()

				for col in patch.columns:
					if col in row:
						setattr(patch, col, row[col])

				# Set the Mod DateTime
				setattr(patch, 'mdate', datetime.now())
				setattr(patch, 'cuuid', cuuid)
				if type == 1:
					setattr(patch, 'type', 'Apple')
					setattr(patch, 'type_int', 1)
				elif type == 2:
					setattr(patch, 'type', 'Third')
					setattr(patch, 'type_int', 2)

			try:
				if patch:
					log_Debug('[PatchScanData][addClientPatch][%s]: Adding Patch: %s' % (cuuid, patch.asDict))
					db.session.add(patch)
					db.session.commit()
				return
			except IntegrityError as exc:
				db.session.rollback()
				log_Error('[PatchScanData][addClientPatch][%s]: Error adding apple record. %s' % (cuuid, exc.message))
				return

		return

# Post Client Patch Install Data
class PatchInstallData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(PatchInstallData, self).__init__()

	def post(self, cuuid, patch_type, patch):

		try:
			if not isValidClientID(cuuid):
				log_Error('[PatchInstallData][Post]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[PatchInstallData][Post]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			# Type: 0 = error, 1 = Apple, 2 = Third
			_patchType = 3
			_patchName = patch
			if patch_type.lower() == "apple" or patch_type == '1':
				_patchType = 0
				_patchTypeName = "apple"
				log_Debug('[PatchInstallData][Post][%s]: Adding Apple Patch: %s' % (cuuid, patch))

			if patch_type.lower() == "third" or patch_type == '2':
				_patchType = 1
				_patchTypeName = "third"
				_patchData = MpPatch.query.filter(MpPatch.puuid == patch).first()
				if not _patchData:
					log_Error("[PatchInstallData][Post]: Unable to get patch info for %s" % (patch))
					return {"result": '', "errorno": 0, "errormsg": ''}, 404

				_patchName = "%s-%s" % (_patchData.patch_name, _patchData.patch_ver)
				log_Debug('[PatchInstallData][Post][%s]: Adding Custom Patch: %s' % (cuuid, _patchName))

			# Create Patch Obj to add to DB
			installed_patch = MpInstalledPatch()
			setattr(installed_patch, 'cuuid', cuuid)
			setattr(installed_patch, 'mdate', datetime.now())
			setattr(installed_patch, 'patch', patch)
			setattr(installed_patch, 'patch_name', _patchName)
			setattr(installed_patch, 'type', _patchTypeName)
			setattr(installed_patch, 'type_int', _patchType)

			db.session.add(installed_patch)
			db.session.commit()

			# Update Status Table
			if _patchType == 0:
				# Apple Patch
				log_Debug('[PatchInstallData][Post][%s]: Removing Apple Patch (%s) from needed table' % (cuuid, patch))
				MpClientPatches.query.filter(MpClientPatches.patch == patch, MpClientPatches.type_int == 1, MpClientPatches.cuuid == cuuid).delete()
				MpClientPatchesApple.query.filter(MpClientPatchesApple.patch == patch, MpClientPatchesApple.cuuid == cuuid).delete()
				db.session.commit()

			if _patchType == 1:
				# Custom Patch
				log_Debug('[PatchInstallData][Post][%s]: Removing Custom Patch (%s) from needed table' % (cuuid, _patchName))
				MpClientPatches.query.filter(MpClientPatches.patch_id == patch, MpClientPatches.type_int == 2, MpClientPatches.cuuid == cuuid).delete()
				_patch_data = MpClientPatchesThird.query.filter(MpClientPatchesThird.patch_id == patch, MpClientPatchesThird.cuuid == cuuid).first()
				if _patch_data is not None:
					if _patch_data.rid:
						MpClientPatchesThird.query.filter(MpClientPatchesThird.rid == _patch_data.rid).delete()
						db.session.commit()

			return {"result": '', "errorno": 0, "errormsg": ''}, 202

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchInstallData][Post][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Read Saved PatchGroup patches and add signatures
class SavePatchGroupPatches(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SavePatchGroupPatches, self).__init__()

	def get(self, groupID):
		try:
			# Get Patch Group ID from Name
			group_id = 'NA'
			q_group = MpPatchGroup.query.filter(MpPatchGroup.id == groupID).first()
			if q_group is not None:
				if q_group.id:
					group_id = q_group.id

					# Get Patch Group Patches Data
					q_data = MpPatchGroupData.query.filter(MpPatchGroupData.pid == group_id, MpPatchGroupData.data_type == 'JSON').first()
					if q_data is not None:
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

						try:
							setattr(q_data, 'data', json.dumps(_res_data))
							db.session.commit()
							return {"result": {}, "errorno": 0, "errormsg": ''}, 201
						except IntegrityError as exc:
							log_Error('[SavePatchGroupPatches][Get][IntegrityError][SAVE]: Message: %s' % (exc.message))
							db.session.rollback()

					# No Data
					return {"result": {}, "errorno": 0, "errormsg": 'No group data to update'}, 200
			else:
				log_Error('[PatchGroupPatches][Get]: No patch group (%s) found.' % (groupID))
				return {"result": '', "errorno": 404, "errormsg": 'Not Found'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[PatchGroupPatches][Get][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# --------------------------------------------------------------------
# Add Routes Resources
patches_api.add_resource(ClientPatchStatus,     '/client/patch/status/<string:cuuid>')
patches_api.add_resource(PatchScanListFilterOS, '/client/patch/scanlist/<string:cuuid>', endpoint='noState')
patches_api.add_resource(PatchScanListFilterOS, '/client/patch/scanlist/<string:cuuid>/<string:state>', endpoint='withState')
patches_api.add_resource(PatchScanListFilterOS, '/client/patch/scanlist/<string:cuuid>/<string:state>/<string:osver>', endpoint='withOS')
patches_api.add_resource(PatchScanListFilterOS, '/client/patch/scanlist/<string:cuuid>/<string:state>/<string:osver>/<string:severity>', endpoint='withLevel')

# MP Agent 3.0
patches_api.add_resource(PatchGroupPatches,     '/client/patch/group/<string:patchGroup>/<string:cuuid>', endpoint='patches_agent30')
patches_api.add_resource(PatchGroupPatchesRev,  '/client/patch/group/rev/<string:patchGroup>/<string:cuuid>', endpoint='patches_rev_agent30')

# MP Agent 3.1
patches_api.add_resource(PatchGroupPatches,     '/client/patch/group/<string:cuuid>', endpoint='patches_agent31')
patches_api.add_resource(PatchGroupPatchesRev,  '/client/patch/group/rev/<string:cuuid>', endpoint='patches_rev_agent31')

# Post Client Patch Scan Data
patches_api.add_resource(PatchScanData,         '/client/patch/scan/<string:patch_type>/<string:cuuid>')
# Post Client Patch Install Data
patches_api.add_resource(PatchInstallData,      '/client/patch/install/<string:patch>/<string:patch_type>/<string:cuuid>')

# Update will be fixed in 3.1, should be done in console
patches_api.add_resource(SavePatchGroupPatches, '/client/update/patch/group/<string:groupID>')
