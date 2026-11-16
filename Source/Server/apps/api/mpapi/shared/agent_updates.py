from packaging import version
from sqlalchemy import text

from mpapi.extensions import db
from mpapi.model import MpClientAgent, MpClient, MpClientPlist, MpClientAgentsFilter
from mpapi.mplogger import log_Info, log_Error, log_Debug

# Agent update kinds: the stored procedure argument for each
UPDATE_APP = 'app'
UPDATE_UPDATER = 'update'


def latest_update_for(kind):
	"""Agent update record (dict) with the highest RID for kind, or None."""
	with db.engine.connect() as con:
		row = con.execute(text("CALL AgentUpdateRID('%s')" % kind)).mappings().first()
	if row is None:
		return None

	record = MpClientAgent.query.filter(MpClientAgent.rid == row['rid']).first()
	if record is None:
		log_Error('[agent_updates] Error, we have a RID but no data.')
		return None
	return record.asDict


def client_info(cuuid):
	"""Client attributes the update filters are evaluated against."""
	info = {'cuuid': cuuid, 'osver': '10.9.0', 'ipaddr': '127.0.0.1', 'hostname': 'localhost',
			'domain': 'Default', 'patchgroup': 'Default'}

	client = (MpClient.query.with_entities(MpClient.osver, MpClient.ipaddr, MpClient.hostname)
			  .filter(MpClient.cuuid == cuuid).first())
	if client is not None:
		info['osver'], info['ipaddr'], info['hostname'] = client

	plist = (MpClientPlist.query.with_entities(MpClientPlist.Domain, MpClientPlist.PatchGroup)
			 .filter(MpClientPlist.cuuid == cuuid).first())
	if plist is not None:
		info['domain'], info['patchgroup'] = plist

	return info


def _filter_matches(client, attr, oper, value):
	if attr == 'all' and oper.lower() == 'eq' and value.lower() == 'all':
		return True
	if attr not in client:
		return False
	same = client[attr].lower() == value.lower()
	return same if oper.lower() == 'eq' else not same


def evaluate_filters(client, filters):
	"""
	Filters are grouped into sections; an 'or' condition starts a new section and a 'none'
	condition ends evaluation. The client qualifies if every filter in any one section matches.
	"""
	sections = {}
	section = count = passed = 0

	for f in filters:
		condition = f['attribute_condition'].lower()
		if condition == 'or':
			section += 1
			count = passed = 0

		count += 1
		if _filter_matches(client, f['attribute'].lower(), f['attribute_oper'], f['attribute_filter']):
			passed += 1
		sections[section] = (count, passed)

		if condition == 'none':
			break

	return any(count == passed for count, passed in sections.values())


def check_update(cuuid, agent_version, agent_build, kind=UPDATE_APP):
	"""
	Does the client need an agent update?
	  None  - no update (or client / update data unknown)
	  {}    - an update exists but the client is filtered out
	  dict  - update data with updateAvailable True
	"""
	update = latest_update_for(kind)
	if update is None:
		return None

	client = client_info(cuuid)

	if update['osver'] != '*':
		if version.parse(update['osver'].replace('+', '')) > version.parse(client['osver']):
			log_Error('[check_update] Client OS version is lower than the minimum OS supported.')
			return None

	if update['version'] == agent_version:
		if int(agent_build) == 0 or int(update['build']) <= int(agent_build):
			log_Info('[check_update] Client is running the latest version and build.')
			return None
	elif version.parse(update['version']) < version.parse(agent_version):
		log_Info('[check_update] Client is running a newer version.')
		return None

	filters = [row.asDict for row in MpClientAgentsFilter.query.all()]
	if not filters or not evaluate_filters(client, filters):
		return {}

	data = {'puuid': update['puuid'], 'type': update['type'], 'pkg_hash': update['pkg_hash'],
			'pkg_name': update['pkg_name'], 'pkg_url': update['pkg_url'], 'updateAvailable': True}
	log_Debug('[check_update] Client (%s) update data: %s' % (cuuid, data))
	return data
