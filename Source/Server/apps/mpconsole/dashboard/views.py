from flask import render_template
from flask_login import login_required, current_user
from sqlalchemy import text
from datetime import datetime, timedelta
from operator import itemgetter

import json

from .  import dashboard
from .. import login_manager
from .. import db
from .. model import *
from .. import errors

@dashboard.route('/dashboard')
@login_required
def index():
	clients = MpClient.query.all()
	_client_count = len(clients)

	# Get OS Ver Data
	osVerData = []
	sql1 = text('SELECT osver, Count(osver) As Count From mp_clients Group By osver Order By Count Desc')
	result = db.engine.execute(sql1)
	for row in result:
		osVerData.append((str(row[0]), str(row[1])))

	osVerMinorData = []
	sql1b = text("""SELECT SUBSTRING_INDEX(osver, ".", 2) as os, Count(*) as Count
					FROM mp_clients
					Group By os 
					Order By Count Desc""")

	# Get OS Ver Minor Count
	resultB = db.engine.execute(sql1b)
	for row in resultB:
		osVerMinorData.append((str(row[0]), str(row[1])))

	# Get Reboot Count
	rbData = []
	sql2 = text("""SELECT needsReboot, Count(*) As Count
				FROM mp_clients Group By needsReboot""")

	rb_result = db.engine.execute(sql2)
	for row in rb_result:
		rbData.append((str(row[0]).title(), str(row[1])))

	# Get Model Info
	sql3 = text("""
			SELECT hw.mpa_Model_Identifier AS ModelType, Count(hw.mpa_Model_Identifier) As Count
			FROM mp_clients mpc
			LEFT JOIN mpi_SPHardwareOverview hw ON hw.cuuid = mpc.cuuid
			Group By hw.mpa_Model_Identifier
			Order By Count Desc
			Limit 0,10
		""")

	mdl_data = []
	mdl_result = db.engine.execute(sql3)
	for row in mdl_result:
		mdl_data.append((str(row[0]).title(), str(row[1])))

	# Get Model Type Counts
	sql3b = text("""
			SELECT hw.mpa_Model_Identifier AS ModelType, Count(hw.mpa_Model_Identifier) As Count
			FROM mp_clients mpc
			LEFT JOIN mpi_SPHardwareOverview hw ON hw.cuuid = mpc.cuuid
			Group By hw.mpa_Model_Identifier
			Order By Count Desc
		""")

	mdlt_book_count = 0
	mdlt_desk_count = 0
	mdlt_serv_count = 0
	mdlt_result = db.engine.execute(sql3b)
	for row in mdlt_result:
		if "book" in str(row[0]).title().lower():
			mdlt_book_count = mdlt_book_count + row[1]
		elif "serve" in str(row[0]).title().lower():
			mdlt_serv_count = mdlt_serv_count + row[1]
		else:
			mdlt_desk_count = mdlt_desk_count + row[1]

	mdlt_data = [('Laptop',str(mdlt_book_count)),('Desktop',str(mdlt_desk_count)),('Server',str(mdlt_serv_count))]

	# Client Patch Status
	sql4a = text("""
				select patch, COUNT(*) as total
				from mp_client_patches_apple
				GROUP BY patch
				ORDER BY total Desc
				Limit 0,10
				""")
	sql4b = text("""
				select patch, COUNT(*) as Total
				from mp_client_patches_third
				WHERE patch NOT LIKE 'mpi_%'
				GROUP BY patch
				ORDER BY Total Desc
				Limit 0,10
				""")
	pch_data_raw = []
	pch_data = []
	pch_resultA = db.engine.execute(sql4a)
	pch_resultB = db.engine.execute(sql4b)
	for row in pch_resultA:
		pch_data_raw.append(row)
	for row in pch_resultB:
		pch_data_raw.append(row)

	for row in pch_data_raw:
		pch_data.append((str(row[0]).title(), row[1]))

	pch_data.sort(key=lambda tup: tup[1],reverse=True)
	pch_data = pch_data[:10]

	# Get Newly Released Patches
	_patches_released = []
	sql6 = text(""" select name as patchname, version, postdate
	from combined_patches_view
	where(postdate >= (now() - interval 14 day))
	AND active = '1'
	AND patch_state = 'Production'
	Order By postdate Desc""")

	result_patch_release = db.engine.execute(sql6)
	for row in result_patch_release:
		_dict = {}
		_dict['patch'] = str(row[0])
		_dict['version'] = str(row[1])
		_dict['date'] = str(row[2])
		_patches_released.append(_dict)

	# Get Top 10 Patch Installs in last 7 days
	sql7 = text(""" select patch_name, COUNT(*) as Total
	from mp_installed_patches
	Where mdate >= DATE(NOW()) - INTERVAL 7 DAY
	Group By patch_name
	Order By Total Desc Limit 10""")

	install_data = []
	install_result = db.engine.execute(sql7)
	for row in install_result:
		install_data.append((str(row[0]).title(), str(row[1])))

	# Client Checkin Status
	status_data = []
	today = datetime.now()
	normal = 0
	warn = 0
	alert = 0
	sql5 = text(""" SELECT mdate From mp_clients""")
	status_result = db.engine.execute(sql5)
	for row in status_result:
		diff = today - row[0]
		if diff.days <= 7:
			normal = normal + 1
		if diff.days > 7 and diff.days < 15:
			warn = warn + 1
		if diff.days >= 15:
			alert = alert + 1

	status_data = [normal, warn, alert]

	agents_data = []
	sql6 = text(""" select client_version, Count(*) as Total from mp_clients
	GROUP BY client_version
	Order By total Desc
	""")
	agentver_result = db.engine.execute(sql6)
	for row in agentver_result:
		agents_data.append((str(row[0]).title(), str(row[1])))







	return render_template('dashboard/dashboard.html', clientCount=_client_count, osData=osVerData, osMinor=osVerMinorData,
						   rebootData=rbData, modelData=mdl_data, modelTypeData=mdlt_data, patchData=pch_data, clientStatus=status_data,
						   agentVers=agents_data, patchReleased=_patches_released, patchInstalled=install_data)


