import uuid
import hashlib
import os.path
from datetime import datetime
from werkzeug.security import generate_password_hash
from mpapi import db
from mpapi.mputil import return_data_for_root_key, read_config_file
from mpapi.model import MpClientsRegistrationSettings, MpSiteKeys
from mpapi.model import AgentConfig, AgentConfigData
from mpapi.model import MpPatchGroup, PatchGroupMembers
from mpapi.model import MpAsusCatalogList
from mpapi.model import MpServer, MpServerList
from mpapi.model import MpSoftwareGroup, MpSoftwareGroupPrivs
from mpapi.model import MpClientGroups, MpClient, MpClientGroupMembers, MpClientTasks
from mpapi.model import MpClientSettings

basedir = os.path.abspath(os.path.dirname(__file__))

from sqlalchemy import *

def addDefaultData():
	addRegConfig()
	addSiteKeys()
	addClientConfig()
	addDefaultPatchGroup()
	addDefaultSWGroup()
	addDefaultSUSGroup()
	addDefaultServerList()
	addDefaultServerConfig()
	addDefaultClientGroup()
	addDefaultTasksToClientGroup()
	addDefaultSettingsClientGroup()

# Agent Registration Settings ------------------------------------------------
def hasRegConfig():
	res = MpClientsRegistrationSettings.query.all()
	if res is not None and len(res) >= 1:
		return True
	else:
		return False

def addRegConfig():
	# Check for config
	if hasRegConfig():
		return False

	# Add Agent Config
	db.session.add(MpClientsRegistrationSettings(autoreg="0", autoreg_key="999999999", client_parking="0"))
	db.session.commit()

# Add Site Keys  -------------------------------------------------------------
def hasSiteKeys():

	_siteData = getSiteKeyData()
	res = MpSiteKeys.query.filter(MpSiteKeys.pubKeyHash==_siteData['pubKeyHash'],
								MpSiteKeys.priKeyHash==_siteData['priKeyHash'],
								MpSiteKeys.active==1).first()
	if res is not None:
		return True
	else:
		return False

def addSiteKeys():
	# Check for config
	if hasSiteKeys():
		return False

	_siteData = getSiteKeyData()

	# Add Site Keys
	db.session.add(MpSiteKeys(pubKey=_siteData['pubKey'], pubKeyHash=_siteData['pubKeyHash'],
							priKey=_siteData['priKey'], priKeyHash=_siteData['priKeyHash'],
							active="1", mdate=datetime.now()))
	db.session.commit()

def resetSiteKeys():
	# Check for config
	if hasSiteKeys():
		return False

	_siteData = getSiteKeyData()

	res = MpSiteKeys.query.filter(MpSiteKeys.active == 1).first()
	if res is not None:
		setattr(res, 'active', 2)
		setattr(res, 'request_new_key', 1)
		db.session.commit()

	# Add Site Keys
	db.session.add(MpSiteKeys(pubKey=_siteData['pubKey'], pubKeyHash=_siteData['pubKeyHash'],
							priKey=_siteData['priKey'], priKeyHash=_siteData['priKeyHash'],
							active="1", mdate=datetime.now()))
	db.session.commit()

def getSiteKeyData():

	keyData = {}
	keyData['pubKey'] = ""
	keyData['pubKeyHash'] = ""
	keyData['priKey'] = ""
	keyData['priKeyHash'] = ""

	_priKeyPath = ""
	_pubKeyPath = ""

	srv_dict = return_data_for_root_key('server')

	if all(k in srv_dict for k in ("priKey", "pubKey")):
		_priKeyPath = srv_dict['priKey']
		_pubKeyPath = srv_dict['pubKey']

	if os.path.exists(_priKeyPath) and os.path.exists(_pubKeyPath):
		keyData['priKeyHash'] = md5ForFile(_priKeyPath)
		keyData['pubKeyHash'] = md5ForFile(_pubKeyPath)

		keyData['pubKey'] = open(_pubKeyPath, 'r').read()
		keyData['priKey'] = open(_priKeyPath, 'r').read()

	return keyData

def md5ForFile(fname):
	hash_md5 = hashlib.md5()
	with open(fname, "rb") as f:
		for chunk in iter(lambda: f.read(4096), b""):
			hash_md5.update(chunk)

	return hash_md5.hexdigest()

# Agent Config ---------------------------------------------------------------
def hasClientConfig():
	res = AgentConfig.query.filter(AgentConfig.isDefault == 1).first()
	if res is not None:
		return True
	else:
		return False

