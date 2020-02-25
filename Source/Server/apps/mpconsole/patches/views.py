from flask import render_template, request, session, redirect, url_for
from werkzeug.utils import secure_filename
from flask_security import login_required
from sqlalchemy import text, or_
from sqlalchemy.orm.session import make_transient

from flask_cors import cross_origin

import base64
import re
import uuid
import sys
import os
import hashlib
import shutil
import json

from datetime import datetime
from dateutil.parser import parse

from .  import patches
from .. import db
from .. model import *
from .. modes import *
from .. mplogger import *
from .. mputil import *
from .. aws import *

'''
----------------------------------------------------------------
Apple Patches
----------------------------------------------------------------
'''
@patches.route('/apple')
@login_required
def apple():
	aListCols = ApplePatch.__table__.columns

	return render_template('patches/patches_apple.html', data={}, columns=aListCols)

''' AJAX Request '''
@patches.route('/apple/list',methods=['GET'])
@login_required
@cross_origin()
def applePatchesList():
	aList = ApplePatch.query.join(ApplePatchAdditions, ApplePatch.supatchname == ApplePatchAdditions.supatchname).add_columns(
		ApplePatchAdditions.severity, ApplePatchAdditions.patch_state).order_by(ApplePatch.postdate.desc()).all()

	cols = ['akey', 'description', 'description64','osver_support', 'patch_state', 'patchname',
			'postdate', 'restartaction', 'severity','severity_int', 'supatchname', 'title', 'version']

	_results = []
	for r in aList:
		_dict = r[0].asDict
		_row = {}
		for col in cols:
			if col in _dict:
				_row[col] = _dict[col]

		_row['severity'] = r.severity
		_row['patch_state'] = r.patch_state
		_results.append(_row)


	return json.dumps({'data': _results}, default=json_serial), 200


@patches.route('/apple/state',methods=['POST'])
@login_required
def appleState():
	if localAdmin() or adminRole():
		suname = request.form.get('pk')
		state = request.form.get('value')

		patchAdds = ApplePatchAdditions.query.filter(ApplePatchAdditions.supatchname == suname).first()
		setattr(patchAdds, 'patch_state', state)
		db.session.commit()
		return json.dumps({}), 200
	else:
		log_Error("{} does not have permission to change apple patch state.".format(session.get('user')))
		return json.dumps({}), 401


@patches.route('/apple/severity',methods=['POST'])
@login_required
def appleSeverity():
	if localAdmin() or adminRole():
		suname = request.form.get('pk')
		severity = request.form.get('value')

		patchAdds = ApplePatchAdditions.query.filter(ApplePatchAdditions.supatchname == suname).first()
		setattr(patchAdds, 'severity', severity)
		db.session.commit()
		return json.dumps({}), 200
	else:
		log_Error("{} does not have permission to change apple patch state.".format(session.get('user')))
		return json.dumps({}), 401