# HTML View
@dashboard.route('/drilldown/<chart>/<value>')
@login_required
def drilldown(chart,value):
	title = "Default Title"
	cols = []
	data = []
	result = drillDownDataFilter(chart, value)
	if result is not None:
		title = result[2]
		cols = result[1]
		data = result[0]


	return render_template('dashboard/dashview.html', dataTitle=title, data=data, columns=cols, chart=chart, value=value)

# Modal Data, for refresh etc
@dashboard.route('/data/<chart>/<value>')
def drilldowndata(chart,value):

	result = drillDownDataFilter(chart, value)
	if result is not None:
		return json.dumps({'data': result[0], 'columns': result[1]}, default=json_serial), 200
	else:
		return json.dumps({'data': [], 'columns': []}, default=json_serial), 404

# Private/local
def drillDownDataFilter(chart, filterValue):
	title = "Default Title"
	cols = []
	data = []

	if chart == "osver":
		title = "OS Version - " + filterValue
		result = osVersionCollection(filterValue)
		data = result[0]
		cols = result[1]
	elif chart == "osverminor":
		title = "OS Version - " + filterValue
		result = osVersionMinorCollection(filterValue)
		data = result[0]
		cols = result[1]
	elif chart == "reboot":
		title = "OS Version - " + filterValue
		result = needsRebootCollection(filterValue.lower())
		data = result[0]
		cols = result[1]
	elif chart == "modelType":
		title = "Model Type - " + filterValue
		result = modelTypeCollection(filterValue)
		data = result[0]
		cols = result[1]
	elif chart == "modelTypes":
		title = "Model Type - " + filterValue
		result = modelTypesCollection(filterValue)
		data = result[0]
		cols = result[1]
	elif chart == "requiredPatches":
		title = "Required Patch - " + filterValue
		result = requiredPatchCollection(filterValue)
		data = result[0]
		cols = result[1]
	elif chart == "installedPatch":
		title = "Installed Patch - " + filterValue
		result = installedPatchCollection(filterValue)
		data = result[0]
		cols = result[1]
	elif chart == "agentStatus":
		title = "Agent Status - " + filterValue
		result = agentStatusCollection(filterValue)
		data = result[0]
		cols = result[1]
	elif chart == "agentVersion":
		title = "Agent Version - " + filterValue
		result = agentVersionCollection(filterValue)
		data = result[0]
		cols = result[1]

	return data, cols, title

