import requests
from requests.auth import HTTPDigestAuth
import json
import pymysql

# ----------------------------------------------
# Notes:
# Version: 1
#
# This script will quickly check all api's for the MacPatch server.
# It does not include all API's as some dont have tests yet or
# body data for the post message.
#
# Please note, for api's to pass the database must have data for
# the api to return. A error 404,405 are no data found. A 500 error
# is a broken api.
#
# To use it source the /opt/MacPatch/Server/env/api/bin/activate
# then run python api_tests.py
# ----------------------------------------------

restServer="http://127.0.0.1:5001"
client_id='BDA43E37-0296-5E33-9DA3-1CDB58998558'

# Agent Version
agent_ver="3.1.2.8"
agent_build="8"

# AuthToken (Please note user name and password in clear)
authUser='mpadmin' 	# Default mp admin account
authPass='pass' 	# Password needs to be changed

# Agent Plugin
plugin_name='NIHAuthPlugin'
plugin_bundleID='gov.llnl.mp.inv.NIHAuthPlugin'
plugin_version='1.1.1'

# Software
swTaskID='095E64D9-391F-4154-876695C0EE17E689' #XQuartz

# Servers
suSListVersionID='1'	# Default List ID
serverListVersionID='1' # Default List ID

# Url List to test
get_urls=[]

def testDB():

	# Create a connection object to the MySQL Database Server
	hostName = "10.254.196.144"
	userName = "mpdbadm"
	userPassword = "Apple2e123"
	databaseName = "MacPatchDB33QA"

	cusrorType = pymysql.cursors.DictCursor

	databaseConnection = pymysql.connect(host=hostName,
										 user=userName,
										 password=userPassword,
										 db=databaseName,
										 port=3306,
										 cursorclass=cusrorType)

	try:
		# Cursor object creation
		cursorObject = databaseConnection.cursor()

		# Execute the sqlQuery
		res = cursorObject.execute("call AgentUpdaterRID()")
		print(res)


		# Print the result of the executed stored procedure
		for result in cursorObject.fetchall():
			print(result)

	except Exception as e:
		print("Exeception occured:{}".format(e))

	finally:
		databaseConnection.close()

# ------------------------------------
# HTTP Method
# ------------------------------------
def makeRESTCall(url, method, body=None, type=None):
	_url = "{}{}".format(restServer, url)

	requests.packages.urllib3.disable_warnings()

	if type == None or type == "get":
		if body is not None:
			myResponse = requests.get(_url, params=body, verify=False)
		else:
			myResponse = requests.get(_url, verify=False)
	elif type == 'post':
		if body is not None:
			myResponse = requests.post(_url, json=body, verify=False)
		else:
			myResponse = requests.post(_url, verify=False)

	statusCode = myResponse.status_code
	# For successful API call, response code will be 200 (OK)
	if (myResponse.ok):
		return True
	else:
		# If response code is not ok (200), print the resulting http error code with description
		# myResponse.raise_for_status()
		print("Error[{}][{}]: {} ".format(method, statusCode, url))
		if statusCode == 500:
			return False

		return True

# ------------------------------------
# Agent
# ------------------------------------

x=('AgentUpdate', '/api/v1/agent/update/{}/{}/{}'.format(client_id,agent_ver,agent_build))
get_urls.append(x)
x=('AgentUpdaterUpdate','/api/v1/agent/updater/{}/{}'.format(client_id,agent_ver))
get_urls.append(x)
x=('AgentUpdaterUpdateWithBuild','/api/v1/agent/updater/{}/{}/{}'.format(client_id,agent_ver,agent_build))
get_urls.append(x)


x=('PluginHash','/api/v1/agent/plugin/hash/{}/{}/{}/{}'.format(client_id,plugin_name,plugin_bundleID,plugin_version))
get_urls.append(x)
# Not Tested Yet
MP_ConfigData='/api/v1/agent/config/{}'.format('token_err')
# Not Tested Yet
MP_UploadAgentPackage='/api/v1/agent/upload/{}/{}'.format('agent_id_err','token_err')

# Not Tested Yet
MP_AgentConfigInfo='/api/v1/agent/config/info/<string:cuuid>'
# Not Tested Yet
MP_AgentConfig='/api/v1/agent/config/data/<string:cuuid>'
# Not Tested Yet
MP_AgentConfigVersion='/api/v1/agent/config/version/<string:cuuid>'

# ------------------------------------
# Agent 2
# ------------------------------------