@patches.route('/applePatchWizard/<akey>')
@login_required
def applePatchWizard(akey):

	cList = ApplePatch.query.filter(ApplePatch.akey == akey).first()
	# Base64 Encoded Description needs to be decoded and cleaned up
	desc = base64.b64decode(cList.description64).decode('utf-8')
	if "<!DOCTYPE" in desc or "<HTML>" in desc:
		desc = desc.replace("Data('","")
		desc = desc.replace("\\n", "")
		desc = desc.replace("\\t", "")
		desc = desc.replace("')", "")
		desc = desc.replace("<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">", "")
		desc = desc.replace("<meta http-equiv=\"Content-Style-Type\" content=\"text/css\">", "")
		desc = desc.replace("<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">", "")
		desc = desc.replace("<html>", "")
		desc = desc.replace("<head>", "")
		desc = desc.replace("<body>", "")
		desc = desc.replace("<title>", "")
		desc = desc.replace("</title>", "")
		desc = desc.replace("</html>", "")
		desc = desc.replace("</head>", "")
		desc = desc.replace("</body>", "")
		replaced = re.sub('<style([\S\s]*?)>([\S\s]*?)<\/style>', '', desc)
		setattr(cList,'description64',replaced)

	cListCols = ApplePatch.__table__.columns

	patchAdds = ApplePatchAdditions.query.filter(ApplePatchAdditions.supatchname == cList.supatchname).first()
	patchCrit = ApplePatchCriteria.query.filter(ApplePatchCriteria.supatchname == cList.supatchname).order_by(ApplePatchCriteria.type_order.asc()).all()
	patchCritLen = len(patchCrit)

	return render_template('patches/apple_patch_wizard.html', data=cList, columns=cListCols, dataAdds=patchAdds, dataCrit=patchCrit, dataCritLen=patchCritLen)

@patches.route('/applePatchWizard/update',methods=['POST'])
@login_required
def applePatchWizardUpdate():

	if localAdmin() or adminRole():
		critDict = dict(request.form)
		suname = request.form['supatchname']
		akey = request.form['akey']

		# Set / Update Values in MP Apple Patch Additions table
		patchAdds = ApplePatchAdditions.query.filter(ApplePatchAdditions.supatchname == request.form['supatchname']).first()
		setattr(patchAdds, 'patch_reboot', request.form['patch_reboot'])
		setattr(patchAdds, 'patch_install_weight', request.form['patchInstallWeight'])
		setattr(patchAdds, 'severity', request.form['patch_severity'])
		setattr(patchAdds, 'user_install', request.form['user_install'])
		db.session.commit()

		# Remove Criteria before adding new / updating
		ApplePatchCriteria.query.filter(ApplePatchCriteria.supatchname == request.form['supatchname']).delete()
		db.session.commit()

		for key in critDict:
			if "reqCri_Order_" in key:
				nid = str(str(critDict[key][0]).split("_")[-1])
				order = critDict[key][0]

				patchCrit = ApplePatchCriteria()
				setattr(patchCrit, 'puuid', akey)
				setattr(patchCrit, 'supatchname', suname)
				setattr(patchCrit, 'type', critDict["reqCri_type_" + nid][0])
				setattr(patchCrit, 'type_action', critDict["reqCri_type_action_" + nid][0])
				setattr(patchCrit, 'type_data', critDict["reqCri_type_data_" + nid][0])
				setattr(patchCrit, 'type_order', order)
				setattr(patchCrit, 'cdate', datetime.now())
				setattr(patchCrit, 'mdate', datetime.now())

				db.session.add(patchCrit)
				db.session.commit()

		log("{} updated apple patch {}({}).".format(session.get('user'), suname, akey))

	else:
		log_Error("{} does not have permission to update apple patch.".format(session.get('user')))

	return json.dumps({'data': {}}, default=json_serial), 200

''' AJAX Request '''
@patches.route('/apple/bulk/toQA',methods=['GET'])
@login_required
@cross_origin()
def migrateApplePatchesToQA():
	if localAdmin() or adminRole():
		query = ApplePatchAdditions.query.filter(ApplePatchAdditions.patch_state == 'Create').all()
		if query is not None:
			for row in query:  # all() is extra
				row.patch_state = 'QA'

		db.session.commit()
		return json.dumps({'data': {}}, default=json_serial), 200

	else:
		log_Error("{} does not have permission to migrate apple patch(s) to QA state.".format(session.get('user')))
		return json.dumps({'data': {}}, default=json_serial), 403

''' AJAX Request '''
@patches.route('/apple/bulk/toProd',methods=['GET'])
@login_required
@cross_origin()
def migrateApplePatchesToProd():
	if localAdmin() or adminRole():
		query = ApplePatchAdditions.query.filter(ApplePatchAdditions.patch_state == 'QA').all()
		if query is not None:
			for row in query:  # all() is extra
				row.patch_state = 'Production'

		db.session.commit()
		return json.dumps({'data': {}}, default=json_serial), 200

	else:
		log_Error("{} does not have permission to migrate apple patch(s) to Production state.".format(session.get('user')))
		return json.dumps({'data': {}}, default=json_serial), 403

'''
----------------------------------------------------------------
Custom Patches
----------------------------------------------------------------
'''
@patches.route('/custom')
@login_required
def custom():
	cList = MpPatch.query.order_by(MpPatch.mdate.desc()).all()
	cListCols = MpPatch.__table__.columns
	cListColsLimited = ['puuid', 'patch_name', 'patch_ver', 'bundle_id', 'description',
	'patch_severity', 'patch_state', 'patch_reboot', 'active', 'pkg_size', 'pkg_path', 'pkg_url', 'mdate']

	return render_template('patches/patches_custom.html', data={}, columns=cListColsLimited, columnsAll=cListCols)

''' AJAX Request '''
@patches.route('/custom/list',methods=['GET'])
@cross_origin()
def customList():

	_clist = MpPatch.query.order_by(MpPatch.mdate.desc()).all()
	_clistCols = ['puuid', 'patch_name', 'patch_ver', 'bundle_id', 'description',
				'patch_severity', 'patch_state', 'patch_reboot', 'active',
				'pkg_size', 'pkg_path', 'pkg_url', 'pkg_useS3', 'mdate']
	_results = []
	_aws = MPaws()
	for r in _clist:
		_dict = r.asDict
		_row = {}
		for col in _clistCols:
			_row[col] = _dict[col]

		if _row['pkg_useS3'] == 1:
			if current_app.config.get('USE_AWS_S3'):
				_row['pkg_url'] = getS3UrlForPatch(_row['puuid'])
			else:
				_row['pkg_url'] = ""

		_results.append(_row)

	return json.dumps({'data': _results}, default=json_serial), 200

@patches.route('/customPatchWizardAdd')
@login_required
def customPatchWizardAdd():

	cList = MpPatch()
	setattr(cList,'puuid',str(uuid.uuid4()))
	cListCols = MpPatch.__table__.columns

	return render_template('patches/custom_patch_wizard.html',data=cList, columns=cListCols,
							dataCrit={}, dataCritLen=0,
							hasOSArch=False, dataReq={})

@patches.route('/customPatchWizard/<puuid>')
@login_required
def customPatchWizard(puuid):

	patch = MpPatch.query.filter(MpPatch.puuid == puuid).first()
	patchCols = MpPatch.__table__.columns

	patchDict = patch.__dict__
	if patchDict['pkg_preinstall'] is not None:
			patchDict['pkg_preinstall'] = escapeStringForACEEditor(patchDict['pkg_preinstall'])
	if patchDict['pkg_postinstall'] is not None:
			patchDict['pkg_postinstall'] = escapeStringForACEEditor(patchDict['pkg_postinstall'])

	patchCrit = MpPatchesCriteria.query.filter(MpPatchesCriteria.puuid == puuid).order_by(MpPatchesCriteria.type_order.asc()).all()

	pathCritLst = []
	for crit in patchCrit:
		patchCritDict = crit.__dict__
		del patchCritDict['_sa_instance_state']
		del patchCritDict['rid']
		if patchCritDict['type'] == "Script":
			patchCritDict['type_data'] = escapeStringForACEEditor(patchCritDict['type_data'])

		pathCritLst.append(patchCritDict)

	patchCritLen = len(patchCrit)
	patchReq = MpPatchesRequisits.query.filter(MpPatchesRequisits.puuid_ref == puuid).all()

	_hasOSArch = False
	for cri in patchCrit:
		if cri.type == "OSArch":
			_hasOSArch = True
			break

	base_url = request.url_root

	if patch.pkg_useS3 == 1:
		aws = MPaws()
		patch.pkg_S3path = aws.getS3UrlForPatch(patch.puuid)

	return render_template('patches/custom_patch_wizard.html', data=patch, columns=patchCols, dataAlt=patchDict,
							dataCrit=patchCrit, dataCritLen=patchCritLen, dataCritAlt=pathCritLst,
							hasOSArch=_hasOSArch, dataReq=patchReq, baseurl=base_url)

''' AJAX Request '''
@patches.route('/customPatchWizard/update',methods=['POST'])
def customPatchWizardUpdate():
	# Get Patch ID
	try:
		req = request
		puuid = req.form['puuid']

		# Check Permissions
		if not localAdmin() and not adminRole():
			log_Error("{} does not have permission to change custom patch {}.".format(session.get('user'), puuid))
			return {'data': {}}, 403

		# Save File, returns path to file
		_file = None
		_fileData = None
		if "mainPatchFile" in request.files:
			_file = request.files['mainPatchFile']
			if request.form['pkg_useS3'] == '1':
				aws = MPaws()
				_fileData = aws.savePatchFileToTMP(puuid, _file)
				aws.uploadFileToS3(_fileData['filePath'],_fileData['fileURL'])
				shutil.rmtree(os.path.join('/tmp', request.form['puuid']))
			else:
				_fileData = savePatchFile(puuid, _file)

		critDict = dict(request.form)

		newPatch = False
		mpPatch = MpPatch.query.filter(MpPatch.puuid == puuid).first()
		if mpPatch is None:
			newPatch = True
			mpPatch = MpPatch()
		mpPatchCols = MpPatch.__table__.columns

		for key in critDict:
			for col in mpPatchCols:
				if col.name == key:
					_val = request.form[col.name]
					setattr(mpPatch, key, _val)
					continue

		# Save Patch Package Info
		if _fileData is not None:
			if _fileData['fileName'] is not None:
				setattr(mpPatch, 'pkg_name', os.path.splitext(_fileData['fileName'])[0])
				setattr(mpPatch, 'pkg_size', _fileData['fileSize'])
				setattr(mpPatch, 'pkg_hash', _fileData['fileHash'])
				setattr(mpPatch, 'pkg_path', _fileData['filePath'])
				setattr(mpPatch, 'pkg_url', _fileData['fileURL'])

		setattr(mpPatch, 'mdate', datetime.now())
		if newPatch:
			db.session.add(mpPatch)

		# Delete current criteria
		MpPatchesCriteria.query.filter(MpPatchesCriteria.puuid == puuid).delete()

		for key in critDict:
			if key.startswith('req_'):

				patchesCriteria = MpPatchesCriteria()
				setattr(patchesCriteria, 'puuid', puuid)
				if key == 'req_os_type':
					setattr(patchesCriteria, 'type', 'OSType')
					setattr(patchesCriteria, 'type_data', request.form[key])
					setattr(patchesCriteria, 'type_order', 1)
					db.session.add(patchesCriteria)
					continue

				if key == 'req_os_ver':
					setattr(patchesCriteria, 'type', 'OSVersion')
					setattr(patchesCriteria, 'type_data', request.form[key])
					setattr(patchesCriteria, 'type_order', 2)
					db.session.add(patchesCriteria)
					continue

				if key == 'req_os_arch':
					setattr(patchesCriteria, 'type', 'OSArch')
					setattr(patchesCriteria, 'type_data', request.form[key])
					setattr(patchesCriteria, 'type_order', 3)
					db.session.add(patchesCriteria)
					continue

			if key.startswith('reqCri_Order_'):
				formLst = key.split('_')
				nid = formLst[-1]
				norder = int(request.form['reqCri_Order_'+str(nid)])
				if norder <= 3:
					norder = norder + 3
				formData = request.form['reqCri_type_data_'+str(nid)]
				formType = request.form['reqCri_type_'+str(nid)]

				patchesCriteria = MpPatchesCriteria()
				setattr(patchesCriteria, 'puuid', puuid)
				setattr(patchesCriteria, 'type', formType)
				setattr(patchesCriteria, 'type_data', formData)
				setattr(patchesCriteria, 'type_order', norder)

				db.session.add(patchesCriteria)
				continue


		db.session.commit()
		log("{} updated custom patch {}.".format(session.get('user'), puuid))

	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		log_Error('Message: %s' % (e))
		return {'errorno': 500, 'errormsg': e, 'result': {}}, 500

	return {'data': {}}, 200

''' Private '''
def savePatchFile(puuid, file):

	result = {}
	result['fileName'] = None
	result['filePath'] = None
	result['fileURL']  = None
	result['fileHash'] = None
	result['fileSize'] = 0

	# Save uploaded files
	upload_dir = os.path.join(current_app.config["PATCH_CONTENT_DIR"], puuid)
	if not os.path.isdir(upload_dir):
		os.makedirs(upload_dir)

	if file is not None and len(file.filename) > 4:
		filename = secure_filename(file.filename)
		_file_path = os.path.join(upload_dir, filename)
		result['fileName'] = filename
		result['filePath'] = _file_path
		result['fileURL']  = os.path.join('/patches', puuid, filename)

		if os.path.exists(_file_path):
			log_Info('Removing existing file (%s)' % (_file_path))
			os.remove(_file_path)

		log_Info('Saving file to (%s)' % (_file_path))
		file.save(_file_path)

		md5 = hashlib.md5()
		with open(_file_path,'rb') as f: 
			for chunk in iter(lambda: f.read(8192), b''): 
				md5.update(chunk)

		result['fileHash'] = md5.hexdigest()
		result['fileSize'] = (os.path.getsize(_file_path)/float(1000))

	return result

def savePatchFileToTMP(puuid, file):

	result = {}
	result['fileName'] = None
	result['filePath'] = None
	result['fileURL']  = None
	result['fileHash'] = None
	result['fileSize'] = 0

	# Save uploaded files
	upload_dir = os.path.join('/tmp', puuid)
	if not os.path.isdir(upload_dir):
		os.makedirs(upload_dir)

	if file is not None and len(file.filename) > 4:
		filename = secure_filename(file.filename)
		_file_path = os.path.join(upload_dir, filename)
		result['fileName'] = filename
		result['filePath'] = _file_path
		result['fileURL']  = os.path.join('/patches', puuid, filename)

		if os.path.exists(_file_path):
			log_Info('Removing existing file (%s)' % (_file_path))
			os.remove(_file_path)

		log_Info('Saving file to (%s)' % (_file_path))
		file.save(_file_path)

		result['fileHash'] = hashlib.md5(open(_file_path, 'rb').read()).hexdigest()
		result['fileSize'] = (os.path.getsize(_file_path)/float(1000))

	return result


@patches.route('/custom/duplicate/<patch_id>',methods=['POST'])
@login_required
def customDuplicate(patch_id):

	if not localAdmin() and not adminRole():
		log_Error("{} does not have permission to duplicate custom patch.".format(session.get('user')))
		return json.dumps({'data': {}}, default=json_serial), 403


	qGet1 = MpPatch.query.filter(MpPatch.puuid == patch_id).first()
	if qGet1 is not None:
		make_transient(qGet1)

		_new_puuid = str(uuid.uuid4())
		_new_patch_name = "Copy_"+qGet1.patch_name
		qGet1.rid = None
		setattr(qGet1, 'puuid', _new_puuid)
		setattr(qGet1, 'patch_name', _new_patch_name)
		setattr(qGet1, 'patch_state', "Create")
		setattr(qGet1, 'active', "0")

		_pkg_path = qGet1.pkg_path
		_pkg_url = qGet1.pkg_url
		setattr(qGet1, 'pkg_path', _pkg_path.replace(patch_id, _new_puuid))
		setattr(qGet1, 'pkg_url', _pkg_url.replace(patch_id, _new_puuid))

		setattr(qGet1, 'cdate', datetime.now())
		setattr(qGet1, 'mdate', datetime.now())

		db.session.add(qGet1)

		# Duplicate patch criteria
		qGet2 = MpPatchesCriteria.query.filter(MpPatchesCriteria.puuid == patch_id).all()
		if qGet2 is not None:
			for x in qGet2:
				make_transient(x)
				x.rid = None
				setattr(x, 'puuid', _new_puuid)
				db.session.add(x)

		# Need to duplicate patch on file system
		try:
			_patch_dir0 = "/opt/MacPatch/Content/Web/patches/" + patch_id
			if os.path.exists(_patch_dir0):
				_patch_dir1 = "/opt/MacPatch/Content/Web/patches/" + _new_puuid
				copytree(_patch_dir0,_patch_dir1)
			else:
				log("{}, unable to duplicate custom patch {}({}). Directory does not exist".format(session.get('user'), qGet1.patch_name, patch_id))

		except OSError as e:
			log_Error("Error: %s - %s." % (e.filename,e.strerror))


		log("{} duplicate custom patch {}({}).".format(session.get('user'), qGet1.patch_name, patch_id))

	try:
		db.session.commit()
	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		message=str(e.args[0]).encode("utf-8")
		log_Error('Message: %s' % (message))

	return json.dumps({'data': {}}, default=json_serial), 200

@patches.route('/custom/delete',methods=['DELETE'])
@login_required
def customDelete():
	ids = request.form['patches']
	if not localAdmin() and not adminRole():
		log_Error("{} does not have permission to delete custom patch(s).".format(session.get('user')))
		return json.dumps({'data': {}}, default=json_serial), 403
	update_groups = []
	for puuid in ids.split(","):
		gids = removePatchFromPatchGroupsAlt(puuid)
		update_groups.extend(gids)
  
		qGet1 = MpPatch.query.filter(MpPatch.puuid == puuid).first()
		if qGet1 is not None:
			# Need to delete from file system
			try:
				if qGet1.pkg_useS3 == 1:
					aws = MPaws()
					aws.deleteS3PatchFile(qGet1.pkg_url)
				else:
					_patch_dir = "/opt/MacPatch/Content/Web/patches/" + puuid
					shutil.rmtree(_patch_dir)

			except OSError as e:
				log_Error("Error: %s - %s." % (e.filename,e.strerror))

			db.session.delete(qGet1)
			MpPatchesCriteria.query.filter(MpPatchesCriteria.puuid == puuid).delete()
			log("{} delete custom patch {}({}).".format(session.get('user'), qGet1.patch_name, puuid))

		try:
			db.session.commit()
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('Message: %s' % (message))
	
	# Update Patch Groups
	_update_groups = set(update_groups)
	for gid in _update_groups:
			patchGroupPatchesSave(gid)  

	return json.dumps({'data': {}}, default=json_serial), 200

def removePatchFromPatchGroupsAlt(patch_id):
	groups = []
	qGet = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_id == patch_id).all()
	if qGet is not None:
		for row in qGet:
			gID = row.patch_group_id
			groups.append(gID)
			db.session.delete(row)
			db.session.commit()
			#patchGroupPatchesSave(gID)

	return groups

''' AJAX Request '''
@patches.route('/custom/picker',methods=['GET'])
@cross_origin()
def customPatchPicker():

	query = MpPatch.query.filter(MpPatch.active == 1, or_(MpPatch.patch_state == "Production",MpPatch.patch_state == "QA")).order_by(MpPatch.patch_name.desc(),MpPatch.patch_ver.desc()).all()

	_results = []
	for p in query:
		row = {}
		row['puuid'] = p.puuid
		row['patch_name'] = p.patch_name
		row['patch_ver'] = p.patch_ver
		_results.append(row)

	return json.dumps({'data': _results}, default=json_serial), 200

''' AJAX Request '''
@patches.route('/custom/state',methods=['POST'])
@login_required
def customPatchState():
	patch_id = request.form.get('pk')
	state = request.form.get('value')

	if not localAdmin() and not adminRole():
		log_Error("{} does not have permission to change custom patch {} state.".format(session.get('user'), patch_id))
		return json.dumps({}), 403

	qGet = MpPatch.query.filter(MpPatch.puuid == patch_id).first()
	if qGet is not None:
		setattr(qGet, 'patch_state', state)
		db.session.commit()

	return json.dumps({}), 200

''' AJAX Request '''
@patches.route('/custom/active',methods=['POST'])
@login_required
def customPatchActive():
	patch_id = request.form.get('pk')
	active = request.form.get('value')

	if not localAdmin() and not adminRole():
		log_Error("{} does not have permission to change custom patch {} active state.".format(session.get('user'), patch_id))
		return json.dumps({}), 403

	qGet = MpPatch.query.filter(MpPatch.puuid == patch_id).first()
	if qGet is not None:
		setattr(qGet, 'active', active)
		db.session.commit()

	return json.dumps({}), 200

'''
----------------------------------------------------------------
Patch Groups
----------------------------------------------------------------
'''

'''
	This method is the main method used to display
	all of the patch groups
'''
@patches.route('/patchGroups')
@login_required
def patchGroups():

	cListColsLimited = [('name','Name'), ('id', 'ID'), ('type','Type'), ('user_id', 'Owner'), ('mdate', 'Last Saved')]

	gmList = PatchGroupMembers.query.filter(PatchGroupMembers.is_owner == '1').all()
	grpMembers = PatchGroupMembers.query.all()
	gmListAlt = MpPatchGroup.query.join(PatchGroupMembers, MpPatchGroup.id == PatchGroupMembers.patch_group_id).add_columns(
		PatchGroupMembers.is_owner, PatchGroupMembers.user_id).outerjoin(MpPatchGroupData,
		MpPatchGroup.id == MpPatchGroupData.pid).add_columns(MpPatchGroupData.mdate).filter(PatchGroupMembers.is_owner == '1').order_by(MpPatchGroupData.mdate.desc()).all()

	rows = []
	for x in gmListAlt:
		row = {}
		members = []

		gData = x[0].asDict
		gID = gData['id']
		row = gData
		# Build List of Group Members, that can edit group
		for g in grpMembers:
			if gID == g.patch_group_id:
				members.append(g.user_id)

		row['members'] = ','.join(members)
		row['owner'] = x.user_id
		row['mdate'] = x.mdate
		rows.append(row)

	return render_template('patches/patch_groups.html', data=rows, columns=cListColsLimited)

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.strftime('%Y-%m-%d %H:%M:%S')
		return serial
	raise TypeError("Type not serializable")

# TODO Change to use AJAX
@patches.route('/patchGroups/add')
@login_required
def patchGroupAdd():
	patchGroup = MpPatchGroup()
	setattr(patchGroup, 'id', str(uuid.uuid4()))
	patchGroupCols = MpPatchGroup.__table__.columns

	return render_template('patches/update_patch_group.html', data=patchGroup, columns=patchGroupCols, type="add")

# TODO Change to use AJAX
@patches.route('/patchGroups/edit/<id>')
@login_required
def patchGroupEdit(id):
	patchGroup = MpPatchGroup().query.filter(MpPatchGroup.id == id).first()
	patchGroupMember = PatchGroupMembers().query.filter(PatchGroupMembers.patch_group_id == id,
														PatchGroupMembers.is_owner == 1).first()
	patchGroupCols = MpPatchGroup.__table__.columns

	return render_template('patches/update_patch_group.html', data=patchGroup, columns=patchGroupCols, owner=patchGroupMember.user_id, type="edit")

# TODO Change to use AJAX
@patches.route('/patchGroups/update',methods=['POST'])
@login_required
def patchGroupUpdate():
	if not localAdmin() and not adminRole():
		log_Error("{} does not have permission to update patch group.".format(session.get('user')))
		return json.dumps({}), 403

	_add = False  # Add New Record vs Update
	_gid  = request.form['gid']
	_name = request.form['name']
	_type = request.form['type']
	if 'owner' in request.form:
		_owner = request.form['owner']
	else:
		_owner = None

	patchGroup = MpPatchGroup().query.filter(MpPatchGroup.id == _gid).first()
	if patchGroup is None:
		_add = True
		patchGroup = MpPatchGroup()

	if _owner:
		patchGroupMember = PatchGroupMembers().query.filter(PatchGroupMembers.patch_group_id == _gid,PatchGroupMembers.is_owner == 1).first()
		_owner = patchGroupMember.user_id
	else:
		patchGroupMember = PatchGroupMembers()
		usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()
		_owner = usr.user_id

	setattr(patchGroup, 'name', _name)
	setattr(patchGroup, 'type', _type)
	setattr(patchGroup, 'mdate', datetime.now())
	if _add:
		setattr(patchGroup, 'id', _gid)
		db.session.add(patchGroup)
		log("{} added new patch group {}.".format(session.get('user'), _name))
	else:
		log("{} updated patch group {}.".format(session.get('user'), _name))

	setattr(patchGroupMember, 'user_id', _owner)
	setattr(patchGroupMember, 'patch_group_id', _gid)
	setattr(patchGroupMember, 'is_owner', 1)

	if _add:
		db.session.add(patchGroupMember)

	db.session.commit()
	return redirect(url_for('patches.patchGroups'))

''' AJAX Request '''
@patches.route('/patchGroups/delete/<id>',methods=['POST'])
@login_required
def patchGroupDelete(id):
	qGroup = MpPatchGroup.query.filter(MpPatchGroup.id == id).first()
	groupName = qGroup.name
	if not localAdmin() and not adminRole() and not isOwnerOfGroup(id):
		log_Error("{} does not have permission to delete patch group {}.".format(session.get('user'), groupName))
		return json.dumps({}), 403

	# Remove Group
	db.session.delete(qGroup)
	PatchGroupMembers.query.filter(PatchGroupMembers.patch_group_id == id).delete()
	MpPatchGroupData.query.filter(MpPatchGroupData.pid == id).delete()
	MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == id).delete()
	db.session.commit()

	log_Error("{} deleted patch group {}.".format(session.get('user'), groupName))
	return json.dumps({'error': 0}), 200

