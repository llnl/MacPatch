from flask import session
from . model import AdmUsers, AdmUsersInfo, MpClientGroupAdmins, MpClientGroups, PatchGroupMembers

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

def _currentUser():
	return AdmUsers.query.filter(AdmUsers.rid == session.get('_user_id')).first()

def isClientGroupOwner(group_id):
	"""True if the user owns the client group, or is the main console admin (user_type 0)"""
	usr = _currentUser()
	if usr is None:
		return False

	usrInf = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == session.get('user')).first()
	if usrInf is not None and usrInf.user_type == 0:
		return True

	group = MpClientGroups.query.filter(MpClientGroups.group_id == group_id).first()
	return group is not None and group.group_owner == usr.user_id

def isPatchGroupOwner(group_id):
	"""True if the user is the owner of the patch group"""
	usr = _currentUser()
	if usr is None:
		return False

	owner = PatchGroupMembers.query.filter(PatchGroupMembers.patch_group_id == group_id, PatchGroupMembers.is_owner == 1).first()
	return owner is not None and owner.user_id == usr.user_id
