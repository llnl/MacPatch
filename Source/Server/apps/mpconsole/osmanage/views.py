from flask import render_template, request
from flask_security import login_required
from datetime import *
import json
from datetime import datetime
import uuid
import re
from yattag import indent
import hashlib

from . import osmanage
from .. import login_manager
from .. import db
from .. model import *
from .. modes import *
from .. mplogger import *

'''
	This method queries the DB for all uploaded profiles
	Add renders the os_profiles.html File
'''
@osmanage.route('/profiles')
@login_required
def profiles():
	columns = [('profileID', 'Profile ID', '0'), ('profileIdentifier', 'Profile Identifier', '0'), ('profileName', 'Name', '1'),
				('profileDescription', 'Description', '1'), ('profileRev', 'Revision', '1'), ('enabled', 'Enabled', '1'),
			   ('isglobal', 'Global', '1'), ('uninstallOnRemove', 'Uninstall On Remove', '1')]

	return render_template('os_managment/os_profiles.html', data=[], columns=columns)

# JSON Routes
# This method is called by os_profiles.html for a list of profiles
# This is done so that the refresh can be used
@osmanage.route('/profiles/list')
@login_required
def profilesListJSON():
	_results = []

	columns = [('profileID', 'Profile ID', '0'), ('profileIdentifier', 'Profile Identifier', '0'),
			   ('profileName', 'Name', '1'),
			   ('profileDescription', 'Description', '1'), ('profileRev', 'Revision', '1'), ('enabled', 'Enabled', '1'),
			   ('isglobal', 'Global', '1'), ('uninstallOnRemove', 'Uninstall On Remove', '1')]

	profileQuery = MpOsConfigProfiles.query.order_by(MpOsConfigProfiles.mdate.desc()).all()
	for p in profileQuery:
		row = {}
		for c in columns:
			y = "p." + c[0]
			if c[0] == 'enabled' or c[0] == 'uninstallOnRemove' or c[0] == 'isglobal':
				row[c[0]] = "Yes" if eval(y) == 1 else "No"
			else:
				row[c[0]] = eval(y)

		_results.append(row)

	return json.dumps({'data': _results}, default=json_serial), 200

'''
	This method renders the os_profile_manager.html File
	For a new profile
'''
@osmanage.route('/profiles/add')
@login_required
def profileAdd():

	profile_id = str(uuid.uuid4())
	return render_template('os_managment/os_profile_manager.html', profileData={}, profileCriteriaAlt={}, profileDataAlt={}, profileDataRE={}, profileID=profile_id)

'''
	This method renders the os_profile_manager.html File
	This is to edit an existing profile
'''
@osmanage.route('/profiles/update/<profile_id>')
@login_required
def profileEdit(profile_id):

	cri = {} # Global Criteria
	groupPolicyID = ''

	profile = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.profileID == profile_id).first()

	if profile is not None:
		if profile.isglobal == 1:
			groupPolicy = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.groupID == 0, MpOsProfilesGroupAssigned.profileID == profile_id).first()
			if groupPolicy is not None:
				groupPolicyID = groupPolicy.gPolicyID


				criteriaQuery = MpOsProfilesCriteria.query.filter(MpOsProfilesCriteria.gPolicyID == groupPolicyID).order_by(
				MpOsProfilesCriteria.type_order.asc()).all()

				profileCritLst = []
				for crit in criteriaQuery:
					patchCritDict = crit.__dict__
					del patchCritDict['_sa_instance_state']
					del patchCritDict['rid']
					if patchCritDict['type'] == "Script":
						patchCritDict['type_data'] = escapeStringForACEEditor(patchCritDict['type_data'])

					profileCritLst.append(patchCritDict)

				cri = {}
				for c in criteriaQuery:
					cri[c.type] = c.type_data

	# Parse BLOB Data
	pData = str(profile.profileData)
	pData = unicode(pData, errors='replace')

	# Using RE get the data between <?xml ... </plist>
	stringlist = re.findall('<\?.+</plist>', pData, re.DOTALL)
	pData2 = ""
	pretty_string = ""
	if len(stringlist) >= 1:
		pData2 = stringlist[0]
		pData2 = pData2.replace('\\n', '')  # Remove \n from string purely for formatting
		pretty_string = indent(pData2,indentation='    ')

	return render_template('os_managment/os_profile_manager.html', profileData=profile, profileDataAlt=pData, profileCriteriaAlt=cri,
						   profileDataRE=pretty_string, profileID=profile_id, groupPolicyID=groupPolicyID)