'''
	------------------------------------
	Patch Group Admins
	------------------------------------
'''

'''
	This method opens the patch_group_admins.html file.
	It populates the table columns and supply the group id
'''
@patches.route('/patchGroups/admins/<id>')
@login_required
def patchGroupAdmins(id):
	columns = [('rid', 'Row ID', '0'),('user_id', 'User ID', '1'), ('is_owner', 'Owner', '1')]
	return render_template('patches/patch_group_admins.html', group_id=id, columns=columns)

''' AJAX Request '''
'''
	This method returns all of the admin members to a patch
	group. Its used by the patch_group_admins.html file
'''
@patches.route('/patchGroup/members/<id>')
def patchGroupMembers(id):
	rowCounter = 0
	patchGroupMembers = PatchGroupMembers.query.filter(PatchGroupMembers.patch_group_id == id).all()
	colsForQuery = ['rid', 'user_id', 'is_owner']

	_results = []
	for p in patchGroupMembers:
		rowCounter += rowCounter
		row = {}
		for x in colsForQuery:
			y = "p."+x
			row[x] = eval(y)

		_results.append(row)

	return json.dumps({'data': _results, 'total': rowCounter}, default=json_serial), 200

''' AJAX Request '''
'''
	This method will add or edit a patch group admin.
	Its used by the patch_group_admins.html file
'''
@patches.route('/patchGroup/member/add/<id>', methods=['POST'])
def patchGroupMemberAdd(id):
	if not localAdmin() and not adminRole() and not isOwnerOfGroup(id):
		log_Error("{} does not have permission to add patch group member.".format(session.get('user')))
		return json.dumps({}), 403

	pk = request.form.get('pk')
	user_id = request.form.get('value')

	patchGroupMember = PatchGroupMembers.query.filter(PatchGroupMembers.patch_group_id == id, PatchGroupMembers.user_id == user_id).first()
	if patchGroupMember is not None:
		# We only edit the non owners
		if patchGroupMember.is_owner != 1:
			setattr(patchGroupMember, 'user_id', user_id)
			setattr(patchGroupMember, 'is_owner', 0)
	else:
		patchGroupMember = PatchGroupMembers()
		setattr(patchGroupMember, 'patch_group_id', id)
		setattr(patchGroupMember, 'user_id', user_id)
		setattr(patchGroupMember, 'is_owner', 0)
		db.session.add(patchGroupMember)

	log("{} added patch group member {} to {}.".format(session.get('user'), user_id, id))
	db.session.commit()
	return json.dumps({'errorno': 0}), 200

