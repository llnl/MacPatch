from datetime import datetime

from flask import request
from sqlalchemy.exc import IntegrityError

from mpapi.app import db
from mpapi.mputil import MPResource, b64EncodeAsString
from mpapi.model import (MpClientGroupMembers, MpClientGroupSoftwareRestrictions, MpProvisionTask, MpSoftware,
						 MpSoftwareCriteria, MpSoftwareGroup, MpSoftwareGroupTasks, MpSoftwareInstall,
						 MpSoftwareRestrictions, MpSoftwareTask, MPGroupConfig)
from mpapi.mplogger import log_Info, log_Error, log_Debug
from mpapi.shared.rest import client_endpoint, ok, fail, signed

from . import software_5_api

# Used when a software task has no OS/arch criteria row of that type
DEFAULT_CRITERIA = {'os_type': 'Mac OS X, Mac OS X Server', 'os_vers': '10.7.*', 'arch_type': 'PPC,X86'}
CRITERIA_KEYS = {'OSType': 'os_type', 'OSVersion': 'os_vers', 'OSArch': 'arch_type'}


def dateString(value):
	return value.strftime('%Y-%m-%d %H:%M:%S') if value is not None else None


def softwareData(sw):
	"""A software package as sent to the client (database values as is)."""
	return {'name': sw.sName, 'vendor': sw.sVendor, 'vendorUrl': sw.sVendorURL, 'version': sw.sVersion,
			'description': sw.sDescription, 'reboot': sw.sReboot, 'sw_type': sw.sw_type, 'sw_url': sw.sw_url,
			'sw_hash': sw.sw_hash, 'sw_size': sw.sw_size,
			'sw_pre_install': b64EncodeAsString(sw.sw_pre_install_script, ''),
			'sw_post_install': b64EncodeAsString(sw.sw_post_install_script, ''),
			'sw_uninstall': b64EncodeAsString(sw.sw_uninstall_script, ''),
			'sw_env_var': sw.sw_env_var, 'auto_patch': sw.auto_patch, 'patch_bundle_id': sw.patch_bundle_id,
			'state': sw.sState, 'sid': sw.suuid, 'sw_img_path': sw.sw_img_path}


def softwareDataForList(sw):
	"""A software package as sent in a task list: all values are strings, adds S3 / app path info."""
	data = softwareData(sw)
	for key in ('reboot', 'sw_type', 'sw_size', 'auto_patch', 'state', 'sid', 'sw_img_path'):
		data[key] = str(data[key])
	data.update({'sw_useS3': str(sw.sw_useS3), 'sw_app_path': str(sw.sw_app_path or 'None')})
	return data


def criteriaData(rows):
	"""OS / arch criteria rows as {'os_type', 'os_vers', 'arch_type'} (defaults for missing types)."""
	data = dict(DEFAULT_CRITERIA)
	for row in rows:
		if row.type in CRITERIA_KEYS:
			data[CRITERIA_KEYS[row.type]] = row.type_data
	return data


def taskData(task):
	"""A software task (MpSoftwareTask or MpProvisionTask) with its software and criteria."""
	software = MpSoftware.query.filter(MpSoftware.suuid == task.primary_suuid).first()
	criteria = (MpSoftwareCriteria.query.filter(MpSoftwareCriteria.suuid == task.primary_suuid)
				.order_by(MpSoftwareCriteria.type_order.asc()).all())

	return {'name': task.name, 'id': task.tuuid,
			'sw_task_type': getattr(task, 'sw_task_type', 'o'),
			'sw_task_privs': getattr(task, 'sw_task_privs', 'Global'),
			'sw_start_datetime': dateString(task.sw_start_datetime),
			'sw_end_datetime': dateString(task.sw_end_datetime),
			'active': task.active, 'suuid': task.primary_suuid,
			'Software': softwareData(software) if software is not None else {},
			'SoftwareCriteria': criteriaData(criteria),
			'SoftwareRequisistsPre': {}, 'SoftwareRequisistsPost': {}}


def osMatches(allowed_os_versions, os_filter):
	"""allowed_os_versions is a comma separated list ('*', '14.*', '15.1'), os_filter e.g. '14.5'."""
	if os_filter == '*':
		return True
	os_filter = os_filter.replace('*', '')
	for allowed in allowed_os_versions.split(','):
		if allowed == '*' or allowed.replace('.*', '') in os_filter:
			return True
	return False


