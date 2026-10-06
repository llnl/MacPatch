from mpapi.extensions import db
from mpapi.model import MpClientGroupMembers, MpClientGroups, MPGroupConfig
from mpapi.mplogger import log_Info


def groupIDForClient(client_id, default_group=False):
	"""Client group ID for a client, 0 if none. default_group falls back to the 'Default' group."""
	member = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_id).first()
	if member is not None:
		return member.group_id

	if default_group:
		group = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
		if group is not None:
			return group.group_id
	return 0


def addClientToDefaultGroup(client_id):
	"""Make the client a member of the 'Default' group. Returns the group ID (0 if there's no Default group)."""
	group = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
	if group is None:
		return 0

	log_Info('Adding client (%s) to default client group.' % client_id)
	db.session.add(MpClientGroupMembers(cuuid=client_id, group_id=group.group_id))
	db.session.commit()
	return group.group_id


def groupConfig(group_id):
	"""Config revision row for a client group; created with default revisions if missing."""
	config = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
	if config is None:
		config = MPGroupConfig(group_id=group_id, rev_tasks=1, tasks_version=1)
		db.session.add(config)
		db.session.commit()
	return config