''' AJAX Request '''
'''
	This method will delete a patch group admin but not
	the owner of the group.
	Its used by the patch_group_admins.html file
'''
@patches.route('/patchGroup/member/delete/<id>', methods=['POST'])
def patchGroupMemberDelete(id):
	if not localAdmin() and not adminRole() and not isOwnerOfGroup(id):
		log_Error("{} does not have permission to delete patch group member.".format(session.get('user')))
		return json.dumps({}), 403

	ids = request.form.get('ids')
	for rid, user_id in enumerate(ids.split(',')):
		qry = PatchGroupMembers.query.filter(PatchGroupMembers.patch_group_id == id, PatchGroupMembers.user_id == user_id).first()
		if qry is not None:
			if qry.is_owner == 0:
				log("{} deleted member {} from patch group {}.".format(session.get('user'), qry.user_id, id))
				db.session.delete(qry)
			else:
				log_Error("{} is a owner. An owner can not be deleted.".format(user_id))
				return json.dumps({'errorno': 0}), 403

	db.session.commit()
	return json.dumps({'errorno': 0}), 200

'''
	------------------------------------
	Patch Group Content
	------------------------------------
'''
@patches.route('/group/edit/<id>')
@login_required
def patchGroupContentEdit(id):
	patchGroup = MpPatchGroup().query.filter(MpPatchGroup.id == id).first()
	columns = [('state','state'), ('id','id'), ('suname', 'suname'), ('name','Patch'), ('title', 'Title'), ('version','Version'),
				('reboot', 'Reboot'), ('type', 'Patch Type'), ('severity','Severity'),
				('patch_state','Patch State'),  ('postdate','Post Date')]

	if patchGroup.type == 0:
		_pType = "'Production'"
	elif patchGroup.type == 1:
		_pType = "'Production','QA'"
	elif patchGroup.type == 2:
		_pType = "'Production','QA','Dev'"
	else:
		_pType = "'Production'"

	# Get Reboot Count
	sql = text("""SELECT DISTINCT b.*, IFNULL(p.patch_id,'NA') as Enabled
				FROM
					combined_patches_view b
				LEFT JOIN (
					SELECT patch_id FROM mp_patch_group_patches
					Where patch_group_id = '""" + id + """'
				) p ON p.patch_id = b.id
				WHERE b.patch_state IN (""" + _pType + """)""")

	result = db.engine.execute(sql)
	_results = []
	for v in result:
		_row = {}
		for column, value in list(v.items()):
			if column != 'patch_install_weight' and column != 'patch_reboot_override' and column != 'size' and column != 'active':
				if column == 'postdate':
					if value is not None:
						_row[column] = value.strftime("%Y-%m-%d %H:%M:00")
					else:
						_row[column] = "1970-01-01 12:00:00"
				else:
					# Check for \r\n in tile to clean up, javascript does not like it
					if isinstance(value, str):
						_row[column] = value.replace('\n', ' ').replace('\r', '')
					else:
						_row[column] = value

		_results.append(_row)

	_type = "false"
	if isOwnerOfGroup(id):
		_type = "true"

	return render_template('patches/patch_group_patches.html', name=patchGroup.name, pid=id, data=_results, columns=columns, isOwner=_type, groupID=id)

