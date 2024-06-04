from flask import request
from flask_restful import reqparse
from datetime import datetime
from werkzeug.utils import secure_filename

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *

import hashlib

parser = reqparse.RequestParser()

# Agent Updates
class AgentInstall(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(AgentInstall, self).__init__()

	def post(self, client_id, agent_ver):
		try:

			ai = AgentInstall()
			setattr(ai, 'cuuid', client_id)
			setattr(ai, 'install_date', datetime.now())
			setattr(ai, 'agent_ver', agent_ver)
			db.session.add(ai)
			db.session.commit()

			return {"errorno": 0, "errormsg": 'none', "result": {}, 'signature': {}}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentConfigInfo][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

# Upload Agent Package Using Python Script
class UploadAgentPackages(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(UploadAgentPackages, self).__init__()

	def post(self, agent_id, token):

		if token != '0':
			_user = verify_auth_token(token)
			if not _user or (_user == "BadSignature" or _user == "SignatureExpired"):
				log_Error('[UploadAgentPackages][Post]: Failed to verify token')
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify token'}, 424

			if not isValidAdminUser(_user):
				log_Error('[UploadAgentPackages][Post]: Failed to verify user (%s) rights' % (_user))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify user rights'}, 424
		else:
			_user = "Dev User 0"

		# Get files data from request
		r = request
		_files = r.files

		# Form Data as json is stored in a file oject, requests cant do better
		_jDataRaw = _files['jData'].read().decode('utf-8')
		_jData =  json.loads(_jDataRaw)

		fData = _jData
		fBase = _files['fBase']
		fBaseHash = ""
		fUpdate = _files['fUpdate']
		fUpdateHash = ""
		fAgent = _files['fComplete']
		if not fBase or not fUpdate or not fAgent:
			log_Error('[UploadAgentPackages][Post]: Failed to verify uploaded files. User: %s' % (_user))
			return {"result": '', "errorno": 425, "errormsg": 'Failed to verify uploaded files.'}, 425

		if not 'app' in fData and not 'update' in fData:
			log_Error('[UploadAgentPackages][Post]: Failed to verify uploaded data. User: %s' % (_user))
			return {"result": '', "errorno": 425, "errormsg": 'Failed to verify uploaded data.'}, 425

		# Verify if Agent already exists
		pluginsData = []
		profilesData = []

		if 'plugins' in fData:
			pluginsData = fData['plugins']
		if 'profiles' in fData:
			profilesData = fData['profiles']

		agent_ver = fData['app']['agent_ver']
		app_ver = fData['app']['version']
		app_build = fData['app']['build']
		hasAgent = MpClientAgent.query.filter(MpClientAgent.agent_ver == agent_ver,
											   MpClientAgent.version == app_ver,
											   MpClientAgent.build == app_build,
											   MpClientAgent.type == "app").first()
		if hasAgent:
			log_Error('[UploadAgentPackages][Post]: Agent(AGENT VER: {}, APP VER: {}) Already Exists User: {}'.format(agent_ver, app_ver, _user))
			return {"result": '', "errorno": 426, "errormsg": 'Agent Already Exists'}, 426

		# Save uploaded files
		upload_dir = os.path.join(current_app.config['AGENT_CONTENT_DIR'], agent_id)
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
			if "Base.pkg" in f.filename:
				fBaseHash = fileHashSHA1(_pkg_file_path)
			elif "Updater.pkg" in f.filename:
				fUpdateHash = fileHashSHA1(_pkg_file_path)

		# Save Agent Data to database
		log_Debug('[UploadAgentPackages][Post]: Create Base Agent Data Record')
		agentObjApp = MpClientAgent()
		setattr(agentObjApp, 'puuid', agent_id)
		setattr(agentObjApp, 'type', 'app')
		setattr(agentObjApp, 'osver', fData['app']['osver'])
		setattr(agentObjApp, 'agent_ver', fData['app']['agent_ver'])
		setattr(agentObjApp, 'version', fData['app']['version'])
		setattr(agentObjApp, 'build', fData['app']['build'])
		setattr(agentObjApp, 'pkg_name', fData['app']['pkg_name'])
		setattr(agentObjApp, 'pkg_url', os.path.join('/mp-content/clients', agent_id, fBase.filename))
		setattr(agentObjApp, 'pkg_hash', fBaseHash)
		setattr(agentObjApp, 'cdate', datetime.now())
		setattr(agentObjApp, 'mdate', datetime.now())
		log_Debug('[UploadAgentPackages][Post]: Add Base Agent Data Record')
		db.session.add(agentObjApp)

		log_Debug('[UploadAgentPackages][Post]: Create Updater Agent Data Record')
		agentObjUpdt = MpClientAgent()
		setattr(agentObjUpdt, 'puuid', agent_id)
		setattr(agentObjUpdt, 'type', 'update')
		setattr(agentObjUpdt, 'osver', fData['update']['osver'])
		setattr(agentObjUpdt, 'agent_ver', fData['update']['agent_ver'])
		setattr(agentObjUpdt, 'version', fData['update']['version'])
		setattr(agentObjUpdt, 'build', fData['update']['build'])
		setattr(agentObjUpdt, 'pkg_name', fData['update']['pkg_name'])
		setattr(agentObjUpdt, 'pkg_url', os.path.join('/mp-content/clients', agent_id, fUpdate.filename))
		setattr(agentObjUpdt, 'pkg_hash', fUpdateHash)
		setattr(agentObjUpdt, 'cdate', datetime.now())
		setattr(agentObjUpdt, 'mdate', datetime.now())
		log_Debug('[UploadAgentPackages][Post]: Add Updater Agent Data Record')
		db.session.add(agentObjUpdt)

		# Add Profiles & Plugins
		for _plugin in pluginsData:
			agentPlugin = MpClientAgentPlugins()
			setattr(agentPlugin, 'puuid', agent_id)
			setattr(agentPlugin, 'plugin', _plugin['plugin'])
			setattr(agentPlugin, 'bundleIdentifier', _plugin['bundleIdentifier'])
			setattr(agentPlugin, 'version', _plugin['version'])
			db.session.add(agentPlugin)

		for _profile in profilesData:
			agentProfile = MpClientAgentProfiles()
			setattr(agentProfile, 'puuid', agent_id)
			setattr(agentProfile, 'displayName', _profile['displayName'])
			setattr(agentProfile, 'identifier', _profile['identifier'])
			setattr(agentProfile, 'organization', _profile['organization'])
			setattr(agentProfile, 'version', _profile['version'])
			setattr(agentProfile, 'fileName', _profile['fileName'])
			db.session.add(agentProfile)

		db.session.commit()

		return {"result": '', "errorno": 0, "errormsg": ""}, 200

# Private

def fileHashSHA1(file):
	BUF_SIZE = 65536  # lets read stuff in 64kb chunks!
	sha1 = hashlib.sha1()

	with open(file, 'rb') as f:
		while True:
			data = f.read(BUF_SIZE)
			if not data:
				break
			sha1.update(data)

	return sha1.hexdigest()

# Add Routes Resources
agent_3_api.add_resource(AgentInstall,			'/agent/install/<string:client_id>/<string:agent_ver>')

agent_3_api.add_resource(UploadAgentPackages,	'/agent/upload/<string:agent_id>/<string:token>')