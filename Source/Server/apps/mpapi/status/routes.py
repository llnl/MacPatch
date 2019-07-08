from werkzeug import secure_filename
from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from ast import literal_eval

from M2Crypto import RSA, util

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

class ServerStatus(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ServerStatus, self).__init__()

	def get(self):
		try:
			log_Info("Running Server Status With DB Check")
			res = MpServer.query.filter(MpServer.isMaster == 1).first()

			admUsrLst = []
			admUsr = AdmGroupUsers.query.filter(AdmGroupUsers.email_notification == 1, AdmGroupUsers.user_email != None).all()
			for i in admUsr:
				admUsrLst.append(i.user_email)

			if res:
				res_data = {'status': "Server is up and db connection is good."}
				return {"result": res_data, "errorno": 0, "errormsg": 'none'}, 200
			else:
				res_data = {'status': "Server is up and db connection is no good."}
				return {"result": res_data, "errorno": 404, "errormsg": ''}, 404

		except IntegrityError as exc:
			log_Error('[ServerStatus][Get][IntegrityError] Message: %s' % (exc.message))
			return {'errorno': 500, 'errormsg': exc.message, 'result': ''}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[ServerStatus][Get][Exception][Line: %d] Message: %s' % (
				exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500

class ServerStatusNoDB(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ServerStatusNoDB, self).__init__()

	def get(self):
		try:
			log_Info("Running Server Status With DB NO Check")
			res_data = {'status': "Server is up flask is working."}
			return {"result": res_data, "errorno": 0, "errormsg": 'none'}, 200

		except IntegrityError as exc:
			log_Error('[ServerStatusNoDB][Get][IntegrityError] Message: %s' % (exc.message))
			return {'errorno': 500, 'errormsg': exc.message, 'result': ''}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[ServerStatusNoDB][Get][Exception][Line: %d] Message: %s' % (
				exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500

class TokenStatus(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(TokenStatus, self).__init__()

	def get(self, token):
		try:
			_user = verify_auth_token(token)
			if not _user or (_user == "BadSignature" or _user == "SignatureExpired"):
				return {"result": False, "errorno": 1, "errormsg": ''}, 200
			else:
				return {"result": True, "errorno": 0, "errormsg": ''}, 200

		except IntegrityError as exc:
			log_Error('[TokenStatus][Get][IntegrityError] Message: %s' % (exc.message))
			return {'errorno': 500, 'errormsg': exc.message, 'result': ''}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[TokenStatus][Get][Exception][Line: %d] Message: %s' % (exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': ''}, 500

class TestUpload(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(TestUpload, self).__init__()

	def post(self, agent_id, token):

		try:
			r = request
			_files = r.files
			# _filesName = ['fBase', 'fUpdate', 'fComplete']

			fData = literal_eval(r.form['data'])
			log_Info('[TestUpload][Post]: %s' % (fData))

			fBase = r.files['fBase']
			fUpdate = r.files['fUpdate']
			fAgent = r.files['fComplete']
			if not fBase or not fUpdate or not fAgent:
				log_Error('[TestUpload][Post]: Failed to verify uploaded files.')
				return {"result": '', "errorno": 425, "errormsg": 'Failed to verify uploaded files.'}, 425

			# Verify if Agent already exists
			# agent_ver = fData['app']['agent_ver']
			# app_ver = fData['app']['version']

			# Save uploaded files
			upload_dir = os.path.join("/tmp", agent_id)
			_files = [fBase, fUpdate, fAgent]
			if not os.path.isdir(upload_dir):
				os.makedirs(upload_dir)

			for f in _files:
				log_Debug('Saving: %s' % (f.filename))
				filename = secure_filename(f.filename)
				_pkg_file_path = os.path.join(upload_dir, filename)

				if os.path.exists(_pkg_file_path):
					log_Debug('Removing existing agent file (%s)' % (_pkg_file_path))
					os.remove(_pkg_file_path)

				f.save(_pkg_file_path)

			return {"result": '', "errorno": 0, "errormsg": ""}, 200
		except OSError as err:
			log_Error('[MP_UploadAgentPackage][Post][OSError] MP_UploadAgentPackage: %s' % (format(err)))
			return {"result": '', "errorno": err.errno, "errormsg": format(err)}, 500
		except IntegrityError as exc:
			log_Error('[MP_UploadAgentPackage][Post][IntegrityError] MP_UploadAgentPackage: %s' % (exc.message))
			return {"result": '', "errorno": 500, "errormsg": ""}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[MP_UploadAgentPackage][Post][Exception][Line: %d] Message: %s' % (
				exc_tb.tb_lineno, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': {}}, 500

# Routes
status_api.add_resource(ServerStatus,      '/server/status')
status_api.add_resource(ServerStatusNoDB,  '/server/status/nodb')

status_api.add_resource(TokenStatus,      '/token/valid/<string:token>')

status_api.add_resource(TestUpload,      '/test/upload/<string:agent_id>/<string:token>')