@patches.route('/group/list/<group_id>')
def patchGroupContent(group_id):

	args = request.args

	total = 0
	patchGroup = MpPatchGroup().query.filter(MpPatchGroup.id == group_id).first()
	columns = [('state','state'), ('id','id'), ('suname', 'suname'), ('name','Patch'), ('title', 'Title'), ('version','Version'),
				('reboot', 'Reboot'), ('type', 'Patch Type'), ('severity','Severity'),
				('patch_state','Patch State'),  ('postdate','Post Date')]

	if patchGroup.type == 0:
		_pType = "'Production'"
	elif patchGroup.type == 1:
		_pType = "'Production','QA'"
	elif patchGroup.type == 2:
		_pType = "'Production','QA','Dev'"
	else:
		_pType = "'Production'"

	sql = text("""SELECT DISTINCT b.*, IFNULL(p.patch_id , 'NA') as Enabled
				FROM
					combined_patches_view b
				LEFT JOIN (
					SELECT patch_id FROM mp_patch_group_patches
					Where patch_group_id = '""" + group_id + """'
				) p ON b.id = p.patch_id
				WHERE b.patch_state IN (""" + _pType + """)
				ORDER BY b.{} {};""".format(args['sort'], args['order'])
			   )

	result = db.engine.execute(sql)
	_results = []
	for v in result:
		_row = {}
		for column, value in list(v.items()):
			if column != 'patch_install_weight' and column != 'patch_reboot_override' and column != 'size' and column != 'active':
				if column == 'postdate':
					if value is not None:
						_row[column] = value.strftime("%Y-%m-%d %H:%M:00")
					else:
						_row[column] = "1970-01-01 12:00:00"
				elif column == 'Enabled':
					if value == 'NA':
						_row['state'] = 0
					else:
						_row['state'] = 1
				else:
					# Check for \r\n in tile to clean up, javascript does not like it
					if isinstance(value, str):
						_row[column] = value.replace('\n', ' ').replace('\r', '')
					else:
						_row[column] = value

		_results.append(_row)

	return json.dumps({'data': _results, 'total': total}, default=json_serial), 200