''' Private '''
'''
	Method to verify file extension
'''
ALLOWED_EXTENSIONS = set(['plist', 'mobileprovision', 'mobileconfig'])
def allowed_file(filename):
	return '.' in filename and filename.rsplit('.', 1)[1] in ALLOWED_EXTENSIONS

''' AJAX Request '''
@osmanage.route('/profile/save/<profile_id>', methods=['POST'])
@login_required
def profileSave(profile_id):
	if adminRole() or localAdmin():
		formDict = request.form.to_dict()

		isNewProfile=False
		profile = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.profileID == profile_id).first()
		if profile is None:
			profile = MpOsConfigProfiles()
			isNewProfile=True

		if 'profileFile' in request.files:
			# Save File, returns path to file
			_file = request.files['profileFile']
			_file_data = _file.read()

			if _file_data and allowed_file(_file.filename):
				# Gen Hash
				profile__hash = hashlib.md5(_file_data).hexdigest()
				#setattr(profile, 'profileData', _file_data.encode('string-escape').encode('utf-8'))
				# commented, issue with encoding, using defaults 
				setattr(profile, 'profileData', _file_data)
				setattr(profile, 'profileHash', profile__hash)

		# Save Profile Data
		setattr(profile, 'profileName', formDict['profileName'])
		setattr(profile, 'profileDescription', formDict['profileDescription'])
		setattr(profile, 'enabled', formDict['enabled'])
		setattr(profile, 'isglobal', formDict['isglobal'])
		setattr(profile, 'uninstallOnRemove', formDict['uninstallOnRemove'])
		setattr(profile, 'mdate', datetime.now())

		if isNewProfile:
			setattr(profile, 'cdate', datetime.now())
			setattr(profile, 'profileRev', 1)
			setattr(profile, 'profileID', profile_id)
			setattr(profile, 'profileIdentifier', formDict['profileIdentifier'])
			db.session.add(profile)
			log("{} added new config profile {}.".format(session.get('user'), formDict['profileName']))
		else:
			setattr(profile, 'profileRev', (profile.profileRev + 1))
			log("{} updated config profile {}.".format(session.get('user'), formDict['profileName']))

		db.session.commit()

		if formDict['isglobal'] == '1':
			gres = updateGlobalProfileCriteria(profile_id, formDict)
			if gres:
				log("Global profile criteria was added for {}".format(formDict['profileName']))


		return json.dumps({'error': 0}), 200

	else:
		log_Error("{} does not have permission to save config profile.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

def updateGlobalProfileCriteria(profile_id, formDict):

	# This is the global group ID
	groupID = 0

	if groupAdminRights(groupID) or localAdmin():

		gPolicyID = str(uuid.uuid4())
		if 'gPolicyID' in formDict:
			if formDict['gPolicyID'] is not None and len(formDict['gPolicyID']) >= 1:
				gPolicyID = formDict['gPolicyID']

		addNew = False
		qPolicy = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.gPolicyID == gPolicyID).first()
		if not qPolicy:
			addNew = True
			qPolicy = MpOsProfilesGroupAssigned()

		setattr(qPolicy, 'gPolicyID', gPolicyID)
		setattr(qPolicy, 'profileID', profile_id)
		setattr(qPolicy, 'groupID', groupID)
		setattr(qPolicy, 'title', 'Global')
		setattr(qPolicy, 'description', 'Global')
		setattr(qPolicy, 'enabled', formDict['enabled'])

		if addNew:
			db.session.add(qPolicy)
			log("{} added global group config profile {}.".format(session.get('user'), profile_id))
		else:
			log("{} updated global group config profile {}.".format(session.get('user'), profile_id))

		# Set profile assignment policy filter
		MpOsProfilesCriteria.query.filter(MpOsProfilesCriteria.gPolicyID == gPolicyID).delete()
		for key in formDict:
			if key.startswith('cri_'):
					cri = MpOsProfilesCriteria()
					setattr(cri, 'gPolicyID', gPolicyID)
					if key == 'cri_os_type':
						setattr(cri, 'type', 'OSType')
						setattr(cri, 'type_data', formDict[key])
						setattr(cri, 'type_order', 1)
						db.session.add(cri)
						continue

					if key == 'cri_os_ver':
						setattr(cri, 'type', 'OSVersion')
						setattr(cri, 'type_data', formDict[key])
						setattr(cri, 'type_order', 2)
						db.session.add(cri)
						continue

					if key == 'cri_system_type':
						setattr(cri, 'type', 'SYSType')
						setattr(cri, 'type_data', formDict[key])
						setattr(cri, 'type_order', 3)
						db.session.add(cri)
						continue

					if key == 'cri_model_type':
						setattr(cri, 'type', 'ModelType')
						setattr(cri, 'type_data', formDict[key])
						setattr(cri, 'type_order', 4)
						db.session.add(cri)
						continue

			if key.startswith('req_cri_type_'):

				formLst = key.split('_')
				nid = formLst[-1]
				norder = int(formDict['req_cri_order_'+str(nid)])
				if norder <= 4:
					norder = norder + 4

				formData = formDict['req_cri_data_'+str(nid)]
				formType = formDict['req_cri_type_'+str(nid)]

				cri = MpOsProfilesCriteria()
				setattr(cri, 'gPolicyID', gPolicyID)
				setattr(cri, 'type', formType)
				setattr(cri, 'type_data', formData)
				setattr(cri, 'type_order', norder)
				db.session.add(cri)

		db.session.commit()
		return True
	else:
		log_Error("{} is not an admin no profile criteria can be added.".format(session.get('user')))
		return False

