from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from hashlib import sha1, sha256
import uuid
import re


from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

class SUServers(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SUServers, self).__init__()

	def get(self, cuuid):

		try:
			if not isValidClientID(cuuid):
				log_Error('[SUServerList][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[SUServerList][Get]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[SUServerList][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			client = MpClient.query.filter(MpClient.cuuid == cuuid).first()
			c_osver = client.osver

			_serverObj = suServerListForID(1, c_osver)

			log_Debug('[SUServerList][Get] CUUID: %s Result: %s' % (cuuid, _serverObj))
			return {'errorno': 0, 'errormsg': '', 'result': _serverObj}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SUServerList][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


class SUServersVersion(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SUServersVersion, self).__init__()

	def get(self, cuuid=None, list_id=1):

		try:
			if not isValidClientID(cuuid):
				log_Error('[SUSListVersion][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[SUSListVersion][Get]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[SUSListVersion][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			_result = 404
			_server = {"version": 0, "listid": 0}

			log_Debug("[SUSListVersion][Get][%s]: Getting SUS Catalog list using id (%s)" % (cuuid, list_id))
			q_result = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == list_id).first()
			if q_result is not None:
				_server['version'] = q_result.version
				_server['listid'] = q_result.listid
				_result = 200
			else:
				log_Warn('[SUSListVersion][Get][%s]: No list found for list id (%s)' % (cuuid, list_id))

			return {'errorno': '0', 'errormsg': '', 'result': _server}, _result

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SUSListVersion][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


class Servers(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(Servers, self).__init__()

	def get(self, cuuid, list_id=1):

		try:
			if not isValidClientID(cuuid):
				log_Error('[ServerList][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[ServerList][Get]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[ServerList][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			_serverObj = serverListForID(list_id)

			if _serverObj is not None:
				return {'errorno': '0', 'errormsg': '', 'result': _serverObj}, 200

			# No Result
			log_Error('[ServerList][Get][%s]: Server List Not Found for id (%d)' % (cuuid, list_id))
			return {'errorno': 404, 'errormsg': 'Server List Not Found', 'result': {}}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ServerList][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


class ServersVersion(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ServersVersion, self).__init__()

	def get(self, cuuid=None, list_id=1):

		try:
			if not isValidClientID(cuuid):
				log_Error('[ServerListVersion][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[ServerListVersion][Get]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[ServerListVersion][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			_result = 404
			_server = {"version": 0, "listid": 0}

			q_result = MpServerList.query.filter(MpServerList.listid == list_id).first()
			if q_result is not None:
				_server['version'] = q_result.version
				_server['listid'] = q_result.listid
				_result = 200
			else:
				log_Warn('[ServerListVersion][Get][%s]: No list found for list id (%d)' % (cuuid, list_id))

			return {'errorno': '0', 'errormsg': '', 'result': _server}, _result

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ServerListVersion][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


class ServerLog(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ServerLog, self).__init__()

	def get(self, reqid, type, serverkey):
		try:
			_results = []
			qry = MpServerLogReq.query.filter(MpServerLogReq.uuid == reqid).first()
			if qry is None:
				return {'data': _results, 'total': len(_results)}, 404

			# Get DateTime
			dt = datetime.now()
			dts = (dt - datetime(1970, 1, 1)).total_seconds()

			# Key Has Expired
			if (dts - float(qry.dts)) > 600:
				return {'data': _results, 'total': len(_results)}, 401

			#srvHashStr = "{}{}{}".format(qry.uuid, qry.dts, qry.type)
			#srvHash = sha256(srvHashStr).hexdigest()

			# Verify Hash
			#if srvHash != serverkey:
			#	return {'data': _results, 'total': len(_results)}, 403

			_results = self.parseLogFile(type)
			return {'data': _results, 'total': len(_results)}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ServerLog][Get][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def parseLogFile(self, type):
		try:
			logFile = '/tmp/fool'
			if type == 'mpwsapi':
				logFile = '/opt/MacPatch/Server/apps/logs/mpwsapi.log'
			elif type == 'mpconsole':
				logFile = '/opt/MacPatch/Server/apps/logs/mpconsole.log'

			l = logline()
			lines = []
			with open(logFile, "r") as ins:
				for line in ins:
					l.parseLine(line.rstrip('\n'))
					lines.insert(0, l.printLine())

			return lines

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ServerList][Get][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

''' ------------------------------- '''
''' NOT A WEB SERVICE CLASS         '''

def suServerListForID(list_id, os_ver):

	_serverObj = {'version': 0, 'data': []}
	_serverList = []

	osver = os_ver.split('.')

	q_catalog_list = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == list_id).first()

	if q_catalog_list is not None:
		q_cats = MpAsusCatalog.query.filter(MpAsusCatalog.os_major == int(osver[0]), MpAsusCatalog.os_minor == int(osver[1])).order_by(
			MpAsusCatalog.c_order.asc()).all()

		_serverObj['version'] = q_catalog_list.version
	else:
		_serverObj['version'] = '0'

	_server_dict = {}
	if q_cats is not None:
		for row in q_cats:
			if row.proxy == 1:
				_server_dict = {'CatalogURL': row.catalog_url, 'serverType': 1}
			else:
				_server_dict = {'CatalogURL': row.catalog_url, 'serverType': 0}

			_serverList.append(_server_dict)

	# Add OS vesion servers array to main Dict
	_serverObj['data'] = _serverList

	return _serverObj

def serverListForID(list_id):

	_serverObj = {'version': 0, 'data': []}
	_serverList = []

	q_result = MpServerList.query.filter(MpServerList.name == "Default", MpServerList.listid == list_id).first()

	if q_result is not None:
		_serverObj['version'] = q_result.version

		q_servers_result = MpServer.query.filter(MpServer.active == 1, MpServer.listid == list_id).all()
		if q_servers_result is not None:
			for row in q_servers_result:
				_srvObj = Server()
				_server_dict = _srvObj.importFromRowReturnDictionary(row.asDict)
				_serverList.append(_server_dict)

			# Server list is built, now add to result
			_serverObj['data'] = _serverList

		return _serverObj

	else:
		return None

class Server(object):
	def __init__(self):
		self.host = "localhost"
		self.port = "2600"
		self.useHTTPS = 1
		self.allowSelfSigned = 0
		self.useTLSAuth = 0
		self.serverType = 0

	def struct(self):
		return (self.__dict__)

	def keys(self):
		return list(self.__dict__.keys())

	def importFromRowReturnDictionary(self, row):
		_my_keys = ['host', 'port', 'useHTTPS', 'allowSelfSigned', 'useTLSAuth']
		_keys = ['server', 'port', 'useSSL', 'allowSelfSignedCert', 'useSSLAuth']

		for idx, key in enumerate(_my_keys):
			setattr(self, key, row[_keys[idx]])

		if int(row['isMaster']) == 1:
			self.serverType = 0
		else:
			if int(row['isMaster']) == 0 and int(row['isProxy']) == 0:
				self.serverType = 1
			elif int(row['isMaster']) == 0 and int(row['isProxy']) == 1:
				self.serverType = 2

		return self.struct()

class logline(object):  # no instance of this class should be created

	def __init__(self):
		self.date = ''
		self.app = ''
		self.level = ''
		self.text = ''

	def parseLine(self,line):
		try:
			_date = line.split(",")
			self.date = _date[0]
			x = re.search('\[(.*?)\]\[(.*?)\]', line)
			self.app = x.group(1)
			self.level = x.group(2)
			self.text = line.split("---")[1]
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[logline][Exception][Line: %d] %s' % (exc_tb.tb_lineno, message))

	def printLine(self):
		row = {}
		row['date'] = self.date
		row['app'] = self.app
		row['level'] = self.level
		row['text'] = self.text
		return row

# Add Routes Resources

# MP 3.1.0
servers_2_api.add_resource(SUServersVersion,    '/suservers/version/<string:cuuid>')
servers_2_api.add_resource(SUServers,      		'/suservers/<string:cuuid>')

servers_2_api.add_resource(ServersVersion, 		'/servers/version/<string:cuuid>')
servers_2_api.add_resource(Servers,        		'/servers/<string:cuuid>')

servers_2_api.add_resource(ServerLog,        	'/server/log/<string:reqid>/<string:type>/<string:serverkey>')
