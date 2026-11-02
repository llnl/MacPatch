"""
Software Group Filtering

Provides filter evaluation for software group targeting based on client attributes.
Follows the same section-based evaluation pattern as agent_updates.py.
"""

from mpapi.extensions import db
from mpapi.model import (MpSoftwareGroupFilters, MpClient, MpClientPlist,
                         MpClientGroupMembers, MpClientGroups, MPIDirectoryServices,
                         MPISPHardwareOverview)
from mpapi.mplogger import log_Info, log_Error, log_Debug


def build_client_info(client_id):
	"""
	Build a dictionary of client attributes for filter evaluation.

	Args:
		client_id: Client UUID

	Returns:
		Dictionary with client attributes from multiple tables
	"""
	info = {'cuuid': client_id}

	# Get basic client attributes from MpClient table
	client = MpClient.query.filter(MpClient.cuuid == client_id).first()
	if client is not None:
		info['osver'] = client.osver or ''
		info['ostype'] = client.ostype or ''
		info['hostname'] = client.hostname or ''
		info['computername'] = client.computername or ''
		info['serialno'] = client.serialno or ''
		info['ipaddr'] = client.ipaddr or ''
		info['macaddr'] = client.macaddr or ''
		info['consoleuser'] = client.consoleuser or ''
		info['agent_version'] = client.agent_version or ''
		info['agent_build'] = str(client.agent_build) if client.agent_build else ''
		info['client_version'] = client.client_version or ''

	# Get configuration attributes from MpClientPlist table
	plist = MpClientPlist.query.filter(MpClientPlist.cuuid == client_id).first()
	if plist is not None:
		info['domain'] = plist.Domain or ''
		info['patchgroup'] = plist.PatchGroup or ''
		info['swdistgroup'] = plist.SWDistGroup or ''

	# Get client group membership
	group_member = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_id).first()
	if group_member is not None:
		group = MpClientGroups.query.filter(MpClientGroups.group_id == group_member.group_id).first()
		if group is not None:
			info['client_group'] = group.group_name or ''

	# Get Active Directory information (optional, may not exist for all clients)
	try:
		ad_info = MPIDirectoryServices.query.filter(MPIDirectoryServices.cuuid == client_id).first()
		if ad_info is not None:
			info['addomain'] = ad_info.mpa_ADDomain or ''
			info['addn'] = ad_info.mpa_distinguishedName or ''
	except Exception as e:
		log_Debug('[build_client_info] No AD info for client %s: %s' % (client_id, str(e)))

	# Get hardware information (optional, may not exist for all clients)
	try:
		hw_info = MPISPHardwareOverview.query.filter(MPISPHardwareOverview.cuuid == client_id).first()
		if hw_info is not None:
			info['model'] = hw_info.mpa_Model_Name or ''
			info['model_identifier'] = hw_info.mpa_Model_Identifier or ''
			info['processor'] = hw_info.mpa_Processor_Name or ''
	except Exception as e:
		log_Debug('[build_client_info] No hardware info for client %s: %s' % (client_id, str(e)))

	return info


def _filter_matches(client, attr, oper, value):
	"""
	Test if a single filter rule matches the client attributes.

	Args:
		client: Dictionary of client attributes
		attr: Attribute name to test
		oper: Operator ('eq' or 'neq')
		value: Value to compare against

	Returns:
		True if the filter matches, False otherwise
	"""
	# Special case: universal match
	if attr == 'all' and oper.lower() == 'eq' and value.lower() == 'all':
		return True

	# Check if attribute exists in client info
	if attr not in client:
		return False

	# Case-insensitive comparison
	client_value = str(client[attr]).lower()
	filter_value = str(value).lower()

	# Perform comparison based on operator
	same = client_value == filter_value

	# Handle both 'neq' and 'ne' as not-equals
	if oper.lower() in ['neq', 'ne']:
		return not same
	else:
		return same


def evaluate_filters(client, filters):
	"""
	Evaluate filters using section-based logic.

	Filters are grouped into sections:
	- Filters within a section are AND'ed (all must match)
	- Sections are OR'ed (any section can match)
	- 'or' condition starts a new section
	- 'none' condition stops evaluation

	Args:
		client: Dictionary of client attributes
		filters: List of filter dictionaries with keys:
			- attribute: attribute name
			- attribute_oper: operator ('eq', 'neq')
			- attribute_filter: value to match
			- attribute_condition: condition ('and', 'or', 'none')

	Returns:
		True if the client matches (ALL filters in ANY section pass), False otherwise
	"""
	sections = {}
	section = count = passed = 0

	for f in filters:
		condition = f['attribute_condition'].lower() if f['attribute_condition'] else 'and'

		# Start new section on 'or' condition
		if condition == 'or':
			section += 1
			count = passed = 0

		# Increment filter count and test if filter matches
		count += 1
		if _filter_matches(client, f['attribute'].lower(), f['attribute_oper'], f['attribute_filter']):
			passed += 1

		# Store section results
		sections[section] = (count, passed)

		# Stop evaluation on 'none' condition
		if condition == 'none':
			break

	# Client qualifies if ALL filters in ANY ONE section match
	return any(count == passed for count, passed in sections.values())


def should_apply_group_to_client(client_id, group_id):
	"""
	Determine if a software group should be applied to a client based on filters.

	Args:
		client_id: Client UUID
		group_id: Software group ID (gid)

	Returns:
		True if the group should be applied (client matches filters or no filters exist),
		False if the client is filtered out
	"""
	try:
		# Query filters for this group, ordered by rid
		filters = MpSoftwareGroupFilters.query.filter(
			MpSoftwareGroupFilters.gid == group_id
		).order_by(MpSoftwareGroupFilters.rid).all()

		# No filters = no restrictions, apply to all clients
		if not filters:
			log_Debug('[should_apply_group_to_client] No filters for group %s, applying to all clients' % group_id)
			return True

		# Build client info dictionary
		client = build_client_info(client_id)

		# Convert filter objects to dictionaries
		filter_dicts = [f.asDict for f in filters]

		# Evaluate filters
		result = evaluate_filters(client, filter_dicts)

		if result:
			log_Info('[should_apply_group_to_client] Client %s matches filters for group %s' % (client_id, group_id))
		else:
			log_Info('[should_apply_group_to_client] Client %s filtered out from group %s' % (client_id, group_id))

		return result

	except Exception as e:
		log_Error('[should_apply_group_to_client] Error evaluating filters for client %s, group %s: %s' % (client_id, group_id, str(e)))
		# On error, fail safe and allow the group (don't filter out due to technical issues)
		return True