''' AJAX Request '''
@osmanage.route('/profile/delete',methods=['DELETE'])
@login_required
def profileDelete():
	if adminRole() or localAdmin():
		if request.method == 'DELETE':
			formDict = request.form.to_dict()
			profile_ids = formDict['profileID'].split(",")
			for pid in profile_ids:
				delPro = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.profileID == pid).first()
				if delPro is not None:
					log_Error("{} deleted config profile {}.".format(session.get('user'), delPro.profileName))
					db.session.delete(delPro)

			db.session.commit()

		return json.dumps({'error': 0}), 200
	else:
		log_Error("{} does not have permission to delete config profile.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

'''
	-------------------------------------------
	Group Profile Assignments
	-------------------------------------------
'''
@osmanage.route('/profile/group/<group_id>/add',methods=['GET'])
@login_required
def addProfileToGroup(group_id):
	profilesQuery = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.enabled == 1).all()
	profilesRes = []
	for p in profilesQuery:
		row = {}
		row['profileID'] = p.profileID
		row['title'] = p.profileName + " (" + p.profileIdentifier +")"
		profilesRes.append(row)

	return render_template('os_managment/os_profile_wizard.html', profileData={}, profileCriteria={}, profileCriteriaAlt={}, profileArray=profilesRes, groupID=group_id)

@osmanage.route('/profile/group/<group_id>/edit/<policy_id>',methods=['GET'])
@login_required
def editProfileInGroup(group_id, policy_id):
	profilesQuery = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.enabled == 1).all()

	profilesRes = []
	for p in profilesQuery:
		row = {}
		row['profileID'] = p.profileID
		row['title'] = p.profileName + " (" + p.profileIdentifier +")"
		profilesRes.append(row)

	policyQuery = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.gPolicyID == policy_id).first()
	criteriaQuery = MpOsProfilesCriteria.query.filter(MpOsProfilesCriteria.gPolicyID == policy_id).order_by(MpOsProfilesCriteria.type_order.asc()).all()

	profileCritLst = []
	for crit in criteriaQuery:
		patchCritDict = crit.__dict__
		del patchCritDict['_sa_instance_state']
		del patchCritDict['rid']
		if patchCritDict['type'] == "Script":
			patchCritDict['type_data'] = escapeStringForACEEditor(patchCritDict['type_data'])

		profileCritLst.append(patchCritDict)

	cri = {}
	for c in criteriaQuery:
		cri[c.type] = c.type_data

	return render_template('os_managment/os_profile_wizard.html', profileData=policyQuery, profileCriteria=profileCritLst, profileArray=profilesRes, groupID=group_id, profileCriteriaAlt=cri)

