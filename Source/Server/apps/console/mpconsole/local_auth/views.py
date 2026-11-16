from flask import render_template, flash, redirect, url_for, session, current_app
from flask_login import login_user, logout_user
from werkzeug.exceptions import HTTPException
from cryptography.fernet import Fernet

from . import local_auth
from . forms import LoginForm
from mpconsole.app import db
from mpconsole.model import *
from mpconsole.mputil import *
from mpconsole.mplogger import *
from mpconsole.mpldap import MPldap

# --------------------------------------------
# Routes
# --------------------------------------------

@local_auth.route("/login", methods=["GET", "POST"])
def login():
	form = LoginForm()
	if not form.validate_on_submit():
		return render_template("local_auth/login.html", form=form)

	formUserID = form.username.data
	log_Info(f"Begin login attempt for user {formUserID}")

	# Local database account, this includes the initial admin account
	# created with scripts/create_admin_account.py
	user = AdmUsers.query.filter(AdmUsers.user_id == formUserID).first()
	if user is not None and user.check_password(form.password.data):
		if accountIsEnabled(user.user_id):
			log_Info(f"Console user login sucessful for user {formUserID}")
			return completeLogin(user, 1)

		log_Error(f"User {formUserID} account is not enabled.")

	# Not a local db user, lets see if LDAP is enabled and try that
	elif current_app.config['LDAP_SRVC_ENABLED'] and ldapAuthenticate(formUserID, form.password.data):
		if accountIsEnabled(formUserID):
			if user is None:
				user = addUser(formUserID)

			log_Info(f"LDAP login sucessful for user {formUserID}")
			return completeLogin(user, 2)

		log_Error(f"Account {formUserID} exists but is disabled.")

	flash('Incorrect username or password.')
	log_Error(f"Failed login attempt for user {formUserID}")
	return render_template("local_auth/login.html", form=form)

@local_auth.route("/logout")
def logout():
	log("Log out user %s" % (session.get('user')))

	logout_user()
	session.clear()
	return redirect(url_for('main.index'))

@local_auth.errorhandler(Exception)
def handle_error(e):
	code = 500
	if isinstance(e, HTTPException):
		code = e.code

	return render_template('error.html', error=code, message=str(e))

# --------------------------------------------
# Helper methods
# --------------------------------------------

def completeLogin(user, user_type):
	# Log in with Flask-Login and set the session values MacPatch relies on
	login_user(user)
	session['user'] = user.user_id
	session['user_key'] = Fernet.generate_key().decode()
	recordLoginAndAssignIfNeeded(user.user_id, user_type)
	setLoginSessionInfo(user.user_id)
	return redirect(url_for('dashboard.index', username=user.user_id))

def ldapAuthenticate(user_id, password):
	log_Debug("Ldap is enabled.")
	mpLDAP = MPldap(current_app)
	# Seach the directory for user logging in
	foundUserDN = mpLDAP.findOUN(user_id)
	if foundUserDN is None:
		return False

	if mpLDAP.authOUN(foundUserDN, user_id, password):
		return True

	log_Error(f"{user_id} Failed to login to LDAP.")
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

def setLoginSessionInfo(user_id):

	# (admin,autopkg,agentUpload,apiAccess)
	_role = (0,0,0,0)

	_account = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _account:
		_role = (_account.admin,_account.autopkg,_account.agentUpload,_account.apiAccess)

	session['role'] = _role

def addUser(username):
	user = AdmUsers()
	user.user_id = username
	user.user_pass = "NA"
	db.session.add(user)
	db.session.commit()
	return user