def tasksForGroup(group_id, os_filter='*'):
	"""The selected software tasks of a software group that apply to the OS version."""
	selected = [g.sw_task_id for g in MpSoftwareGroupTasks.query.filter(
		MpSoftwareGroupTasks.sw_group_id == group_id, MpSoftwareGroupTasks.selected == 1).all()]

	tasks = {t.tuuid: t for t in MpSoftwareTask.query.filter(MpSoftwareTask.active == 1).all()}
	software = {s.suuid: s for s in MpSoftware.query.all()}
	criteria = {}
	for row in MpSoftwareCriteria.query.all():
		criteria.setdefault(row.suuid, []).append(row)

	result = []
	for task_id in selected:
		task = tasks.get(task_id)
		if task is None:
			continue

		# A task without OS version criteria isn't offered
		task_criteria = {CRITERIA_KEYS[r.type]: r.type_data for r in criteria.get(task.primary_suuid, [])
						 if r.type in CRITERIA_KEYS}
		if 'os_vers' not in task_criteria or not osMatches(task_criteria['os_vers'], os_filter):
			continue

		sw = software.get(task.primary_suuid)
		result.append({'id': task.tuuid, 'name': task.name, 'sw_task_type': task.sw_task_type,
					   'sw_task_privs': task.sw_task_privs,
					   'sw_start_datetime': dateString(task.sw_start_datetime),
					   'sw_end_datetime': dateString(task.sw_end_datetime), 'active': task.active,
					   'Software': softwareDataForList(sw) if sw is not None else {},
					   'SoftwareCriteria': task_criteria,
					   'SoftwareRequisistsPre': {}, 'SoftwareRequisistsPost': {}})
	return result


class SoftwareTasksForGroup(MPResource):
	"""Software tasks of a software group, optionally filtered by OS version."""

	@client_endpoint(allow_iload=True)
	def get(self, client_id, groupName, osver='*'):
		group = MpSoftwareGroup.query.filter(MpSoftwareGroup.gName == groupName).first()
		if group is None or group.gid is None:
			log_Error('[SoftwareTasksForGroup][GET][%s] Group (%s) Not Found' % (client_id, groupName))
			return fail(404, 'Group Not Found', result={'type': 'SoftwareTask', 'data': {}})

		return ok({'type': 'SoftwareTask', 'data': tasksForGroup(group.gid, osver)}, code=202)


class SoftwareTaskForTaskID(MPResource):
	"""One software task with its software and criteria."""

	@client_endpoint()
	def get(self, client_id, taskID):
		task = MpSoftwareTask.query.filter(MpSoftwareTask.tuuid == taskID).first()
		if task is None:
			return fail(404, 'Task Not Found', result={'type': 'SoftwareTask', 'data': {}})
		return signed('SoftwareTask', taskData(task))


class SoftwareProvisionDataForTaskID(MPResource):
	"""One provisioning task with its software and criteria."""

	@client_endpoint()
	def get(self, taskID, client_id):
		task = MpProvisionTask.query.filter(MpProvisionTask.tuuid == taskID).first()
		if task is None:
			return fail(404, 'Task Not Found', result={'type': 'ProvisionTask', 'data': {}})
		return signed('ProvisionTask', taskData(task))


class SoftwareGroups(MPResource):
	"""Software distribution groups; state 1 or 2 = that state, 3 = any enabled state."""

	@client_endpoint(allow_iload=True)
	def get(self, client_id, state='1'):
		if state in ('1', '2'):
			groups = MpSoftwareGroup.query.filter(MpSoftwareGroup.state == state).all()
		elif state == '3':
			groups = MpSoftwareGroup.query.filter(MpSoftwareGroup.state >= 1).all()
		else:
			log_Error('[SoftwareGroups][GET][%s] Not valid state selected (%s)' % (client_id, state))
			return fail(400, 'Not valid state selected.')

		if not groups:
			log_Error('[SoftwareGroups][GET][%s] No groups found.' % client_id)
			return fail(404, 'No groups found.', errorno=0)

		return signed('SoftwareGroup', [{'Name': g.gName, 'Desc': g.gDescription} for g in groups])