''' AJAX Method '''
@osmanage.route('/profile/<gprofile_id>',methods=['GET','DELETE'])
@login_required
def profile(gprofile_id):

	if request.method == 'DELETE':
		profileQuery = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.gPolicyID == gprofile_id).first()
		if profileQuery is not None:
			_groupID = profileQuery.groupID
			_title = profileQuery.title
			_profile = profileQuery.profileID

			if groupAdminRights(_groupID) or localAdmin():
				db.session.delete(profileQuery)
				MpOsProfilesCriteria.query.filter(MpOsProfilesCriteria.gPolicyID == gprofile_id).delete()
				db.session.commit()

				log("{} deleted assigned {} config profile {}.".format(session.get('user'), _title, _profile))
				return json.dumps({'error': 0}), 200
			else:
				log_Error("{} does not have permission to delete {} config profile assignment.".format(session.get('user'), _title))
				return json.dumps({'error': 0}), 403

	# TODO: Not complete
	if request.method == 'GET':
		profileQuery = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.profileid == gprofile_id).first()
		_result = {}

		return json.dumps({'error': 0}), 200

	return json.dumps({'error': 0}), 200

''' AJAX Method '''
@osmanage.route('/profiles/group/<group_id>', methods=['GET'])
@login_required
def groupProfiles(group_id):

	columns = [('profileID', 'Profile ID', '0'), ('gPolicyID', 'Policy Identifier', '0'), ('pName', 'Profile Name', '1'), ('title', 'Title', '1'),
				('description', 'Description', '1'), ('enabled', 'Enabled', '1')]

	profiles = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.groupID == group_id).join(
		MpOsConfigProfiles, MpOsConfigProfiles.profileID == MpOsProfilesGroupAssigned.profileID).add_columns(
		MpOsConfigProfiles.profileName).all()

	_results = []
	if profiles is not None:
		for p in profiles:
			row = {}
			for c in columns:
				if c[0] == 'pName':
					row[c[0]] = p.profileName
				else:
					y = "p[0]."+c[0]
					row[c[0]] = eval(y)

			_results.append(row)

	return json.dumps({'data': _results, 'total': 0}), 200

