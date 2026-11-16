'''
	Console admin account helpers

	Shared by the flask CLI commands in cli.py and scripts/create_admin_account.py.
	All functions require an application context.
'''
import secrets
import string
from datetime import datetime
from werkzeug.security import generate_password_hash

from mpconsole.app import db
from mpconsole.model import AdmUsers, AdmUsersInfo

def generateStrongPassword(length=20):
	"""Generate a cryptographically secure random password"""
	alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_=+"
	return ''.join(secrets.choice(alphabet) for _ in range(length))

def getAdminAccount():
	"""Return the user_id of the first (oldest) enabled admin account, or None"""
	qAdm = AdmUsersInfo.query.filter(AdmUsersInfo.admin == 1, AdmUsersInfo.enabled == 1).order_by(AdmUsersInfo.rid.asc()).first()
	if qAdm is not None:
		return qAdm.user_id

	return None

def createAdminAccount(username='mpadmin', password=None, force=False):
	"""
	Create a database admin account with a hashed password

	Args:
		username: Admin username (default: mpadmin)
		password: Admin password (if None, generates random password)
		force: If True, recreate account even if it exists

	Returns:
		tuple: (success: bool, password: str, message: str)
	"""
	existing_user = AdmUsers.query.filter_by(user_id=username).first()
	existing_info = AdmUsersInfo.query.filter_by(user_id=username).first()

	if existing_user and not force:
		return False, None, f"User '{username}' already exists. Use --force to recreate."

	if password is None:
		password = generateStrongPassword()

	try:
		# Delete existing user if force flag is set
		if force:
			if existing_user:
				db.session.delete(existing_user)
			if existing_info:
				db.session.delete(existing_info)
			db.session.commit()

		admin_user = AdmUsers()
		admin_user.user_id = username
		admin_user.user_pass = generate_password_hash(password)
		db.session.add(admin_user)

		admin_info = AdmUsersInfo()
		admin_info.user_id = username
		admin_info.user_type = 1  # Database user
		admin_info.enabled = 1
		admin_info.admin = 1
		admin_info.autopkg = 1
		admin_info.agentUpload = 1
		admin_info.apiAccess = 1
		admin_info.number_of_logins = 0
		admin_info.last_login = datetime.now()
		db.session.add(admin_info)

		db.session.commit()
		return True, password, f"Admin account '{username}' created successfully."

	except Exception as e:
		db.session.rollback()
		return False, None, f"Error creating admin account: {str(e)}"