# Filter - OS Version Query
def osVersionCollection(os_version):
	_results = []
	clients = MpClient.query.outerjoin(MPIDirectoryServices, MPIDirectoryServices.cuuid == MpClient.cuuid).add_columns(
		MPIDirectoryServices.mpa_ADDomain, MPIDirectoryServices.mpa_distinguishedName).outerjoin(
		MpClientGroupMembers, MpClientGroupMembers.cuuid == MpClient.cuuid).add_columns(
		MpClientGroupMembers.group_id).filter(MpClient.osver == os_version).all()

	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'computername', 'label': 'Computer Name'},
				{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
				{'name': 'ipaddr', 'label': 'IP Address'}, {'name': 'serialno', 'label': 'Serial No'},
				{'name': 'osver', 'label': 'OS Ver'},{'name': 'mdate', 'label': 'Last Check-in'}]

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	for c in clients:
		_dict = c[0].asDict
		_dict['addomain'] = c.mpa_ADDomain
		_dict['addn'] = c.mpa_distinguishedName
		if c.group_id and _client_Groups[c.group_id]:
			_dict['client_group'] = _client_Groups[c.group_id]
		else:
			_dict['client_group'] = "NA"
		_results.append(_dict)

	return _results, colNames

# Filter - OS Version Query
def osVersionMinorCollection(os_version_minor):
	_results = []
	clients = MpClient.query.outerjoin(MPIDirectoryServices, MPIDirectoryServices.cuuid == MpClient.cuuid).add_columns(
		MPIDirectoryServices.mpa_ADDomain, MPIDirectoryServices.mpa_distinguishedName).outerjoin(
		MpClientGroupMembers, MpClientGroupMembers.cuuid == MpClient.cuuid).add_columns(
		MpClientGroupMembers.group_id).filter(MpClient.osver.like(os_version_minor+"%")).all()

	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'computername', 'label': 'Computer Name'},
				{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
				{'name': 'ipaddr', 'label': 'IP Address'}, {'name': 'serialno', 'label': 'Serial No'},
				{'name': 'osver', 'label': 'OS Ver'},{'name': 'mdate', 'label': 'Last Check-in'}]

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	for c in clients:
		_dict = c[0].asDict
		_dict['addomain'] = c.mpa_ADDomain
		_dict['addn'] = c.mpa_distinguishedName
		if c.group_id and _client_Groups[c.group_id]:
			_dict['client_group'] = _client_Groups[c.group_id]
		else:
			_dict['client_group'] = "NA"
		_results.append(_dict)

	return _results, colNames

# Filter - Reboot Status
def needsRebootCollection(reboot):
	_results = []
	clients = MpClient.query.outerjoin(MPIDirectoryServices, MPIDirectoryServices.cuuid == MpClient.cuuid).add_columns(
		MPIDirectoryServices.mpa_ADDomain, MPIDirectoryServices.mpa_distinguishedName).outerjoin(
		MpClientGroupMembers, MpClientGroupMembers.cuuid == MpClient.cuuid).add_columns(
		MpClientGroupMembers.group_id).filter(MpClient.needsreboot == str(reboot)).all()

	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'computername', 'label': 'Computer Name'},
				{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
				{'name': 'ipaddr', 'label': 'IP Address'}, {'name': 'serialno', 'label': 'Serial No'},
				{'name': 'needsreboot', 'label': 'Needs Reboot'},{'name': 'osver', 'label': 'OS Ver'},
				{'name': 'mdate', 'label': 'Last Check-in'}]

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	for c in clients:
		_dict = c[0].asDict
		_dict['addomain'] = c.mpa_ADDomain
		_dict['addn'] = c.mpa_distinguishedName
		if c.group_id and _client_Groups[c.group_id]:
			_dict['client_group'] = _client_Groups[c.group_id]
		else:
			_dict['client_group'] = "NA"
		_results.append(_dict)

	return _results, colNames