def restrictionRule(restriction):
	return {'displayName': restriction.displayName, 'processName': restriction.processName,
			'message': restriction.message, 'killProc': restriction.killProc, 'sendEmail': restriction.sendEmail}


class SoftwareRestrictions(MPResource):
	"""Apps the client must not run: global rules plus its client group's rules (group wins)."""

	@client_endpoint(allow_iload=True)
	def get(self, client_id):
		member = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_id).first()
		group_id = member.group_id if member is not None else 0

		# Group rules: the group's enabled rules that point at a non-global restriction
		group_app_ids = [r.appID for r in MpClientGroupSoftwareRestrictions.query.filter(
			MpClientGroupSoftwareRestrictions.group_id == group_id,
			MpClientGroupSoftwareRestrictions.enabled == 1).all()]
		restrictions = {}
		if group_app_ids:
			restrictions = {r.appID: r for r in MpSoftwareRestrictions.query.filter(
				MpSoftwareRestrictions.enabled == 1, MpSoftwareRestrictions.isglobal == 0,
				MpSoftwareRestrictions.appID.in_(group_app_ids)).all()}
		group_rules = [(app_id, restrictionRule(restrictions[app_id])) for app_id in group_app_ids
					   if app_id in restrictions]

		# Global rules, except for apps the group has its own rule for
		group_rule_ids = {app_id for app_id, _ in group_rules}
		global_rules = [restrictionRule(r) for r in MpSoftwareRestrictions.query.filter(
			MpSoftwareRestrictions.enabled == 1, MpSoftwareRestrictions.isglobal == 1).all()
			if r.appID not in group_rule_ids]

		config = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
		group_rev = config.restrictions_version if config is not None else 0

		return signed('SoftwareRestriction', {'revision': '%d-%s' % (len(global_rules), group_rev),
											  'rules': global_rules + [rule for _, rule in group_rules]})


class SoftwareInstallResult(MPResource):
	"""Record the result of a software install / uninstall."""

	@client_endpoint()
	def post(self, client_id):
		body = request.get_json(force=True)
		if body is None:
			log_Error('[SoftwareInstallResult][POST][%s] No data found to post.' % client_id)
			return fail(404, 'No data found to post.')
		log_Debug('[SoftwareInstallResult][POST][%s] %s' % (client_id, body))

		# The client sends either the table's column names, or the older SWTaskID / SWDistID names
		columns = {'SWTaskID': 'tuuid', 'SWDistID': 'suuid', 'ResultNo': 'result',
				   'ResultString': 'resultString', 'Action': 'action'}
		if 'SWTaskID' not in body:
			columns = {col: col for col in columns.values()}

		install = MpSoftwareInstall(cuuid=client_id, cdate=datetime.now())
		for key, col in columns.items():
			if key in body:
				setattr(install, col, body[key])

		try:
			db.session.add(install)
			db.session.commit()
		except IntegrityError as e:
			db.session.rollback()
			log_Error('[SoftwareInstallResult][POST][%s] %s' % (client_id, e))

		return ok(code=201, errormsg='')


# Add Routes Resources
software_5_api.add_resource(SoftwareTasksForGroup, '/sw/tasks/<string:client_id>/<string:groupName>', endpoint='swTasks')
software_5_api.add_resource(SoftwareTasksForGroup, '/sw/tasks/<string:client_id>/<string:groupName>/<string:osver>', endpoint='swTasksOS')
software_5_api.add_resource(SoftwareTaskForTaskID, '/sw/task/<string:client_id>/<string:taskID>')
software_5_api.add_resource(SoftwareProvisionDataForTaskID, '/sw/provision/task/<string:taskID>/<string:client_id>')
software_5_api.add_resource(SoftwareGroups, '/sw/groups/<string:client_id>', endpoint='swGroups')
software_5_api.add_resource(SoftwareGroups, '/sw/groups/<string:client_id>/<string:state>', endpoint='swGroupsState')
software_5_api.add_resource(SoftwareRestrictions, '/sw/restrictions/<string:client_id>')
software_5_api.add_resource(SoftwareInstallResult, '/sw/installed/<string:client_id>')