# Add Routes Resources
AgentUpdateV2='/api/v2/agent/update/{}/{}/{}'.format(client_id,agent_ver,agent_build)
get_urls.append(AgentUpdateV2)
AgentUpdaterUpdateV2='/api/v2/agent/updater/{}/{}'.format(client_id,agent_ver)
get_urls.append(AgentUpdaterUpdateV2)
AgentUpdaterUpdateWithBuildV2='/api/v2/agent/updater/{}/{}/{}'.format(client_id,agent_ver,agent_build)
get_urls.append(AgentUpdaterUpdateWithBuildV2)

AgentConfigInfoV2='/api/v2/agent/config/info/{}'.format(client_id)
get_urls.append(AgentConfigInfoV2)
AgentConfigV2='/api/v2/agent/config/data/{}'.format(client_id)
get_urls.append(AgentConfigV2)

x=('PluginHashV2','/api/v2/agent/plugin/hash/{}/{}/{}/{}'.format(plugin_name,plugin_bundleID,plugin_version,client_id))
get_urls.append(x)

# Not Tested Yet
ConfigDataV2='/api/v2/agent/config/<string:token>'
# Not Tested Yet
UploadAgentPackageV2='/api/v2/agent/upload/<string:agent_id>/<string:token>'

# ------------------------------------
# Antivirus
# ------------------------------------
x=('AVData', '/api/v1/client/av/{}'.format(client_id))
get_urls.append(x)
x=('AVDefs', '/api/v1/client/av/defs/{}/{}'.format('symantec',client_id))
get_urls.append(x)

# ------------------------------------
# Auth - Token
# ------------------------------------
_body={'authUser':authUser,'authPass':authPass}
x=('GetAuthToken','/api/v1/auth/token',_body,'post')
get_urls.append(x)

# ------------------------------------
# AutoPkg
# Not Implemented, would need to upload something
x=('AddAutoPKGPatch', '/api/v1/autopkg/<string:token>')
x=('UploadAutoPKGPatch', '/api/v1/autopkg/upload/<string:patch_id>/<string:token>')

# ------------------------------------
# Checkin
# ------------------------------------

x=('AgentBase',      '/api/v1/client/checkin/<string:cuuid>')
x=('AgentPlist',     '/api/v1/client/checkin/plist/<string:cuuid>')
x=('AgentStatus',    '/api/v1/client/checkin/info/<string:cuuid>')
x=('CheckServerKey', '/api/v1/client/server/key/<string:cuuid>')


# ------------------------------------
# Checkin 2
# ------------------------------------
cData = { "agent_build" : 2, "agent_version" : "3.3.0", "client_version" : "3.3.0.2",
"computername" : "cronus", "consoleuser" : "heizer1", "cuuid" : "BDA43E37-0296-5E33-9DA3-1CDB58998558",
"fileVault" : "FileVault is On.", "hostname" : "cronus.local", "ipaddr" : "128.15.244.127",
"macaddr" : "38:f9:d3:b5:ba:a4", "model" : "MacBookPro15,1", "needsreboot" : "false",
"ostype" : "Mac OS X","osver" : "10.14.6","serialno" : "C02YJ5HQJGH6"
}
x=('AgentBase', '/api/v1/client/checkin/{}'.format(client_id),cData,'post')
get_urls.append(x)
x=('AgentStatus', '/api/v1/client/checkin/info/{}'.format(client_id))
get_urls.append(x)
x=('CheckServerKey', '/api/v1/client/server/key/{}'.format(client_id))
get_urls.append(x)

# ------------------------------------
# Inventory, 2, 3
# Can really test inventory add
# ------------------------------------

#1
x=('AddInventoryData','/client/inventory/{}'.format(client_id))
x=('InventoryState','/api/v1/client/inventory/state/{}'.format(client_id))
get_urls.append(x)
#2
x=('AddInventoryData','/client/inventory/{}'.format(client_id))
x=('InventoryState','/api/v2/client/inventory/state/{}'.format(client_id))
get_urls.append(x)
#3
x=('AddInventoryData','/client/inventory/{}'.format(client_id))

# ------------------------------------
# Mac Profiles
# ------------------------------------
x=('ProfilesForClient', '/api/v1/client/profiles/{}'.format(client_id))
get_urls.append(x)

# ------------------------------------
# Mac Profiles 2
# ------------------------------------
x=('ProfilesForClient', '/api/v2/client/profiles/{}'.format(client_id))
get_urls.append(x)

# ------------------------------------
# Patches
# ------------------------------------

