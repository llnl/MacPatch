from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

class SUSCatalogs(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SUSCatalogs, self).__init__()

	def get(self, cuuid, osminor, osmajor="10"):

		try:
			if not isValidClientID(cuuid):
				log_Error('[SUSCatalogs][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				if current_app.config['ALLOW_MIXED_SIGNATURES']:
					log_Info('[SUSCatalogs][Get]: ALLOW_MIXED_SIGNATURES is enabled.')
				else:
					log_Error('[SUSCatalogs][Get]: Failed to verify Signature for client (%s)' % (cuuid))
					return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			q_catalogs = MpAsusCatalog.query.filter(MpAsusCatalog.os_major == int(osmajor),
													MpAsusCatalog.os_minor == int(osminor)).order_by(MpAsusCatalog.c_order.asc()).all()

			# CatalogURLS
			# ProxyCatalogURLS
			_errorno = 500
			_result = 404
			catalogs = {}
			cats = []
			proxy_cats = []

			if catalogs is not None:
				if len(q_catalogs) >= 1:
					for row in q_catalogs:
						if row.proxy == 0:
							cats.append(row.catalog_url)
						elif row.proxy == 1:
							proxy_cats.append(row.catalog_url)

					catalogs['CatalogURLS'] = cats
					catalogs['ProxyCatalogURLS'] = proxy_cats
					_errorno = 0
					_result = 200
				else:
					log_Error('[SUSCatalogs][Get][%s]: Error no sus catalogs found.' % (cuuid))
					_errorno = 404
			else:
				log_Error('[SUSCatalogs][Get][%s]: Error no catalogs found.' % (cuuid))

			return {'errorno': _errorno, 'errormsg': '', 'result': catalogs}, _result

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SUSCatalogs][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class SUServerList(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SUServerList, self).__init__()

	def get(self, cuuid, osminor, osmajor="10"):

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

			_osver = '{}.{}'.format(osmajor, osminor)
			_serverObj = ServerInfo()
			_serverObj = suServerListForID(1,_osver)

			log_Debug('[SUServerList][Get] CUUID: %s Result: %s' % (cuuid, _serverObj.struct()))
			return {'errorno': 0, 'errormsg': '', 'result': _serverObj.struct()}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SUServerList][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class SUSListVersion(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SUSListVersion, self).__init__()

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

class ServerList(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ServerList, self).__init__()

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
				return {'errorno': '0', 'errormsg': '', 'result': _serverObj.struct()}, 200

			# No Result
			log_Error('[ServerList][Get][%s]: Server List Not Found for id (%d)' % (cuuid, list_id))
			return {'errorno': 404, 'errormsg': 'Server List Not Found', 'result': {}}, 404

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[ServerList][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

class ServerListVersion(MPResource):
	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ServerListVersion, self).__init__()

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

''' ------------------------------- '''
''' NOT A WEB SERVICE CLASS         '''

def suServerListForID(list_id, os_ver):

	_serverObj = ServerInfo()
	_serverList = []

	osver = os_ver.split('.')

	q_catalog_list = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == list_id).first()

	if q_catalog_list is not None:
		q_cats = MpAsusCatalog.query.filter(MpAsusCatalog.os_major == int(osver[0]), MpAsusCatalog.os_minor == int(osver[1])).order_by(
			MpAsusCatalog.c_order.asc()).all()

		_serverObj.id = q_catalog_list.listid
		_serverObj.name = q_catalog_list.name
		_serverObj.version = q_catalog_list.version
	else:
		_serverObj.id = ''
		_serverObj.name = 'NA'
		_serverObj.version = '0'

	_catalog = {'os': osver[1], 'servers': []}
	_server_dict = {}
	if q_cats is not None:
		for row in q_cats:
			if row.proxy == 1:
				_server_dict = {'CatalogURL': row.catalog_url, 'serverType': 1}
			else:
				_server_dict = {'CatalogURL': row.catalog_url, 'serverType': 0}

			_serverList.append(_server_dict)
		# Add the to the os version list dict
		_catalog['servers'] = _serverList

	# Add OS vesion servers array to main Dict
	_serverObj.servers = [_catalog]

	return _serverObj

def serverListForID(list_id):

	_serverObj = ServerInfo()
	_serverList = []

	q_result = MpServerList.query.filter(MpServerList.name == "Default", MpServerList.listid == list_id).first()

	if q_result is not None:
		setattr(_serverObj, "name", q_result.name)
		setattr(_serverObj, "version", q_result.version)
		setattr(_serverObj, "id", q_result.listid)

		q_servers_result = MpServer.query.filter(MpServer.active == 1, MpServer.listid == list_id).all()
		if q_servers_result is not None:
			for row in q_servers_result:
				_srvObj = Server()
				_server_dict = _srvObj.importFromRowReturnDictionary(row.asDict)
				_serverList.append(_server_dict)

			setattr(_serverObj, "servers", _serverList)

		return _serverObj

	else:
		return None

class ServerInfo(object):
	def __init__(self):
		self.name = "Default"
		self.version = "0"
		self.id = "NA"
		self.servers = []

	def struct(self):
		return (self.__dict__)

	def keys(self):
		return list(self.__dict__.keys())

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

# Add Routes Resources
# Old
servers_api.add_resource(SUSCatalogs,       '/sus/catalogs/<string:osminor>/<string:cuuid>', endpoint='susUsingMinor')
servers_api.add_resource(SUSCatalogs,       '/sus/catalogs/<string:osmajor>/<string:osminor>/<string:cuuid>', endpoint='susUsingMajorMinor')
# New
servers_api.add_resource(SUSListVersion,    '/sus/list/version/<string:cuuid>/<int:list_id>')
servers_api.add_resource(SUServerList,      '/sus/catalogs/list/<string:osminor>/<string:cuuid>', endpoint='asusUsingMinor')
servers_api.add_resource(SUServerList,      '/sus/catalogs/list/<string:osmajor>/<string:osminor>/<string:cuuid>', endpoint='asusUsingMajorMinor')

servers_api.add_resource(ServerList,        '/server/list/<string:cuuid>')
servers_api.add_resource(ServerList,        '/server/list/<int:list_id>/<string:cuuid>', endpoint='srvListWithID')

servers_api.add_resource(ServerListVersion, '/server/list/version/<string:cuuid>', endpoint='srvListVerWithClientID')
servers_api.add_resource(ServerListVersion, '/server/list/version/<int:list_id>/<string:cuuid>', endpoint='srvListVerWithID')
