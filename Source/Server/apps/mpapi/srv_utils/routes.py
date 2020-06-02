from flask import request, current_app
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

class SUSPatchData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SUSPatchData, self).__init__()

	def post(self):
		# Must have a valid key hash

		try:
			log_Warn('[SUSPatchData][Post]: Method needs auth check.')

			if not isValidAPIKey(self.req_akey, self.req_ts):
				log_Error('[SUSPatchData][Post]: Failed to verify API Key')
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify API Key'}, 424

			_data = request.form.get('data')
			_jdata = json.loads(_data)
			_aCols = ['postdate', 'akey', 'version', 'restart', 'title', 'suname', 'name', 'description']
			_bCols = ['postdate', 'akey', 'version', 'restartaction', 'title', 'supatchname', 'patchname', 'description64']

			if _jdata is not None:
				rows_added = 0
				for row in _jdata:
					# Main Apple Patch
					apple_obj = ApplePatch.query.filter(ApplePatch.supatchname == row['suname']).first()
					if apple_obj is None:
						aObj = ApplePatch()
						for index, item in enumerate(_aCols, start=0):
							setattr(aObj, _bCols[index], row[_aCols[index]])

						db.session.add(aObj)
						db.session.commit()
						rows_added += 1

					# Define Apple Patch Addition for MP
					apple_obj_alt = ApplePatchAdditions.query.filter(ApplePatchAdditions.supatchname == row['suname']).first()
					if apple_obj_alt is None:
						aObjAdd = ApplePatchAdditions()
						setattr(aObjAdd, 'version', row['version'])
						setattr(aObjAdd, 'supatchname', row['suname'])

						db.session.add(aObjAdd)
						db.session.commit()

				return {"result": 'rows added:' + str(rows_added), "errorno": 0, "errormsg": 'none'}, 201

			else:
				log_Error('[SUSPatchData][Post]: Patch data missing.')
				return {"result": '', "errorno": 1, "errormsg": 'Patch data missing.'}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SUSPatchData][Post][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class DataBaseConfigData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(DataBaseConfigData, self).__init__()

	def get(self):

		dbConfig = {'DB_USER':'','DB_PASS':'', 'DB_HOST':'','DB_PORT':3306,'DB_NAME': 'MacPatchDB3',
					'DATABASE_URI':'','TRACK_MODIFICATIONS':False,'ENGINE_OPTIONS':{}}

		if current_app.config['DB_USER']:
			dbConfig['DB_USER'] = current_app.config['DB_USER']
		if current_app.config['DB_PASS']:
			dbConfig['DB_PASS'] = ''
		if current_app.config['DB_HOST']:
			dbConfig['DB_HOST'] = current_app.config['DB_HOST']
		if current_app.config['DB_PORT']:
			dbConfig['DB_PORT'] = current_app.config['DB_PORT']
		if current_app.config['DB_NAME']:
			dbConfig['DB_NAME'] = current_app.config['DB_NAME']
		if current_app.config['DB_URI_STRING']:
			dbConfig['DATABASE_URI'] = current_app.config['DB_URI_STRING']
		if current_app.config['SQLALCHEMY_TRACK_MODIFICATIONS']:
			dbConfig['TRACK_MODIFICATIONS'] = current_app.config['SQLALCHEMY_TRACK_MODIFICATIONS']
		if current_app.config['SQLALCHEMY_ENGINE_OPTIONS']:
			dbConfig['ENGINE_OPTIONS'] = current_app.config['SQLALCHEMY_ENGINE_OPTIONS']

		return {"result": dbConfig, "errorno": 0, "errormsg": 'none'}, 200

# Routes

# SUS
srv_api.add_resource(SUSPatchData,			'/sus/patches/apple')

# Database
srv_api.add_resource(DataBaseConfigData,	'/db/config')