# Filter - Model Type
def modelTypeCollection(model):
	_results = []
	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'computername', 'label': 'Computer Name'},
				{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
				{'name': 'ipaddr', 'label': 'IP Address'}, {'name': 'serialno', 'label': 'Serial No'},
				{'name': 'modelType', 'label': 'Model Type'}, {'name': 'osver', 'label': 'OS Ver'},
				{'name': 'mdate', 'label': 'Last Check-in'}]

	# Get Model Info
	sqlStr = text("""
				SELECT *, hw.mpa_Model_Identifier AS modelType, cg.group_id as client_group,
				ds.mpa_distinguishedName as addn, ds.mpa_ADDomain as addomain
				FROM mp_clients mpc
				LEFT JOIN mpi_SPHardwareOverview hw ON hw.cuuid = mpc.cuuid
				LEFT JOIN mpi_DirectoryServices ds ON ds.cuuid = mpc.cuuid
				LEFT JOIN mp_client_group_members cg ON cg.cuuid = mpc.cuuid
				Where hw.mpa_Model_Identifier = '""" + model + """'
				""")

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	mdl_result = db.engine.execute(sqlStr)
	for row in mdl_result:
		_dict = {}
		for col in colNames:
			_name = col['name']
			if _name in row:
				if _name == 'client_group':
					_row_val = row[_name]
					if _row_val:
						_dict[_name] = _client_Groups[_row_val]
					else:
						_dict[_name] = ""
				else:
					_dict[_name] = row[_name]
			else:
				_dict[_name] = ""

		_results.append(_dict)

	return _results, colNames

# Filter - Model Types (Laptop, Desktop ...)
def modelTypesCollection(model):
	_results = []
	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'computername', 'label': 'Computer Name'},
				{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
				{'name': 'ipaddr', 'label': 'IP Address'}, {'name': 'serialno', 'label': 'Serial No'},
				{'name': 'modelType', 'label': 'Model Type'}, {'name': 'osver', 'label': 'OS Ver'},
				{'name': 'mdate', 'label': 'Last Check-in'}]

	# Get Model Info
	if model == 'Laptop':
		sqlStr = text("""
					SELECT *, hw.mpa_Model_Identifier AS modelType, cg.group_id as client_group,
					ds.mpa_distinguishedName as addn, ds.mpa_ADDomain as addomain
					FROM mp_clients mpc
					LEFT JOIN mpi_SPHardwareOverview hw ON hw.cuuid = mpc.cuuid
					LEFT JOIN mpi_DirectoryServices ds ON ds.cuuid = mpc.cuuid
					LEFT JOIN mp_client_group_members cg ON cg.cuuid = mpc.cuuid
					WHERE hw.mpa_Model_Identifier like '%book%'
					""")
	elif model == 'Server':
		sqlStr = text("""
							SELECT *, hw.mpa_Model_Identifier AS modelType, cg.group_id as client_group,
							ds.mpa_distinguishedName as addn, ds.mpa_ADDomain as addomain
							FROM mp_clients mpc
							LEFT JOIN mpi_SPHardwareOverview hw ON hw.cuuid = mpc.cuuid
							LEFT JOIN mpi_DirectoryServices ds ON ds.cuuid = mpc.cuuid
							LEFT JOIN mp_client_group_members cg ON cg.cuuid = mpc.cuuid
							WHERE hw.mpa_Model_Identifier like '%serve%'
							""")
	elif model == 'Desktop':
		sqlStr = text("""
							SELECT *, hw.mpa_Model_Identifier AS modelType, cg.group_id as client_group,
							ds.mpa_distinguishedName as addn, ds.mpa_ADDomain as addomain
							FROM mp_clients mpc
							LEFT JOIN mpi_SPHardwareOverview hw ON hw.cuuid = mpc.cuuid
							LEFT JOIN mpi_DirectoryServices ds ON ds.cuuid = mpc.cuuid
							LEFT JOIN mp_client_group_members cg ON cg.cuuid = mpc.cuuid
							WHERE hw.mpa_Model_Identifier not like '%serve%'
							AND hw.mpa_Model_Identifier not like '%Book%'
							""")
	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	mdl_result = db.engine.execute(sqlStr)
	for row in mdl_result:
		_dict = {}
		for col in colNames:
			_name = col['name']
			if _name in row:
				if _name == 'client_group':
					_row_val = row[_name]
					if _row_val:
						_dict[_name] = _client_Groups[_row_val]
					else:
						_dict[_name] = ""
				else:
					_dict[_name] = row[_name]
			else:
				_dict[_name] = ""

		_results.append(_dict)

	return _results, colNames