@patches.route('/group/add/<group_id>/<patch_id>')
@login_required
def patchGroupContentAdd(group_id, patch_id):
	if not localAdmin() and not adminRole() and not isOwnerOfGroup(group_id):
		log_Error("{} does not have permission to add content to patch group {}.".format(session.get('user'), group_id))
		return json.dumps({}), 403

	qry = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id,
											MpPatchGroupPatches.patch_id == patch_id).first()
	if qry is None:
		log("{} added patch {} to patch group {}.".format(session.get('user'), patch_id, group_id))
		patchGroupPatch = MpPatchGroupPatches()
		setattr(patchGroupPatch, 'patch_group_id', group_id)
		setattr(patchGroupPatch, 'patch_id', patch_id)
		db.session.add(patchGroupPatch)
		db.session.commit()

	return json.dumps({'error': 0}), 200

@patches.route('/group/add/bulk/<group_id>', methods=['POST'])
@login_required
def patchGroupContentAddBulk(group_id):
	if not localAdmin() and not adminRole() and not isOwnerOfGroup(group_id):
		log_Error("{} does not have permission to add bulk content to patch group {}.".format(session.get('user'), group_id))
		return json.dumps({}), 403

	dataStr = request.data
	data = json.loads(dataStr)

	for patch_id in data:
		qry = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id,
												MpPatchGroupPatches.patch_id == patch_id).first()
		if qry is None:
			log("{} added patch {} to patch group {}.".format(session.get('user'), patch_id, group_id))
			qryAdd = MpPatchGroupPatches()
			setattr(qryAdd, 'patch_group_id', group_id)
			setattr(qryAdd, 'patch_id', patch_id)
			db.session.add(qryAdd)

	db.session.commit()
	return json.dumps({'errorno': 0}), 200

@patches.route('/group/remove/<group_id>/<patch_id>')
def patchGroupContentDel(group_id, patch_id):
	if not localAdmin() and not adminRole() and not isOwnerOfGroup(group_id):
		log_Error("{} does not have permission to remove content from patch group {}.".format(session.get('user'), group_id))
		return json.dumps({}), 403

	patchGroupPatch = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id,
														MpPatchGroupPatches.patch_id == patch_id).first()
	if patchGroupPatch is not None:
		log("{} removed patch {} from patch group {}.".format(session.get('user'), patch_id, group_id))
		db.session.delete(patchGroupPatch)
		db.session.commit()

	return json.dumps({'error': 0}), 200