def addClientConfig():
	# Check for config
	if hasClientConfig():
		return False

	agentConf = {"AllowClient": "1", "AllowServer": "0", "Description": "Defautl Agent Config",
					"Domain": "Default", "PatchGroup": "Default", "Reboot": "1", "SWDistGroup": "Default",
					"MPProxyServerAddress": "AUTOFILL", "MPProxyServerPort": "3600", "MPProxyEnabled": "0",
					"MPServerAddress": "AUTOFILL", "MPServerPort": "3600", "MPServerSSL": "1",
					"CheckSignatures": "0", "MPServerAllowSelfSigned": "0"}

	# Create UUID
	_uuid = str(uuid.uuid4())
	# Add Agent Config
	db.session.add(AgentConfig(aid=_uuid, name="Default", isDefault="1", revision="0"))
	db.session.commit()

	# Add Agent Config Data
	for key in agentConf.keys():
		db.session.add(AgentConfigData(aid=_uuid, akey=key, akeyValue=agentConf[key], enforced="0"))
		db.session.commit()

	# Get & Set Revision Hash
	revHash = getRevisonForConfig(_uuid)
	if revHash != "NA":
		_hash = AgentConfig.query.filter(AgentConfig.aid == _uuid).first()
		_hash.revision = revHash
		db.session.commit()

def getRevisonForConfig(configID):

	res = AgentConfigData.query.filter(AgentConfigData.aid == configID).all()
	if res is not None:
		reslst = []
		for i in res:
			reslst.append(i.akeyValue.lower())

		reslststr = "".join(reslst)
		configHash = hashlib.md5(reslststr).hexdigest()

		return configHash
	else:
		return "NA"

# Patch Group ----------------------------------------------------------------
def hasDefaultPatchGroup():
	res = MpPatchGroup.query.filter(MpPatchGroup.name=='Default').first()
	if res is not None:
		return True
	else:
		return False

def addDefaultPatchGroup():
	# Check for config
	if hasDefaultPatchGroup():
		return False

	adm_dict = return_data_for_root_key('users')
	adm_user = adm_dict['admin']['name']

	# Create UUID
	_uuid = str(uuid.uuid4())

	# Add Agent Config
	db.session.add(MpPatchGroup(name="Default", id=_uuid, type="0"))
	db.session.commit()

	# Add Agent Config
	db.session.add(PatchGroupMembers(user_id=adm_user, patch_group_id=_uuid, is_owner="1"))
	db.session.commit()

# SW Dist Group --------------------------------------------------------------
def hasDefaultSWGroup():
	res = MpSoftwareGroup.query.filter(MpSoftwareGroup.gName == 'Default').first()
	if res is not None:
		return True
	else:
		return False

def addDefaultSWGroup():
	# Check for config
	if hasDefaultSWGroup():
		return False

	adm_dict = return_data_for_root_key('users')
	adm_user = adm_dict['admin']['name']

	# Create UUID
	_uuid = str(uuid.uuid4())

	# Add Agent Config
	dts = datetime.now()
	db.session.add(MpSoftwareGroupPrivs(gid=_uuid, uid=adm_user, isowner='1'))
	db.session.commit()
	db.session.add(MpSoftwareGroup(gid=_uuid, gName="Default", gDescription="Default", gType="0", gHash='0', state='1', cdate=dts, mdate=dts))
	db.session.commit()

# SUS Server Group -----------------------------------------------------------
def hasDefaultSUSGroup():
	res = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == '1').first()
	if res is not None:
		return True
	else:
		return False

def addDefaultSUSGroup():
	# Check for config
	if hasDefaultSUSGroup():
		return False

	# Add Default SUS Server Group
	db.session.add(MpAsusCatalogList(name="Default", listid='1', version="0"))
	db.session.commit()

# Server Config --------------------------------------------------------------
def hasDefaultServerConfig():
	res = MpServer.query.filter(MpServer.isMaster == 1).first()
	if res is not None:
		return True
	else:
		return False

def addDefaultServerConfig():
	# Check for config
	if hasDefaultServerConfig():
		return False

	# Add Agent Config
	db.session.add(MpServer(listid='1', server="localhost", port="3600", useSSL='1', useSSLAuth='0', allowSelfSignedCert='1', isMaster='1', isProxy='0', active='0'))
	db.session.commit()

def hasDefaultServerList():
	res = MpServerList.query.filter(MpServerList.listid == 1).first()
	if res is not None:
		return True
	else:
		return False

