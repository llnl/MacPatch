from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from ast import literal_eval

from itsdangerous import TimedJSONWebSignatureSerializer as Serializer, BadSignature, SignatureExpired

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

class GetAuthToken(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(GetAuthToken, self).__init__()

	def get(self):
		try:
			_body = request.get_json(silent=True)
			'''
				Dict format of get auth token request
				{'authUser': 'tom', 'authPass': 'passiton'}
			'''

			if not verify_auth_password(_body['authUser'], _body['authPass']):
				log_Error('[GetAuthToken][Get]: Failed to verify user (%s) and password.' % (_body['authUser']))
				return {"result": {}, "errorno": 401, "errormsg": 'Unauthorized'}, 401

			s = Serializer(current_app.config['SECRET_KEY'], expires_in=3600)
			_token = s.dumps({'id': _body['authUser']})

			log_Debug('[GetAuthToken][Get]: Token (%s) issued for user (%s) and password.' % (_token, _body['authUser']))
			return {"result": {'token': _token}, "errorno": 0, "errormsg": 'none'}, 200

		except IntegrityError, exc:
			log_Error('[GetAuthToken][Get][except]: %s' % (exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[GetAuthToken][Get][Exception][Line: %d] Message: %s' % (
				exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': {}}, 500

	def post(self):
		try:
			_body = request.get_json(silent=True)
			if not _body:
				_body = literal_eval(request['data'])

			'''
				Dict format of get auth token request
				{'authUser': 'tom', 'authPass': 'passiton'}
			'''

			if not verify_auth_password(_body['authUser'], _body['authPass']):
				log_Error('[GetAuthToken][Post]: Failed to verify user (%s) and password.' % (_body['authUser']))
				return {"result": {}, "errorno": 401, "errormsg": 'Unauthorized'}, 401

			s = Serializer(current_app.config['SECRET_KEY'], expires_in=3600)
			_token = s.dumps({'id': _body['authUser']})

			log_Debug('[GetAuthToken][Post]: Token (%s) issued for user (%s) and password.' % (_token, _body['authUser']))
			return {"result": {'token': _token}, "errorno": 0, "errormsg": 'none'}, 200

		except IntegrityError, exc:
			log_Error('[GetAuthToken][Post][except]: %s' % (exc.message))
			return {"result": '', "errorno": 500, "errormsg": exc.message}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[GetAuthToken][Post][Exception][Line: %d] Message: %s' % (exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': {}}, 500

# Routes
auth_api.add_resource(GetAuthToken,      '/auth/token')