''' AJAX Request '''
'''
	This method will delete a patch group admin but not
	the owner of the group.
	Its used by the patch_group_admins.html file
'''
@patches.route('/group/save/<group_id>')
def patchGroupPatchesSave(group_id):
	if not localAdmin() and not adminRole() and not isOwnerOfGroup(group_id):
		log_Error("{} does not have permission to save content for patch group {}.".format(session.get('user'), group_id))
		return json.dumps({}), 403

	_now = datetime.now()
	dts = _now.strftime('%Y%m%d%H%M%S')

	_patchData = {}
	_patchData['rev'] = str(dts)
	_patchData['AppleUpdates'] = []
	_patchData['CustomUpdates'] = []

	_patchGroupPatches = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id).all()
	if _patchGroupPatches is not None:
		for p in _patchGroupPatches:
			row = {}
			patch = patchDataForPatchID(p.patch_id)
			if patch is None:
				# Patch ID no longer exists, delete it from all
				# patch groups
				removePatchFromPatchGroups(p.patch_id)
				continue
			else:
				if patch['type'] == "Apple":
					row["name"] = patch['suname']
					row["patch_id"] = patch['id']
					row["baseline"] = "0"
					row["patch_install_weight"] = patch['patch_install_weight']
					row["patch_reboot_override"] = patch['patch_reboot_override']
					row["severity"] = patch['severity']
					row["hasCriteria"] = applePatchHasCriteria(patch['id'])
					_patchData['AppleUpdates'].append(row)
					continue
				else:
					row["patch_id"] = patch['id']
					row["patch_install_weight"] = patch['patch_install_weight']
					row["severity"] = patch['severity']
					row["patches"] = customDataForPatchID(patch['id'])
					_patchData['CustomUpdates'].append(row)
					continue

	isNew=False
	pData = MpPatchGroupData.query.filter(MpPatchGroupData.pid == group_id).first()
	if pData is None:
		isNew=True
		pData = MpPatchGroupData()

	jsonData = json.dumps(_patchData)
	setattr(pData, 'rev', dts)
	setattr(pData, 'hash', hashlib.md5(jsonData.encode('utf-8')).hexdigest())
	setattr(pData, 'data', jsonData)
	setattr(pData, 'data_type', "JSON")
	setattr(pData, 'mdate', _now)

	if isNew:
		setattr(pData, 'pid', group_id)
		db.session.add(pData)

	log("{} saved content for patch group {}.".format(session.get('user'), group_id))
	db.session.commit()
	return json.dumps({'errorno': 0}), 200

# Private
def patchDataForPatchID(patch_id):
	sql = text("SELECT * from combined_patches_view Where id = :patchID")
	result = db.engine.execute(sql, patchID=patch_id)
	_results = []
	for v in result:
		_results.append(dict(v))

	if len(_results) < 1:
		return None

	return _results[0]

# Private
def applePatchHasCriteria(patch_id):
	crit = ApplePatchCriteria.query.filter(ApplePatchCriteria.puuid == patch_id).all()
	if crit is not None:
		return "TRUE"
	else:
		return "FALSE"

# Private
def customDataForPatchID(patch_id):
	_results = []
	patches = MpPatch.query.filter(MpPatch.puuid == patch_id).all()
	if patches is not None:
		for p in patches:
			row = {}
			row["name"] = p.patch_name
			row["hash"] = p.pkg_hash
			row["preinst"] = b64EncodeAsString(p.pkg_preinstall, 'NA')
			row["postinst"] = b64EncodeAsString(p.pkg_postinstall,'NA')
			row["env"] = p.pkg_env_var or "NA"
			row["reboot"] = p.patch_reboot
			row["type"] = "1"
			row["url"] = p.pkg_url or "NA"
			row["size"] = p.pkg_size
			row["baseline"] = "0"
			_results.append(row)

	return _results

# Private
def removePatchFromPatchGroups(patch_id):
	# This will delete a missing patch from all patch groups
	qry = MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_id == patch_id).all()
	if qry is not None:
		for q in qry:
			db.session.delete(q)
		db.session.commit()

'''
----------------------------------------------------------------
Patch Status
----------------------------------------------------------------
'''
@patches.route('/required')
@login_required
def requiredList():
	columns = [('cuuid', 'Client ID', '0'), ('patch', 'Patch', '1'), ('description', 'Description', '1'),
				('restart', 'Reboot', '1'), ('hostname', 'HostName', '1'), ('ipaddr', 'IP Address', '1'),
				('osver', 'OS Version', '1'), ('type', 'Type', '1'),('date', 'Date', '1')]

	return render_template('patches/patches_detected.html', columns=columns, pageTitle="Detected Patches")

''' AJAX Route '''
@patches.route('/required/<limit>/<offset>/<search>/<sort>/<order>')
def requiredListPaged(limit,offset,search,sort,order):
	# This has to be cleaned up
	total = 0
	getNewTotal = True
	if 'my_search_name' in session:
		if session['my_search_name'] == 'requiredList':
			if 'my_search' in session and 'my_search_total' in session:
				if session['my_search'] == search:
					getNewTotal = False
					total = session['my_search_total']
	else:
		session['my_search_name'] ='requiredList'
		session['my_search_total'] = 0
		session['my_search'] = None

	# Query for Data
	qResult = requiredQuery(search, int(offset), int(limit), sort, order, getNewTotal)

	# Result is a tuple, records = 0, rowCount = 1
	_result = qResult[0]

	# Parse results, and create list for json result
	_results = []
	for v in _result:
		_row = {}
		for column, value in list(v.items()):
			_row[column] = value
		_results.append(_row)

	session['my_search_name'] = 'requiredList'

	if getNewTotal:
		total = qResult[1]
		session['my_search_total'] = total
		session['my_search'] = search

	return json.dumps({'data': _results, 'total': total}, default=json_serial), 200