def addDefaultServerList():
	# Check for config
	if hasDefaultServerList():
		return False

	# Add Agent Config
	db.session.add(MpServerList(listid='1', name="Default", version="0"))
	db.session.commit()

# Client Groups ---------------------------------------------------------------
def hasDefaultClientGroup():
	res = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
	if res is not None:
		return True
	else:
		return False

def addDefaultClientGroup():
	# Check for config
	if hasDefaultClientGroup():
		return False

	# Add Agent Config
	_uuid = str(uuid.uuid4())
	db.session.add(MpClientGroups(group_id=_uuid, group_name="Default", group_owner="mpadmin"))
	db.session.commit()

def addDefaultTasksToClientGroup():
	# Check if Default group exists
	gid = None
	res = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
	if res is not None:
		gid = res.group_id
	else:
		log_Error("Default client group does not exist.")
		log_Error("Can not add default agent trasks.")
		return False

	# Check for default tasks
	hasTasks = hasDefaultClientGroupTasks(gid)
	if hasTasks == 0:
		# Add Tasks
		tasks = readDefaultTasks()
		for t in tasks:
			_task = MpClientTasks()
			setattr(_task, 'group_id', gid)
			for key, value in t.iteritems():
				setattr(_task, key, value)
			db.session.add(_task)

		db.session.commit()
		return True
	elif hasTasks == 2:
		log_Error("There was a problem getting the data on the default tasks.")
		return False

	return False

def hasDefaultClientGroupTasks(gid):
	if gid is None:
		return 2

	res = MpClientTasks.query.filter(MpClientTasks.group_id == gid).count()
	if res <= 0:
		return 0
	else:
		return 1

	# Return 2 if error, we should not get here
	return 2

def readDefaultTasks():
	tasks = None
	jFile = os.path.join(basedir, 'mpconsole/static/json/default_tasks.json')
	if os.path.exists(jFile):
		jData = read_config_file(jFile)
		tasks = jData['mpTasks']

	return tasks

def hasDefaultSettingsClientGroup():
	res = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
	if res is not None:
		settings  = MpClientSettings.query.filter(MpClientSettings.group_id == res.group_id).all()
		if len(settings) >= 8:
			return True
		else:
			return False
	else:
		return False

def addDefaultSettingsClientGroup():
	# Check for config
	if hasDefaultSettingsClientGroup():
		return False

	# Add Agent Config
	clientGrp = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
	groupID = clientGrp.group_id

	patchGroup = MpPatchGroup.query.filter(MpPatchGroup.name == 'Default').first()
	swGroup = MpSoftwareGroup.query.filter(MpSoftwareGroup.gName == 'Default').first()
	form = {'patch_group': patchGroup.id,
			'software_group': swGroup.gid,
			'inherited_software_group':'None',
			'allow_client':'1',
			'allow_server':'1',
			'allow_reboot':'1',
			'verify_signatures':'0',
			'patch_state':'Production',
			'pre_stage_patches':'1'}

	for key, value in form.iteritems():
		mpcs = MpClientSettings()
		setattr(mpcs, 'group_id', groupID)
		setattr(mpcs, 'key', key)
		setattr(mpcs, 'value', str(value))
		db.session.add(mpcs)

	db.session.commit()
	return True

'''
	Commands for mpconsole.py
'''
# Add Default Admin Account ----------------------------------------------------
def addDefaultAdminAccount():
	usr_dict = return_data_for_root_key('users')
	if 'admin' in usr_dict:
		adm_account = usr_dict['admin']
		if adm_account['enabled']:
			_pass = generate_password_hash(adm_account['pass'])
			db.session.add(AdmUsers(user_id=adm_account['name'], user_RealName="MPAdmin", user_pass=_pass, enabled='1'))
			db.session.commit()
		return True
	return False

# Upgrade Tasks ---------------------------------------------------------------
def addUnassignedClientsToGroup():
	# Check for config
	res0 = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
	res1 = MpClient.query.all()
	res2 = MpClientGroupMembers.query.all()

	default_gid = 0
	if res0:
		default_gid = res0.group_id
	else:
		return

	clients_in_group = []
	for x in res2:
		clients_in_group.append(str(x.cuuid))

	for x in res1:
		if x.cuuid in clients_in_group:
			continue
		else:
			db.session.add(MpClientGroupMembers(group_id=default_gid, cuuid=x.cuuid))

	db.session.commit()
