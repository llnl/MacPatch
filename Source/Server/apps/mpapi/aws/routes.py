from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *
from .. mpaws import *

parser = reqparse.RequestParser()

class GetAWSUrl(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(GetAWSUrl, self).__init__()

	def get(self, type, id, cuuid):
		# type = sw, patch
		# id = sw or patch ID
		if not isValidClientID(cuuid):
			log_Error('[GetAWSUrl][GET]: Failed to verify ClientID (%s)' % (cuuid))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify ClientID'}, 412

		if not isValidSignature(self.req_signature, cuuid, request.data, self.req_ts):
			log_Error('[GetAWSUrl][GET]: Failed to verify Signature for client (%s)' % (cuuid))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify Signature'}, 412


		try:
			aws = MPaws()
			_url = None
			err = 0
			errmsg = 'none'
			res = {'url': 'none', 'type': type}
			if type == 'patch':
				_url = aws.getS3UrlForPatch(id)
				if _url is not None:
					res = {'url':_url, 'type': type}
				else:
					err = 1
					errmsg = f'Patch data for {id} not found.'

			elif type == 'sw':
				_url = aws.getS3UrlForSoftware(id)
				if _url is not None:
					res = {'url':_url, 'type': type}
				else:
					err = 1
					errmsg = f'Software data for {id} not found.'
			if err == 0:
				return {"result": res, "errorno": err, "errormsg": errmsg}, 200
			else:
				return {"result": res, "errorno": err, "errormsg": errmsg}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[GetAWSUrl][Get][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


# Routes
aws_api.add_resource(GetAWSUrl,      '/aws/url/<string:type>/<string:id>/<string:cuuid>')