''' AJAX Method '''
@osmanage.route('/group/profile', methods=['POST'])
@login_required
def postProfile():
	_formDict = dict(request.form)

	groupID = request.form['groupID']
	if groupID is None or len(groupID) <= 0:
		return json.dumps({'error': 404}), 404

	if groupAdminRights(groupID) or localAdmin():
		gPolicyID = request.form['gPolicyID']
		if gPolicyID is None or len(gPolicyID) <= 0:
			gPolicyID = str(uuid.uuid4())

		profileID = request.form['profileID']

		addNew = False
		qPolicy = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.gPolicyID == gPolicyID).first()
		if not qPolicy:
			addNew = True
			qPolicy = MpOsProfilesGroupAssigned()

		setattr(qPolicy, 'gPolicyID', gPolicyID)
		setattr(qPolicy, 'profileID', profileID)
		setattr(qPolicy, 'groupID', groupID)
		setattr(qPolicy, 'title', request.form['title'])
		setattr(qPolicy, 'description', request.form['description'])
		setattr(qPolicy, 'enabled', request.form['enabled'])
		if addNew:
			db.session.add(qPolicy)
			log("{} added group config profile {}.".format(session.get('user'), profileID))
		else:
			log("{} updated group config profile {}.".format(session.get('user'), profileID))

		# Set profile assignment policy filter
		MpOsProfilesCriteria.query.filter(MpOsProfilesCriteria.gPolicyID == gPolicyID).delete()
		for key in _formDict:
			if key.startswith('cri_'):
					cri = MpOsProfilesCriteria()
					setattr(cri, 'gPolicyID', gPolicyID)
					if key == 'cri_os_type':
						setattr(cri, 'type', 'OSType')
						setattr(cri, 'type_data', request.form[key])
						setattr(cri, 'type_order', 1)
						db.session.add(cri)
						continue

					if key == 'cri_os_ver':
						setattr(cri, 'type', 'OSVersion')
						setattr(cri, 'type_data', request.form[key])
						setattr(cri, 'type_order', 2)
						db.session.add(cri)
						continue

					if key == 'cri_system_type':
						setattr(cri, 'type', 'SYSType')
						setattr(cri, 'type_data', request.form[key])
						setattr(cri, 'type_order', 3)
						db.session.add(cri)
						continue

					if key == 'cri_model_type':
						setattr(cri, 'type', 'ModelType')
						setattr(cri, 'type_data', request.form[key])
						setattr(cri, 'type_order', 4)
						db.session.add(cri)
						continue

			if key.startswith('req_cri_type_'):

				formLst = key.split('_')
				nid = formLst[-1]
				norder = int(request.form['req_cri_order_'+str(nid)])
				if norder <= 4:
					norder = norder + 4

				formData = request.form['req_cri_data_'+str(nid)]
				formType = request.form['req_cri_type_'+str(nid)]

				cri = MpOsProfilesCriteria()
				setattr(cri, 'gPolicyID', gPolicyID)
				setattr(cri, 'type', formType)
				setattr(cri, 'type_data', formData)
				setattr(cri, 'type_order', norder)
				db.session.add(cri)

		db.session.commit()
		return json.dumps({'error': 0}), 200

	else:
		log_Error("{} does not have permission to add/update group config profile.".format(session.get('user')))
		return json.dumps({'error': 0}), 403

'''
	-------------------------------------------
	App Filters
	-------------------------------------------
'''
@osmanage.route('/app_filters')
@login_required
def appFilters():
	columns = [('profileID', 'Profile ID', '0'), ('profileIdentifier', 'Profile Identifier', '1'), ('profileName', 'Name', '1'),
				('profileDescription', 'Description', '1'), ('profileRev', 'Revision', '1'), ('enabled', 'Enabled', '1'),
				('uninstallOnRemove', 'Uninstall On Remove', '1')]

	profileQuery = MpOsConfigProfiles.query.all()

	_results = []
	for p in profileQuery:
		row = {}
		for c in columns:
			y = "p."+c[0]
			if c[0] == 'enabled' or c[0] == 'uninstallOnRemove':
				row[c[0]] = "Yes" if eval(y) == 1 else "No"
			else:
				row[c[0]] = eval(y)

		_results.append(row)

	return render_template('os_managment/os_app_filters.html', data=_results, columns=columns)

'''
	-------------------------------------------
	OS Configuration
	-------------------------------------------
'''
@osmanage.route('/os/config')
@login_required
def osConfig():

	columns = [('profileID', 'Profile ID', '0'), ('profileIdentifier', 'Profile Identifier', '1'), ('profileName', 'Name', '1'),
				('profileDescription', 'Description', '1'), ('profileRev', 'Revision', '1'), ('enabled', 'Enabled', '1'),
				('uninstallOnRemove', 'Uninstall On Remove', '1')]

	profileQuery = MpOsConfigProfiles.query.all()

	_results = []
	for p in profileQuery:
		row = {}
		for c in columns:
			y = "p."+c[0]
			if c[0] == 'enabled' or c[0] == 'uninstallOnRemove':
				row[c[0]] = "Yes" if eval(y) == 1 else "No"
			else:
				row[c[0]] = eval(y)

		_results.append(row)

	return render_template('os_managment/os_app_filters.html', data=_results, columns=columns)

'''
	-------------------------------------------
	Global
	-------------------------------------------
'''
def escapeStringForACEEditor(data_string):
	result = ""
	result = data_string.replace('`','\`')
	result = result.replace('${','\${')
	result = result.replace('}','\}')
	return result

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.isoformat()
		return serial
	raise TypeError("Type not serializable")
