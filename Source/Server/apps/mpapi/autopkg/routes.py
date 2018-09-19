from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
import uuid
import base64
import os

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

# Client AV Data Collection
class AddAutoPKGPatch(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(AddAutoPKGPatch, self).__init__()

	def post(self, token):

		try:
			_user = verify_auth_token(token)
			if not _user or (_user == "BadSignature" or _user == "SignatureExpired"):
				return {"result": '', "errorno": 100, "errormsg": 'Failed to verify token'}, 401

			if not isValidAutoPKGUser(_user):
				return {"result": '', "errorno": 101, "errormsg": 'Failed to verify ClientID'}, 403

			_jdata = request.get_json(silent=True)
			_body = _jdata['autoPKGData']

			if not self.isValidPatch(_body):
				return {"result": '', "errorno": 102, "errormsg": 'Failed to verify AutoPKG Object'}, 424

			if self.patchExists(_body):
				return {"result": '', "errorno": 9003, "errormsg": 'Patch already exists.'}, 409

			_patchID = str(uuid.uuid4())

			# Populate the PATCH object for the json data
			_patch = autoPKG()
			_patchKeys = _patch.allKeys()
			setattr(_patch, "puuid", _patchID)

			for key in _body.keys():
				if key in _patchKeys:
					if key == "pkg_preinstall" or key == "pkg_postinstall":
						setattr(_patch, key, base64.b64decode(_body[key]))
					else:
						setattr(_patch, key, _body[key])

			# Populate the PATCH CRITERIA object for the json data
			_patchCri = autoPKGCriteria()
			_patchCriKeys = _patchCri.allKeys()

			for key in _body.keys():
				if key in _patchCriKeys:
					setattr(_patchCri, key, _body[key])

			# Add Patch
			_mpPatch = MpPatch()
			for col in _mpPatch.columns:
				if col == 'mdate' or col == 'cdate':
					setattr(_mpPatch, col, datetime.now())
				else:
					if col in _patchKeys:
						setattr(_mpPatch, col, eval('_patch.'+col))

			setattr(_mpPatch, "patch_state", "AutoPKG")
			setattr(_mpPatch, "active", "1")
			db.session.add(_mpPatch)

			# Add Patch Criteria
			_crit1 = MpPatchesCriteria()
			setattr(_crit1, 'puuid', _patchID)
			setattr(_crit1, 'type', 'OSType')
			setattr(_crit1, 'type_data', _body['OSType'])
			setattr(_crit1, 'type_order', '1')
			db.session.add(_crit1)

			_crit2 = MpPatchesCriteria()
			setattr(_crit2, 'puuid', _patchID)
			setattr(_crit2, 'type', 'OSVersion')
			setattr(_crit2, 'type_data', _body['OSVersion'])
			setattr(_crit2, 'type_order', '2')
			db.session.add(_crit2)

			_crit3 = MpPatchesCriteria()
			setattr(_crit3, 'puuid', _patchID)
			setattr(_crit3, 'type', 'OSArch')
			setattr(_crit3, 'type_data', _body['OSArch'] if 'OSArch' in _body else 'X86')
			setattr(_crit3, 'type_order', '3')
			db.session.add(_crit3)

			x = 3 # Last Inserted Order number for patch criteria
			for cItem in _patchCri.patch_criteria_enc:
				x += 1 # Add 1 for the order
				_critStr = base64.b64decode(cItem) # Decode Base64
				_critLst = _critStr.split("@") # Gen List from String, split on @ symbol
				_cType = _critLst[0] # Get Type
				_critLst.pop(0) # Remove Type to get the Query
				_cQry = "@".join(_critLst) # Build Query String
				_crit = MpPatchesCriteria()

				setattr(_crit, 'puuid', _patchID)
				setattr(_crit, 'type', _cType)
				setattr(_crit, 'type_data', _cQry)
				setattr(_crit, 'type_order', x)
				db.session.add(_crit)

			db.session.commit()
			self.AddUploadRequest(_user, _patchID)

			# Send Email About New PKG
			linebk = "-----------------------------------------------"
			email_msg_lst = ["User: " + _user, linebk, "PatchID: " + _patchID, "Patch Name: " + _patch.patch_name, "Patch Version: " + _patch.patch_ver, "Patch Bundle ID: " + _patch.bundle_id]
			email_msg = "\r\n".join(email_msg_lst)
			sendEmailMessage("New AutoPKG Patch Created", email_msg, )

			return {"result": _patchID, "errorno": 0, "errormsg": ''}, 201

		except IntegrityError, exc:
			db.session.rollback()
			log_Error('[AddAutoPKGPatch][Post][IntegrityError] Message: %s' % (exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[AddAutoPKGPatch][Post][Exception][Line: %d] Message: %s' % (exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': {}}, 500

	def isValidPatch(self, patch):

		result = 0
		reqObjKeys = ["bundle_id", "patch_name", "patch_ver", "patch_severity", "OSType", "OSVersion", "patch_criteria_enc"]

		for key in reqObjKeys:
			if key in patch:
				result += 1

		if result == len(reqObjKeys):
			return True
		else:
			return False

	def patchExists(self, patch):

		q_result = MpPatch.query.filter(MpPatch.bundle_id == patch['bundle_id'], MpPatch.patch_ver == patch['patch_ver']).first()
		if q_result is not None:
			return True
		else:
			return False

	def AddUploadRequest(self, user, puuid):

		_req = MpUploadRequest()
		setattr(_req, 'requestid', puuid)
		setattr(_req, 'uid', user)
		setattr(_req, 'cdate', datetime.now())
		setattr(_req, 'enabled', '1')
		db.session.add(_req)
		db.session.commit()

class UploadAutoPKGPatch(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(UploadAutoPKGPatch, self).__init__()

	def post(self, patch_id, token):

		try:
			_user = verify_auth_token(token)
			if not _user or (_user == "BadSignature" or _user == "SignatureExpired"):
				log_Error('[UploadAutoPKGPatch][Post]: Failed to verify token')
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify token'}, 424

			if not isValidAutoPKGUser(_user):
				log_Error('[UploadAutoPKGPatch][Post]: Failed authorization check.')
				return {"result": '', "errorno": 425, "errormsg": 'Failed authorization check.'}, 425

			file = request.files['autoPKG']
			upload_dir = os.path.join(current_app.config['PATCH_CONTENT_DIR'], patch_id)

			if not os.path.isdir(upload_dir):
				log_Debug('[UploadAutoPKGPatch][Post]: Create upload directory  %s' % (upload_dir))
				os.makedirs(upload_dir)

			file.save(os.path.join(upload_dir, file.filename))

			pkg_name    = os.path.splitext(file.filename)[0]
			pkg_url     = os.path.join("/patches", patch_id, file.filename)
			pkg_path    = os.path.join(upload_dir, file.filename)
			pkg_sizeK   = os.path.getsize(pkg_path) / 1000
			pkg_hash    = self.md5(pkg_path)

			# Update Patch db record with patch file info
			patch = MpPatch.query.filter_by(puuid = patch_id).first()
			if patch:
				patch.pkg_name      = pkg_name
				patch.pkg_size      = pkg_sizeK
				patch.pkg_hash      = pkg_hash
				patch.pkg_path      = pkg_path
				patch.pkg_url       = pkg_url
				log_Info('[UploadAutoPKGPatch][Post]: Update patch db record with patch file info.')
				log_Debug('[UploadAutoPKGPatch][Post]: Patch Info %s' % (patch.asDict))
				db.session.commit()
				return {"result": '', "errorno": 0, "errormsg": ""}, 202

			log_Error('[UploadAutoPKGPatch][Post]: Error patch (%s) was not found to update.' % (patch_id))
			return {"result": '', "errorno": 104, "errormsg": ""}, 404

		except IntegrityError, exc:
			log_Error('[UploadAutoPKGPatch][Post][IntegrityError]: %s' % (exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[UploadAutoPKGPatch][Post][Exception][Line: %d] Message: %s' % (exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': {}}, 500

	def isValidPatch(self, patch):

		result = 0
		reqObjKeys = ["bundle_id", "patch_name", "patch_ver", "patch_severity", "OSType", "OSVersion", "patch_criteria_enc"]

		for key in reqObjKeys:
			if key in patch:
				result += 1

		if result == len(reqObjKeys):
			return True
		else:
			return False

	def AddUploadRequest(self, user, puuid):

		_req = MpUploadRequest()
		setattr(_req, 'requestid', puuid)
		setattr(_req, 'uid', user)
		setattr(_req, 'cdate', datetime.now())
		setattr(_req, 'enabled', '1')
		db.session.add(_req)
		db.session.commit()

	def md5(self, fname):
		hash_md5 = hashlib.md5()
		with open(fname, "rb") as f:
			for chunk in iter(lambda: f.read(4096), b""):
				hash_md5.update(chunk)
		return hash_md5.hexdigest()

''' ------------------------------- '''
''' NOT A WEB SERVICE CLASS         '''
''' Classes for Patch               '''

class autoPKG(object):

	def __init__(self):
		self.puuid = ""
		self.bundle_id = ""
		self.patch_name = ""
		self.patch_ver = ""
		self.patch_vendor = ""
		self.patch_install_weight = "30"
		self.description = ""
		self.description_url = ""
		self.patch_severity = "High"
		self.patch_state = ""
		self.patch_reboot = "No"
		self.cve_id = ""
		self.active = "0"
		self.pkg_preinstall = ""
		self.pkg_postinstall = ""
		self.pkg_name = "AUTOPKG"
		self.pkg_env_var = ""

	def asDict(autoPKG):
		return (autoPKG.__dict__)

	def allKeys(autoPKG):
		return (autoPKG.__dict__.keys())

class autoPKGCriteria(object):

	def __init__(self):
		# Criteria
		self.OSArch = "X86"
		self.OSType = "Mac OS X, Mac OS X Server"
		self.OSVersion = "*"
		self.patch_criteria_enc = []

	def asDict(autoPKG):
		return (autoPKG.__dict__)

	def allKeys(autoPKG):
		return (autoPKG.__dict__.keys())


# Add Routes Resources
autopkg_api.add_resource(AddAutoPKGPatch,    '/autopkg/<string:token>')
autopkg_api.add_resource(UploadAutoPKGPatch, '/autopkg/upload/<string:patch_id>/<string:token>')