# Add Routes Resources
x=('ClientPatchStatus', '/api/v1/client/patch/status/{}'.format(client_id))
get_urls.append(x)
x=('PatchScanListFilterOS', '/api/v1/client/patch/scanlist/{}'.format(client_id))
get_urls.append(x)
x=('PatchScanListFilterOS', '/api/v1/client/patch/scanlist/<string:cuuid>/<string:state>'.format(client_id))
x=('PatchScanListFilterOS', '/api/v1/client/patch/scanlist/<string:cuuid>/<string:state>/<string:osver>'.format(client_id))
x=('PatchScanListFilterOS', '/api/v1/client/patch/scanlist/<string:cuuid>/<string:state>/<string:osver>/<string:severity>'.format(client_id))

# MP Agent 3.0
x=('PatchGroupPatches', '/api/v1/client/patch/group/{}/{}'.format('Default',client_id))
get_urls.append(x)
x=('PatchGroupPatchesRev', '/api/v1/client/patch/group/rev/{}/{}'.format('Default',client_id))
get_urls.append(x)

# MP Agent 3.1
x=('PatchGroupPatches', '/api/v1/client/patch/group/{}'.format(client_id))
get_urls.append(x)
x=('PatchGroupPatchesRev', '/api/v1/client/patch/group/rev/{}'.format(client_id))
get_urls.append(x)

# Post Client Patch Scan Data
# This will need type 1 = Apple, 2 = Third, need a dict of data for this
x=('PatchScanData', '/api/v1/client/patch/scan/<string:patch_type>/{}'.format(client_id))
x=('PatchScanData', '/api/v1/client/patch/scan/<string:patch_type>/{}'.format(client_id))

# Post Client Patch Install Data
# Need a dict of data for this
x=('PatchInstallData', '/api/v1/client/patch/install/{}/{}/{}'.format('MPTESTApple','1',client_id),None,'post')
get_urls.append(x)
x=('PatchInstallData', '/api/v1/client/patch/install/{}/{}/{}'.format('MPTESTCustom','2',client_id),None,'post')
get_urls.append(x)

# Update will be fixed in 3.1, should be done in console
x=('SavePatchGroupPatches', '/api/v1/client/update/patch/group/<string:groupID>'.format(client_id))

# ------------------------------------
# Patches 2
# ------------------------------------

x=('PatchGroupPatches','/api/v2/client/patch/group/{}'.format(client_id))
get_urls.append(x)
x=('PatchScanList','/api/v2/client/patch/scan/list/all/{}'.format(client_id))
get_urls.append(x)
x=('PatchScanList','/api/v2/client/patch/scan/list/{}/{}'.format('all',client_id))
get_urls.append(x)

# ------------------------------------
# Patches 3
# ------------------------------------
x=('PatchGroupPatches','/api/v3/client/patch/group/{}'.format(client_id))
get_urls.append(x)
x=('PatchScanList','/api/v3/client/patch/scan/list/all/{}'.format(client_id))
get_urls.append(x)
x=('PatchScanList','/api/v3/client/patch/scan/list/{}/{}'.format('all',client_id))
get_urls.append(x)

# ------------------------------------
# Patches 4
# ------------------------------------
x=('PatchGroupPatches','/api/v4/client/patch/group/{}'.format(client_id))
get_urls.append(x)

# ------------------------------------
# Provisioning
# ------------------------------------
# Get
x=('PatchGroups',     '/api/v1/provisioning/groups/patch/{}'.format(client_id))
get_urls.append(x)
# Get
x=('ClientGroups',    '/api/v1/provisioning/groups/client/{}'.format(client_id))
get_urls.append(x)
# Post, need a sample string body to work
body={'action':'start','os':'10.16','label':'Test','migrationID':'9999999'}
x=('OSMigration',    '/api/v1/provisioning/migration/{}'.format(client_id),body,'post')
get_urls.append(x)

# ------------------------------------
# Register
# ------------------------------------

# Post
x=('Registration',         '/client/register/<string:cuuid>')
x=('Registration',         '/client/register/<string:cuuid>/<string:regKey>')
# Get
x=('RegistrationStatus',   '/api/v1/client/register/status/{}'.format(client_id))
get_urls.append(x)
x=('RegistrationStatus',   '/client/register/status/<string:cuuid>/<string:keyHash>')

# ------------------------------------
# Register 2
# ------------------------------------

# Post
x=('Registration', '/api/v2/client/register/{}'.format(client_id))
x=('Registration', '/api/v2/client/register/<string:client_id>/<string:regKey>')
# Get
x=('RegistrationStatus', '/api/v2/client/register/status/{}'.format(client_id))
get_urls.append(x)
x=('RegistrationStatus', '/api/v2/client/register/status/<string:client_id>/<string:keyHash>')


