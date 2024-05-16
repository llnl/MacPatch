from flask import render_template, flash, redirect, url_for, request, session, current_app
from flask_login import login_user, logout_user
from werkzeug.exceptions import HTTPException

from . import auth
from . forms import LoginForm
from mpconsole.app import db
from mpconsole.model import *
from mpconsole.mputil import *
from mpconsole.mplogger import *
from mpconsole.mpldap import MPldap



@auth.route("/login", methods=["GET", "POST"])
def login():
	form = LoginForm()
	if form.username.data is not None:
		formUserID = form.username.data
		log_Info(f"Begin login attempt for user {formUserID}")
	else:
		log_Error("Form data is incomplete.")
		return render_template("login.html", form=form)

	# Read from siteconfig file
	_localAdm = return_data_for_root_key('users')

	tryLocalAdmin = False
	if 'admin' in _localAdm:
		tryLocalAdmin = _localAdm['admin']['enabled']
		log_Debug("Local admin enabled: {}".format(tryLocalAdmin))

	if form.validate_on_submit():
		# Check if the user exists in the db
		user = AdmUsers.query.filter(AdmUsers.user_id == formUserID).first()
		if tryLocalAdmin:
			_lUser = _localAdm['admin']['name']
			_lPass = _localAdm['admin']['pass']
			if formUserID == _lUser:
				if _lPass == form.password.data:
					if user is None:
						user = AdmUsers()
						user.user_id = formUserID
						user.user_pass = "NA"
						db.session.add(user)
						db.session.commit()

						makeUserAdmin(user.user_id, 0)

					login_user(user)
					session['user'] = formUserID
					recordLoginAndAssignIfNeeded(user.user_id, 0)
					setLoginSessionInfo(user.user_id)

					log_Info(f"Local admin login sucessful for user {formUserID}")
					return redirect(url_for('dashboard.index', username=user.user_id))
		
		# Check if user is local db user
		if user is not None and user.check_password(form.password.data):
			if accountIsEnabled(user.user_id):
				login_user(user)
				session['user'] = formUserID
				recordLoginAndAssignIfNeeded(user.user_id, 1)
				setLoginSessionInfo(user.user_id)

				log_Info(f"Console user login sucessful for user {formUserID}")
				return redirect(url_for('dashboard.index', username=user.user_id))
			else:
				log_Error(f"User {formUserID} account is not enabled.")
		
		# Not a local db user, lets see if LDAP is enabled and try that
		else:
			if current_app.config['LDAP_SRVC_ENABLED']:
			# LDAP is enabled
				log_Debug("Ldap is enabled.")
				# Init LDAP class
				mpLDAP = MPldap(current_app)
				# Seach the directory for user logging in
				foundUserDN = mpLDAP.findOUN(formUserID)

				if foundUserDN is not None:
					# User was found in the directory 
					# Lets try the auth for the user logging in
					if mpLDAP.authOUN(foundUserDN, formUserID, form.password.data):
						# LDAP Login Using the user DN passed
						if accountExists(formUserID):
							# The UserID Exists in MacPatch DB
							_usrActIsEnabled = accountIsEnabled(formUserID)
							if _usrActIsEnabled:
								# Account is enabled
								session['user'] = formUserID
								login_user(user)
								recordLoginAndAssignIfNeeded(user.user_id, 2)
								setLoginSessionInfo(user.user_id)
								log_Info(f"LDAP login sucessful for user {formUserID}")

								return redirect(url_for('dashboard.index', username=user.user_id))
							else:
								log_Error(f"Account {formUserID} exists but is disabled.")

						else:
							# The UserID does not exists, create and login
							user = addUser(formUserID)
							login_user(user)
							recordLoginAndAssignIfNeeded(user.user_id, 2)
							setLoginSessionInfo(user.user_id)
							session['user'] = form.username.data
						
							log_Info(f"LDAP login sucessful for user {formUserID}")
							return redirect(url_for('dashboard.index', username=user.user_id))
					else:
						# LDAP Login Using the user DN failed
						log_Error(f"{formUserID} Failed to login to LDAP.")
						

		flash('Incorrect username or password.')
		log_Error(f"Failed login attempt for user {form.username.data}")

	return render_template("login.html", form=form)


def accountExists(user_id):
	_account = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _account:
		return True

	return False

def accountIsEnabled(user_id):
	_account = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _account:
		# Need to Update
		_enabled = _account.enabled
		if _enabled == 0:
			return False

	return True

def recordLoginAndAssignIfNeeded(user_id,user_type):
	_account = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _account:
		# Need to Update
		_logins = _account.number_of_logins + 1
		setattr(_account, 'last_login', datetime.now())
		setattr(_account, 'number_of_logins', _logins)

	else:
		# Add Info
		_account = AdmUsersInfo()
		setattr(_account, 'user_id', user_id)
		setattr(_account, 'user_type', user_type)
		setattr(_account, 'last_login', datetime.now())
		setattr(_account, 'number_of_logins', 1)
		setattr(_account, 'enabled', 1)
		db.session.add(_account)

	db.session.commit()
	return

def makeUserAdmin(user_id, user_type):
	_account = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _account is None:
		# Add Account and Set as Admin
		_account = AdmUsersInfo()
		setattr(_account, 'user_id', user_id)
		setattr(_account, 'user_type', user_type)
		setattr(_account, 'last_login', datetime.now())
		setattr(_account, 'number_of_logins', 0)
		setattr(_account, 'enabled', 1)
		setattr(_account, 'admin', 1)
		setattr(_account, 'autopkg', 1)
		setattr(_account, 'agentUpload', 1)
		setattr(_account, 'apiAccess', 1)
		db.session.add(_account)

def setLoginSessionInfo(user_id):

	# (admin,autopkg,agentUpload,apiAccess)
	_role = (0,0,0,0)

	_account = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _account:
		_role = (_account.admin,_account.autopkg,_account.agentUpload,_account.apiAccess)

	session['role'] = _role

# ----
# Helper methods
# ----

def addUser(username):
	user = AdmUsers()
	user.user_id = username
	user.user_pass = "NA"
	db.session.add(user)
	db.session.commit()
	return user

@auth.route("/logout")
def logout():
	log("Log out user %s" % (session['user']))

	logout_user()
	session.clear()
	return redirect(url_for('main.index'))

@auth.errorhandler(Exception)
def handle_error(e):
	code = 500
	if isinstance(e, HTTPException):
		code = e.code

	return render_template('error.html', error=code, message=str(e))