# Filter - Required Patch
def requiredPatchCollection(patch):
	_results = []
	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'addomain', 'label': 'AD-Domain'},
				{'name': 'addn', 'label': 'AD-DistinguishedName'},{'name': 'ipaddr', 'label': 'IP Address'},
				{'name': 'serialno', 'label': 'Serial No'},{'name': 'patch', 'label': 'Patch'},
				{'name': 'type', 'label': 'Patch Type'},{'name': 'osver', 'label': 'OS Ver'},
				{'name': 'mdate', 'label': 'Last Check-in'}]

	# Get Model Info
	sqlStr = text("""
					SELECT *, cg.group_id as client_group, ds.mpa_distinguishedName as addn, ds.mpa_ADDomain as addomain,
					cli.osver as osver, cli.serialno as serialno
					FROM client_patch_status_view mpc
					LEFT JOIN mp_clients cli ON cli.cuuid = mpc.cuuid
					LEFT JOIN mpi_DirectoryServices ds ON ds.cuuid = mpc.cuuid
					LEFT JOIN mp_client_group_members cg ON cg.cuuid = mpc.cuuid
					Where patch like '""" + patch + """%'
					""")

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	mdl_result = db.engine.execute(sqlStr)
	for row in mdl_result:
		_dict = {}
		for col in colNames:
			_name = col['name']
			if _name in row:
				if _name == 'client_group':
					_row_val = row[_name]
					if _row_val:
						_dict[_name] = _client_Groups[_row_val]
					else:
						_dict[_name] = ""
				else:
					_dict[_name] = row[_name]
			else:
				_dict[_name] = ""

		_results.append(_dict)

	return _results, colNames

# Filter - Installed Patch
def installedPatchCollection(patch):
	_results = []
	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'addomain', 'label': 'AD-Domain'},
				{'name': 'addn', 'label': 'AD-DistinguishedName'},{'name': 'ipaddr', 'label': 'IP Address'},
				{'name': 'serialno', 'label': 'Serial No'},{'name': 'patch', 'label': 'Patch'},
				{'name': 'type', 'label': 'Patch Type'},{'name': 'osver', 'label': 'OS Ver'},
				{'name': 'mdate', 'label': 'Last Check-in'}]

	# Get Model Info
	sqlStr = text("""
					SELECT *, cg.group_id as client_group, ds.mpa_distinguishedName as addn, ds.mpa_ADDomain as addomain,
					cli.osver as osver, cli.serialno as serialno
					FROM mp_installed_patches mpc
					LEFT JOIN mp_clients cli ON cli.cuuid = mpc.cuuid
					LEFT JOIN mpi_DirectoryServices ds ON ds.cuuid = mpc.cuuid
					LEFT JOIN mp_client_group_members cg ON cg.cuuid = mpc.cuuid
					Where patch_name like '""" + patch + """%'
					""")

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	mdl_result = db.engine.execute(sqlStr)
	for row in mdl_result:
		_dict = {}
		for col in colNames:
			_name = col['name']
			if _name in row:
				if _name == 'client_group':
					_row_val = row[_name]
					if _row_val:
						_dict[_name] = _client_Groups[_row_val]
					else:
						_dict[_name] = ""
				else:
					_dict[_name] = row[_name]
			else:
				_dict[_name] = ""

		_results.append(_dict)

	return _results, colNames

