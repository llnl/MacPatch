from flask import session
from . model import AdmUsersInfo, MpClientGroupAdmins, MpClientGroups

def localAdmin():
	qUsr = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == session['user']).first()
	if qUsr is not None:
		if qUsr.user_type == 0 and qUsr.enabled == 1:
			return True

	return False

def groupAdminRights(groupid):

	# Check if user is a local admin (user_type == 0)
	# Local admins should have access to all client groups
	if localAdmin():
		return True

	# Check if user has admin role (covers LDAP admins)
	# Admin role (session['role'][0] == 1) should have access to all client groups
	if adminRole():
		return True

	qUsrOwnwer = MpClientGroups.query.filter(MpClientGroups.group_id == groupid, MpClientGroups.group_owner == session['user']).first()
	if qUsrOwnwer is not None:
		return True

	qUsr = MpClientGroupAdmins.query.filter(MpClientGroupAdmins.group_admin == session['user'], MpClientGroupAdmins.group_id == groupid).first()
	if qUsr is not None:
		return True

	return False

def adminRole():
	_x = session['role']
	if _x[0] == 1:
		return True

	return False

def autopkgRole():
	_x = session['role']
	if _x[1] == 1:
		return True

	return False

def agentUploadRole():
	_x = session['role']
	if _x[2] == 1:
		return True

	return False

def apiRole():
	_x = session['role']
	if _x[3] == 1:
		return True

	return False
