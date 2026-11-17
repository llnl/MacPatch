'''
	Software consistency checks, used by the flask CLI (check-software-tasks)
'''
from datetime import datetime

from mpconsole.app import db
from mpconsole.model import MpSoftwareTask, MpSoftware, MpSoftwareGroupTasks, MpSoftwareGroup, MpClientGroupSoftware, MpClientGroups

def findBrokenSoftwareTasks():
	"""Returns (number of tasks checked, list of tasks whose primary software package is missing).

	Each broken task has a 'groups' list, the software groups it is currently assigned to (selected)."""
	existing = set(row[0] for row in db.session.query(MpSoftware.suuid).all())

	tasks = MpSoftwareTask.query.order_by(MpSoftwareTask.name.asc()).all()
	broken = []
	for t in tasks:
		if not t.primary_suuid:
			problem = 'No primary software package is set'
		elif t.primary_suuid not in existing:
			problem = 'Package {} no longer exists'.format(t.primary_suuid)
		else:
			continue

		broken.append({'tuuid': t.tuuid, 'name': t.name or '', 'active': t.active, 'problem': problem, 'groups': [], 'clientGroups': []})

	_addAssignedGroups(broken)
	_addAssignedClientGroups(broken)
	return len(tasks), broken

def _addAssignedGroups(broken):
	"""Fill in the 'groups' list on each broken task, using one query for all of them"""
	if not broken:
		return

	by_task = dict((b['tuuid'], b) for b in broken)
	rows = db.session.query(MpSoftwareGroupTasks.sw_task_id, MpSoftwareGroupTasks.sw_group_id, MpSoftwareGroup.gName) \
		.outerjoin(MpSoftwareGroup, MpSoftwareGroup.gid == MpSoftwareGroupTasks.sw_group_id) \
		.filter(MpSoftwareGroupTasks.selected == 1, MpSoftwareGroupTasks.sw_task_id.in_(list(by_task))) \
		.all()

	for task_id, group_id, group_name in rows:
		by_task[task_id]['groups'].append({'gid': group_id, 'name': group_name})

	for b in broken:
		b['groups'].sort(key=lambda g: (g['name'] or g['gid']).lower())

def _addAssignedClientGroups(broken):
	"""Fill in the 'clientGroups' list on each broken task, using one query for all of them"""
	if not broken:
		return

	by_task = dict((b['tuuid'], b) for b in broken)
	rows = db.session.query(MpClientGroupSoftware.tuuid, MpClientGroupSoftware.group_id, MpClientGroups.group_name) \
		.outerjoin(MpClientGroups, MpClientGroups.group_id == MpClientGroupSoftware.group_id) \
		.filter(MpClientGroupSoftware.tuuid.in_(list(by_task))) \
		.all()

	for task_id, group_id, group_name in rows:
		by_task[task_id]['clientGroups'].append({'gid': group_id, 'name': group_name})

	for b in broken:
		b['clientGroups'].sort(key=lambda g: (g['name'] or g['gid']).lower())

def deactivateSoftwareTasks(task_ids):
	"""Set the given software tasks to inactive, returns how many were changed"""
	if not task_ids:
		return 0

	count = 0
	for t in MpSoftwareTask.query.filter(MpSoftwareTask.tuuid.in_(task_ids)).all():
		t.active = 0
		t.mdate = datetime.now()
		count += 1

	db.session.commit()
	return count

def deleteSoftwareTasks(task_ids, republish=None, log=None):
	"""Delete the given software tasks, the same way the console does.

	Each task is removed from its software groups and client groups first, then deleted.
	republish(group_id) is called once for every software group that lost a task, so the
	group's published task data no longer lists it.  log(message) is called for each step.

	Returns {'deleted': n, 'softwareGroupRows': n, 'clientGroupRows': n, 'groups': [group ids]}"""
	log = log or (lambda m: None)
	result = {'deleted': 0, 'softwareGroupRows': 0, 'clientGroupRows': 0, 'groups': []}
	touched = []

	for t in MpSoftwareTask.query.filter(MpSoftwareTask.tuuid.in_(list(task_ids))).all():
		for row in MpSoftwareGroupTasks.query.filter(MpSoftwareGroupTasks.sw_task_id == t.tuuid).all():
			log('Removing task {} from software group {}'.format(t.tuuid, row.sw_group_id))
			if row.sw_group_id not in touched:
				touched.append(row.sw_group_id)
			db.session.delete(row)
			result['softwareGroupRows'] += 1

		for row in MpClientGroupSoftware.query.filter(MpClientGroupSoftware.tuuid == t.tuuid).all():
			log('Removing task {} from client group {}'.format(t.tuuid, row.group_id))
			db.session.delete(row)
			result['clientGroupRows'] += 1

		log('Deleting software task {} ({})'.format(t.name, t.tuuid))
		db.session.delete(t)
		result['deleted'] += 1

	db.session.commit()

	if republish:
		for gid in touched:
			republish(gid)

	result['groups'] = touched
	return result

def findPackageDependents(package_ids):
	"""Which software tasks use the given packages, and which groups those tasks are in.

	Returns a list with one entry per package that has at least one task:
	  {'suuid', 'name', 'tasks': [{'tuuid', 'name', 'active', 'groups': [...], 'clientGroups': [...]}]}
	groups / clientGroups hold {'gid', 'name'}.  Read only, nothing is changed."""
	package_ids = list(package_ids)
	if not package_ids:
		return []

	names = dict((suuid, name) for suuid, name in
		db.session.query(MpSoftware.suuid, MpSoftware.sName).filter(MpSoftware.suuid.in_(package_ids)).all())

	tasks = MpSoftwareTask.query.filter(MpSoftwareTask.primary_suuid.in_(package_ids)).order_by(MpSoftwareTask.name.asc()).all()
	items = [{'tuuid': t.tuuid, 'name': t.name or '', 'active': t.active, 'groups': [], 'clientGroups': [], '_suuid': t.primary_suuid}
		for t in tasks]
	_addAssignedGroups(items)
	_addAssignedClientGroups(items)

	by_package = {}
	for item in items:
		suuid = item.pop('_suuid')
		by_package.setdefault(suuid, []).append(item)

	return [{'suuid': suuid, 'name': names.get(suuid, suuid), 'tasks': by_package[suuid]}
		for suuid in package_ids if suuid in by_package]