# ------------------------------------
# Servers
# ------------------------------------

x=('SUSCatalogs','/api/v1/sus/catalogs/{}/{}'.format('13',client_id))
get_urls.append(x)
x=('SUSCatalogs','/api/v1/sus/catalogs/{}/{}/{}'.format('10','13',client_id))
get_urls.append(x)

x=('SUSListVersion','/api/v1/sus/list/version/{}/{}'.format(client_id,suSListVersionID))
get_urls.append(x)
x=('SUServerList','/api/v1/sus/catalogs/list/{}/{}'.format('13',client_id))
get_urls.append(x)
x=('SUServerList','/api/v1/sus/catalogs/list/{}/{}/{}'.format('10','13',client_id))
get_urls.append(x)

x=('ServerList','/api/v1/server/list/{}'.format(client_id))
get_urls.append(x)
x=('ServerList','/api/v1/server/list/{}/{}'.format(serverListVersionID,client_id))
get_urls.append(x)

x=('ServerListVersion', '/api/v1/server/list/version/{}'.format(client_id))
get_urls.append(x)
x=('ServerListVersion', '/api/v1/server/list/version/{}/{}'.format(serverListVersionID,client_id))
get_urls.append(x)

# ------------------------------------
# Servers 2
# ------------------------------------

x=('SUServersVersion', '/api/v2/suservers/version/{}'.format(client_id))
get_urls.append(x)
x=('SUServers', '/api/v2/suservers/{}'.format(client_id))
get_urls.append(x)

x=('ServersVersion', '/api/v2/servers/version/{}'.format(client_id))
get_urls.append(x)
x=('Servers', '/api/v2/servers/{}'.format(client_id))
get_urls.append(x)

x=('ServerLog', '/api/v2/server/log/<string:reqid>/<string:type>/<string:serverkey>')

# ------------------------------------
# Software
# ------------------------------------

x=('SoftwareTasksForGroup', '/api/v1/sw/tasks/{}/{}'.format(client_id,'Default'))
get_urls.append(x)
x=('SoftwareTasksForGroup', '/api/v1/sw/tasks/{}/{}/{}'.format(client_id,'Default','10.13'))
get_urls.append(x)
x=('SoftwareTaskForTaskID', '/api/v1/sw/task/{}/{}'.format(client_id,swTaskID))
get_urls.append(x)

x=('SoftwareDistributionGroups', '/api/v1/sw/groups/{}'.format(client_id))
get_urls.append(x)
x=('SoftwareDistributionGroups', '/api/v1/sw/groups/<string:cuuid>/<string:state>')

# No body data yet
x=('SoftwareInstallResult', '/api/v1/sw/installed/{}'.format(client_id),None,'post')

# Old API, depricated no longer in use
x=('SaveSoftwareTasksForGroup', '/api/v1/sw/update/tasks/<string:cuuid>/<string:groupID>')

# ------------------------------------
# Software v2
# ------------------------------------

x=('SoftwareTasksForGroup', '/api/v2/sw/tasks/{}/{}'.format(client_id,'Default'))
get_urls.append(x)
x=('SoftwareTasksForGroup', '/api/v2/sw/tasks/{}/{}/{}'.format(client_id,'Default','10.13'))
get_urls.append(x)
x=('SoftwareTaskForTaskID', '/api/v2/sw/task/{}/{}'.format(client_id,swTaskID))
get_urls.append(x)
x=('SoftwareGroups', '/api/v2/sw/groups/{}'.format(client_id))
get_urls.append(x)
x=('SoftwareGroups', '/api/v2/sw/groups/<string:cuuid>/<string:state>')
x=('SoftwareForClientGroup', '/api/v2/sw/required/{}'.format(client_id))
get_urls.append(x)

# ------------------------------------
# Software v3
# ------------------------------------
x=('SoftwareRestrictions','/api/v3/sw/restrictions/{}'.format(client_id))
get_urls.append(x)

# ------------------------------------
# MAIN
# ------------------------------------

#testDB()
#exit(0)

for u in get_urls:
	res = True
	if len(u) == 2:
		res = makeRESTCall(u[1],u[0])
	elif len(u) == 3:
		res = makeRESTCall(u[1], u[0], body=u[2])
	elif len(u) == 4:
		res = makeRESTCall(u[1], u[0], body=u[2],type=u[3])

	if res == False:
		break