def requiredQuery(filterStr='undefined', page=0, page_size=0, sort='date', order='desc', getCount=True):

	columns = [('cuuid', 'Client ID', '0'), ('patch', 'Patch', '1'), ('description', 'Description', '1'),
				('restart', 'Reboot', '1'), ('hostname', 'HostName', '1'), ('ipaddr', 'IP Address', '1'),
				('osver', 'OS Version', '1'), ('type', 'Type', '1'),('date', 'Date', '1')]

	if sort == 'undefined':
		sort = 'date'
	if order == 'undefined':
		sort = 'desc'

	# Define Sort and Order By
	order_by_str = sort + ' ' + order

	sql0 = None
	sql1 = None
	res1 = None

	filterStr = str(filterStr)
	#offset = page * page_size
	offset = page

	if filterStr == 'undefined' or len(filterStr) <= 0:
		# Query for All Records, sql0 is used for count, sql1 is the query for paging
		sql0 = text("""SELECT date FROM mp_client_patches_full_view""")
		sql1 =	f"SELECT v.*, c.hostname, c.ipaddr, c.osver FROM mp_client_patches_full_view v " \
				f"Left Join mp_clients c ON c.cuuid = v.cuuid " \
				f"ORDER BY {order_by_str} LIMIT {str(offset)}, {str(page_size)}"

	else:
		# Query used when searching, sql0 is not used for count since search is the total
		isFirst = True
		whereStr = 'WHERE'
		for col in columns:

			if col[2] == '1':
				hasDate = isDateString(filterStr, True)
				if 'date' in col[0]:
					if not hasDate:
						continue

				if isFirst:
					whereStr = whereStr + " " + col[0] + " like '%" + filterStr + "%'"
					isFirst = False
				else:
					whereStr = whereStr + " OR " + col[0] + " like '%" + filterStr + "%'"

		sql0 = f"SELECT v.*, c.hostname, c.ipaddr, c.osver FROM mp_client_patches_full_view v " \
			   f"Left Join mp_clients c ON c.cuuid = v.cuuid " \
			   f"{whereStr}"
		sql0 = text(sql0)

		sql1 =  f"SELECT v.*, c.hostname, c.ipaddr, c.osver FROM mp_client_patches_full_view v "\
					f"Left Join mp_clients c ON c.cuuid = v.cuuid " \
					f"{whereStr} "\
					f"ORDER BY {order_by_str}  LIMIT {str(offset)} , {str(page_size)}"


	recCounter1 = 0
	recCounter2 = 0
	# Execute the SQL statement(s)
	if sql0 is not None:
		res1 = db.engine.execute(sql0)
		recCounter1 = res1.rowcount

	if sql1 is not None:
		result = db.engine.execute(text(sql1))
		recCounter2 = result.rowcount

	# Return tuple, query results and a record count
	return (result, recCounter1, recCounter2)

def isDateString(string, fuzzy=False):
	"""
	Return whether the string can be interpreted as a date.
	:param string: str, string to check for date
	:param fuzzy: bool, ignore unknown tokens in string if True
	"""
	try:
		parse(string, fuzzy=fuzzy)
		return True
	except ValueError:
		return False

@patches.route('/installed')
@login_required
def installedList():
	columns = [('cuuid','Client ID','0'),('patch','Patch','0'),('patch_name','Patch Name','1'),('hostname','HostName','1'),('ipaddr','IP Address','1'),
	('osver','OS Version','1'),('type','Type','1'),('mdate','Install Date','1')]

	return render_template('patches/patches_installed.html', columns=columns, pageTitle="Installed Patches")

''' AJAX Route '''
@patches.route('/installed/<limit>/<offset>/<search>/<sort>/<order>')
def installedListPaged(limit,offset,search,sort,order):
	total = 0
	getNewTotal = True
	if 'my_search_name' in session:
		if session['my_search_name'] == 'installedList':
			if 'my_search' in session and 'my_search_total' in session:
				if session['my_search'] == search:
					getNewTotal = False
					total = session['my_search_total']
	else:
		session['my_search_name'] ='installedList'
		session['my_search_total'] = 0
		session['my_search'] = None

	colsForQuery = ['cuuid', 'patch', 'patch_name', 'type', 'mdate']
	qResult = installedQuery(search, int(offset), int(limit), sort, order, getNewTotal)
	if qResult is not None:
		query = qResult[0]
	else:
		query = []

	session['my_search_name'] = 'installedList'

	if getNewTotal:
		total = qResult[1]
		session['my_search_total'] = total
		session['my_search'] = search

	_results = []
	for p in query:
		row = {}
		for x in colsForQuery:
			y = "p[0]."+x
			if x == 'mdate':
				row[x] = eval(y)
			elif x == 'type':
				row[x] = eval(y).title()
			else:
				row[x] = eval(y)

		row['hostname'] = p.hostname
		row['ipaddr'] = p.ipaddr
		row['osver'] = p.osver
		_results.append(row)

	return json.dumps({'data': _results, 'total': total}, default=json_serial), 200

def installedQuery(filterStr='undefined', page=0, page_size=0, sort='mdate', order='desc', getCount=True):
	clientCols = ['hostname','osver','ipaddr']

	if sort == 'undefined':
		sort = 'mdate'
	if order == 'undefined':
		sort = 'desc'

	order_by_str = sort + ' ' + order
	if sort in clientCols:
		order_by_str = 'mp_clients_' + order_by_str
	else:
		order_by_str = 'mp_installed_patches.' + order_by_str

	if filterStr == 'undefined' or len(filterStr) <= 0:
		query = MpInstalledPatch.query.join(MpClient, MpClient.cuuid == MpInstalledPatch.cuuid).add_columns(
			MpClient.hostname, MpClient.osver, MpClient.ipaddr).order_by(text(order_by_str))
	else:
		query = MpInstalledPatch.query.join(MpClient, MpClient.cuuid == MpInstalledPatch.cuuid).add_columns(
			MpClient.hostname, MpClient.osver, MpClient.ipaddr).filter(or_(MpInstalledPatch.patch.contains(filterStr),
																		MpInstalledPatch.patch_name.contains(filterStr),
																		MpInstalledPatch.type.contains(filterStr),
																		MpClient.hostname.contains(filterStr),
																		MpClient.ipaddr.contains(filterStr))).order_by(text(order_by_str))

	# count of rows
	if getCount:
		rowCounter = query.count()
	else:
		rowCounter = 0

	if page_size:
		query = query.limit(page_size)
	if page:
		query = query.offset(page)

	return (query, rowCounter)


''' Global '''
def isOwnerOfGroup(id):
	usr = AdmUsers.query.filter(AdmUsers.rid == session.get('user_id')).first()

	if usr:
		pgroup = PatchGroupMembers.query.filter(PatchGroupMembers.patch_group_id == id,
												PatchGroupMembers.is_owner == 1).first()
		if pgroup:
			if pgroup.user_id == usr.user_id:
				return True
			else:
				return False

	return False

def getDoc(col_obj):
	return col_obj.doc

def daysFromDate(now,date):
	x = now - date
	return x.days

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.strftime('%Y-%m-%d %H:%M:%S')
		return serial
	

def escapeStringForACEEditor(data_string):
	result = ""
	result = data_string.replace('`','\`')
	result = result.replace('${','\${')
	result = result.replace('}','\}')
	return result
