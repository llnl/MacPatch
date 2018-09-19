from flask import request
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

		except IntegrityError, exc:
			log_Error('[SUSPatchData][Post][IntegrityError]: %s' % (exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[SUSPatchData][Post][Exception][Line: %d] Message: %s' % (
				exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500


# Routes
srv_api.add_resource(SUSPatchData,      '/sus/patches/apple')
