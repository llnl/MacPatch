from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from ast import literal_eval

from itsdangerous.url_safe import URLSafeTimedSerializer as Serializer
from itsdangerous import BadSignature, SignatureExpired

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *

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

			log_Debug('[GetAuthToken][Get]: Token (%s) issued for user (%s) and password.' % (_token.decode('utf-8'), _body['authUser']))
			return {"result": {'token': _token.decode('utf-8')}, "errorno": 0, "errormsg": 'none'}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[GetAuthToken][Get][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

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

			log_Debug('[GetAuthToken][Post]: Token (%s) issued for user (%s) and password.' % (_token.decode('UTF-8'), _body['authUser']))
			return {"result": {'token': _token.decode('UTF-8')}, "errorno": 0, "errormsg": 'none'}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[GetAuthToken][POST][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Routes
auth_api.add_resource(GetAuthToken,      '/auth/token')