# Filter Agent Status
def agentStatusCollection(state):

	_results = []
	colNames = []

	clients = MpClient.query.outerjoin(MPIDirectoryServices, MPIDirectoryServices.cuuid == MpClient.cuuid).add_columns(
		MPIDirectoryServices.mpa_ADDomain, MPIDirectoryServices.mpa_distinguishedName).outerjoin(
		MpClientGroupMembers, MpClientGroupMembers.cuuid == MpClient.cuuid).add_columns(
		MpClientGroupMembers.group_id).all()

	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'computername', 'label': 'Computer Name'},
				{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
				{'name': 'ipaddr', 'label': 'IP Address'}, {'name': 'serialno', 'label': 'Serial No'},
				{'name': 'osver', 'label': 'OS Ver'}, {'name': 'mdate', 'label': 'Last Checkin'}]

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	today = datetime.today()
	for row in clients:
		_dict = row[0].asDict
		_dict['addomain'] = row.mpa_ADDomain
		_dict['addn'] = row.mpa_distinguishedName

		if row.group_id:
			_dict['client_group'] = _client_Groups[row.group_id]
		else:
			_dict['client_group'] = ""


		diff = today - row[0].mdate
		if diff.days <= 7:
			if state == 'Normal':
				_results.append(_dict)
		if diff.days > 7 and diff.days < 15:
			if state == 'Warning':
				_results.append(_dict)
		if diff.days >= 15:
			if state == 'Alert':
				_results.append(_dict)

	return _results, colNames

# Filter - Agent Version
def agentVersionCollection(version):
	_results = []
	colNames = []

	clients = MpClient.query.outerjoin(MPIDirectoryServices, MPIDirectoryServices.cuuid == MpClient.cuuid).add_columns(
		MPIDirectoryServices.mpa_ADDomain, MPIDirectoryServices.mpa_distinguishedName).outerjoin(
		MpClientGroupMembers, MpClientGroupMembers.cuuid == MpClient.cuuid).add_columns(
		MpClientGroupMembers.group_id).filter(MpClient.client_version == version).all()

	colNames = [{'name': 'cuuid', 'label': 'CUUID'}, {'name': 'client_group', 'label': 'Client Group'},
				{'name': 'hostname', 'label': 'Host Name'}, {'name': 'computername', 'label': 'Computer Name'},
				{'name': 'addomain', 'label': 'AD-Domain'}, {'name': 'addn', 'label': 'AD-DistinguishedName'},
				{'name': 'ipaddr', 'label': 'IP Address'}, {'name': 'serialno', 'label': 'Serial No'},
				{'name': 'client_version', 'label': 'Agent Version'}, {'name': 'osver', 'label': 'OS Ver'},
				{'name': 'mdate', 'label': 'Last Check-in'}]

	_client_Groups = {}
	q_client_Groups = MpClientGroups.query.all()
	for g in q_client_Groups:
		_client_Groups[g.group_id] = g.group_name

	for row in clients:
		_dict = row[0].asDict

		_dict['addomain'] = row.mpa_ADDomain
		_dict['addn'] = row.mpa_distinguishedName

		_dict['addomain'] = row.mpa_ADDomain
		_dict['addn'] = row.mpa_distinguishedName
		if row.group_id and _client_Groups[row.group_id]:
			_dict['client_group'] = _client_Groups[row.group_id]
		else:
			_dict['client_group'] = "NA"

		_results.append(_dict)

	return _results, colNames

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.isoformat()
		return serial
	raise TypeError("Type not serializable")
