from mpapi.mputil import MPResource
from mpapi.model import (MpClient, MpClientGroups, MpClientTasks,
						 MpAsusCatalogList, MpServerList, MPPluginHash)
from mpapi.mplogger import log_Info, log_Error, log_Debug
from mpapi.shared.rest import client_endpoint, ok, fail, signed
from mpapi.shared.groups import groupIDForClient, groupConfig
from mpapi.shared.servers import serverListForID, suServerListForID
from mpapi.shared.agent_updates import check_update, UPDATE_APP, UPDATE_UPDATER

from . import agent_5_api

AGENT_CONFIG_SCHEMA = 330


class AgentConfigInfo(MPResource):
	"""Revisions of the settings a client can fetch with AgentConfig."""

	@client_endpoint()
	def get(self, client_id):
		group_id = groupIDForClient(client_id)
		if group_id == 0:
			return fail(404, 'Settings version or client group membership not found.',
						result={'type': 'AgentConfigInfo', 'data': {}})

		config = groupConfig(group_id)
		catalog_list = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == '1').first()
		server_list = MpServerList.query.filter(MpServerList.listid == '1').first()

		info = {'group_id': group_id,
				'settings': {'agent': config.rev_settings, 'tasks': config.rev_tasks,
							 'suservers': catalog_list.version if catalog_list is not None else 0,
							 'servers': server_list.version if server_list is not None else 0}}
		return signed('AgentConfigInfo', info)


class AgentConfig(MPResource):
	"""Full agent configuration for a client's group: settings, servers, SU catalogs and tasks."""

	@client_endpoint()
	def get(self, client_id):
		group_id = groupIDForClient(client_id, default_group=True)
		if group_id == 0:
			return fail(404, 'Settings version or client group membership not found.',
						result={'type': 'AgentConfig', 'data': {}})

		config = groupConfig(group_id)
		client = MpClient.query.filter(MpClient.cuuid == client_id).first()
		group = MpClientGroups.query.filter(MpClientGroups.group_id == group_id).first()

		agent_data = {}
		if group is not None:
			agent_data = {'client_group': group.group_name, 'client_group_id': group_id}

		servers = serverListForID(1)
		suservers = {'version': 0, 'data': []}
		if client is not None:
			suservers = suServerListForID(1, client.osver)

		tasks = [t.asDict for t in MpClientTasks.query.filter(MpClientTasks.group_id == group_id).all()]

		agentConfig = {
			'schema': AGENT_CONFIG_SCHEMA,
			'revs': {'agent': config.rev_settings, 'servers': servers['version'],
					 'suservers': suservers['version'], 'tasks': config.rev_tasks, 'swrestrictions': 0},
			'settings': {
				'agent': {'rev': config.rev_settings, 'data': agent_data},
				'servers': {'rev': servers['version'], 'data': servers['data']},
				'suservers': {'rev': suservers['version'], 'data': suservers['data']},
				'tasks': {'rev': config.rev_tasks, 'data': tasks},
				'software': {'data': []}}}

		return signed('AgentConfig', agentConfig)


class AgentUpdate(MPResource):
	"""Is a newer MPAgent available for this client?"""

	@client_endpoint()
	def get(self, client_id, agentver='0', agentbuild='0'):
		return _update_response(client_id, agentver, agentbuild, UPDATE_APP, 'AgentUpdate', sign=False)


class AgentUpdaterUpdate(MPResource):
	"""Is a newer MPUpdater available for this client?"""

	@client_endpoint()
	def get(self, client_id, agentver='0', agentbuild='0'):
		return _update_response(client_id, agentver, agentbuild, UPDATE_UPDATER, 'AgentUpdaterUpdate', sign=True)


def _update_response(client_id, agentver, agentbuild, kind, rtype, sign):
	agentver = agentver.removeprefix('MPAgent Version: ')
	log_Info('[%s] Checking for update for client (%s) version: %s' % (rtype, client_id, agentver))

	update = check_update(client_id, agentver, agentbuild, kind)
	if update is None:
		return ok({'type': rtype, 'data': {'updateAvailable': False}}, code=202)

	if sign:
		return signed(rtype, update)
	return ok({'type': rtype, 'data': update})


class PluginHash(MPResource):
	"""Expected hash of an agent plugin, for the agent to verify before loading it."""

	@client_endpoint()
	def get(self, client_id, plugin_name, plugin_bundle, plugin_version):
		plugin = MPPluginHash.query.filter(MPPluginHash.pluginName == plugin_name,
										   MPPluginHash.pluginBundleID == plugin_bundle,
										   MPPluginHash.pluginVersion == plugin_version).first()
		if plugin is None:
			log_Error('[PluginHash][GET] Plugin (%s) hash could not be found.' % plugin_name)
			return fail(404, 'Plugin hash could not be found.', result={'data': ''})

		log_Debug('[PluginHash][GET] %s for client (%s)' % (plugin.asDict, client_id))
		return ok({'data': plugin.hash})


# Add Routes Resources
agent_5_api.add_resource(AgentConfigInfo,    '/agent/config/info/<string:client_id>')
agent_5_api.add_resource(AgentConfig,        '/agent/config/data/<string:client_id>')
agent_5_api.add_resource(AgentUpdate,        '/agent/update/<string:client_id>/<string:agentver>/<string:agentbuild>')
agent_5_api.add_resource(AgentUpdaterUpdate, '/agent/updater/<string:client_id>/<string:agentver>', endpoint='updaterNoBuild')
agent_5_api.add_resource(AgentUpdaterUpdate, '/agent/updater/<string:client_id>/<string:agentver>/<string:agentbuild>', endpoint='updaterBuild')
agent_5_api.add_resource(PluginHash,         '/agent/plugin/hash/<string:plugin_name>/<string:plugin_bundle>/<string:plugin_version>/<string:client_id>')
