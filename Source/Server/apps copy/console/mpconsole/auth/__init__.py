
import msal
import uuid
import flask
from flask import Blueprint, render_template, flash
from flask import current_app, url_for, render_template, request, redirect, session
from datetime import datetime

# HighCastle
from flask_login import login_user
from cryptography.fernet import Fernet
from mpconsole.app import db
from mpconsole.model import *
from mpconsole.mplogger import *

def construct_blueprint(auth_config: dict, application_root_uri: str = None) -> Blueprint:
	"""Get a blueprint for authentication, with routes at /auth/login and /auth/logout.
	
	Args:
		auth_config: dict containing auth config. Must contain keys:
			TENANT: AAD tenant aka directory, can be guid or name
			CLIENT_ID: Your application's client id aka "applicationID"
			CLIENT_SECRET: Your application's client secret aka "applicationKey"
			HTTPS_SCHEME: either 'https' or 'http', should always be 'https' in production
		application_root_uri: Where to redirect on successful authentication, defaults to flask.url_for('index')
	
	Returns:
		flask.Blueprint called 'auth'
	"""
	required_keys = {
		'TENANT', 
		'CLIENT_ID',
		'CLIENT_SECRET',
		'HTTPS_SCHEME'
	}
	intersection = required_keys & auth_config.keys()
	if len(intersection) != len(required_keys):
		missing_keys = required_keys - intersection
		raise ValueError('auth_config dict missing required keys: ' + ','.join(missing_keys))        
	
	bp = Blueprint('auth', __name__, template_folder='templates')

	# Register blueprint routes
	@bp.route('/ping')
	def ping():
		return '<h1>Hello, Auth blueprint</h1>'
	
	@bp.route("/login")
	def login():
		redirect_uri = url_for('.signin_oidc', _external=True, _scheme=auth_config['HTTPS_SCHEME'])
		session["state"] = str(uuid.uuid4())
		auth_url = _build_auth_url(
			auth_config=auth_config,
			redirect_uri=redirect_uri,
			state=session["state"])
		resp = flask.Response(status=307)
		resp.headers['location'] = auth_url
		return resp
	
	@bp.route("/signin-oidc")
	def signin_oidc():
		"""
		This is the re-direct from MS interactive authentication kicked off in the 'login' function
		Here, we get an authentication token for the app, and check the user has permissions (has a user role of at least read access)
		If successful, redirects to the home page of the application, by default a `url_for('index')` route
		"""
		app_root_uri = application_root_uri or url_for('main.landing')

		if request.args.get('state') != session.get("state"):
			#raise ValueError("State does not match")
			log_Info(f"[signin_oidc] State does not match")
			session.clear()
			flash("Your session token state did not match, please re-login.")
			return redirect(url_for('main.index'))
		
		# Authentication/Authorization failure
		if "error" in request.args:  
			log_Info(f"[signin_oidc] error in request.args")
			return render_template("auth_error.html", result=request.args, application_root_uri=app_root_uri)
		
		redirect_uri = url_for('.signin_oidc', _external=True, _scheme=auth_config['HTTPS_SCHEME'])
		code = request.args['code']        

		if request.args.get('code'):
			cache = _load_cache()
			result = _build_msal_app(auth_config=auth_config, cache=cache).acquire_token_by_authorization_code(
									 request.args['code'], scopes=["User.Read"], redirect_uri=redirect_uri)

			if "error" in result:
				log_Error(f"[signin_oidc] result = {result}")
				return render_template("auth_error.html", result=result, application_root_uri=app_root_uri)
			
			user = result.get("id_token_claims")
			
			# Not using AAD Roles, using roles defined from db
			#if not _has_read_access(user):
			#    result = {"error": "Authentication Failed", "error_description": "User does not have at least read access to this application."}
			#    return render_template("auth_error.html", result=result, application_root_uri=app_root_uri)
			
			session["oid_user"] = user
			_save_cache(cache)
			
		# Setup User from DB
		oun = session["oid_user"]["preferred_username"].split("@")
		mp_user = AdmUsers.query.filter(AdmUsers.user_id == oun[0] ).first()
		if mp_user is None:
			mp_user = AdmUsers()
			mp_user.user_id = oun[0]
			mp_user.user_pass = "NA"
			db.session.add(mp_user)
			db.session.commit()
		
		# Flask Login - Pass MacPatch User Account
		login_user(mp_user, True)
		session.permanent = True
		session['user'] = oun[0] # Required for MacPatch
		session['oid_user']['oun'] = oun[0]
		session['user_key'] = Fernet.generate_key().decode()

		recordLoginAndAssignIfNeeded(oun[0], 2)
		setLoginSessionInfo(mp_user.user_id)
		print(f"app_root_uri = {app_root_uri}")
		# Redirect to home page, authentication was successful
		current_app.logger.info(f"User authentication successful for {session['oid_user'].get('name', 'unknown')}")
		return redirect(app_root_uri)

	# somewhere to logout
	@bp.route("/logout")
	def logout():
		current_app.logger.info(f'Logout requested')
		session.clear()  # Wipe out user and its token cache from session
		logout_url = _build_logout_url(auth_config=auth_config)
		return redirect(logout_url)  # Also logout from your tenant's web session
	
	@bp.route("/logout-complete")
	def logout_complete():
		current_app.logger.info(f'Logout complete')
		app_root_uri = application_root_uri or url_for('index')
		return render_template("logout.html", application_root_uri=app_root_uri)

	return bp

# MacPatch Specific
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

# MacPatch Specific
def setLoginSessionInfo(user_id):
	# Role Order
	# (admin,autopkg,agentUpload,apiAccess)
	_role = (0,0,0,0)

	_account = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user_id).first()
	if _account:
		_role = (_account.admin,_account.autopkg,_account.agentUpload,_account.apiAccess)
	session['role'] = _role

def _build_auth_url(auth_config, redirect_uri = None, scopes=None, state=None):
	return _build_msal_app(auth_config).get_authorization_request_url(
		scopes = scopes or ['User.Read'],
		state = state or str(uuid.uuid4()),
		prompt = 'select_account',
		redirect_uri = redirect_uri or url_for("auth.signin_oidc", _external=True, _scheme=auth_config['HTTPS_SCHEME']))

def _build_logout_url(auth_config, redirect_url = None):
	#authority = _get_authority(auth_config['TENANT'])
	#post_logout_redirect_url = redirect_url or url_for('.logout_complete', _external=True, _scheme=auth_config['HTTPS_SCHEME'])
	#logout_url = f"{authority}/oauth2/v2.0/logout?post_logout_redirect_uri={post_logout_redirect_url}"
	#return logout_url
	return url_for('main.index')

def _build_msal_app(auth_config, cache=None):
	return msal.ConfidentialClientApplication(
		auth_config['CLIENT_ID'],
		authority = _get_authority(auth_config['TENANT']),
		client_credential=auth_config['CLIENT_SECRET'],
		token_cache=cache)

def _load_cache():
	cache = msal.SerializableTokenCache()
	if session.get("token_cache"):
		cache.deserialize(session["token_cache"])
	return cache

def _save_cache(cache):
	if cache.has_state_changed:
		session["token_cache"] = cache.serialize()

def _get_token_from_cache(auth_config, scope=None):
	cache = _load_cache()  # This web app maintains one cache per session
	cca = _build_msal_app(auth_config, cache=cache)
	accounts = cca.get_accounts()
	if accounts:  # So all account(s) belong to the current signed-in user
		result = cca.acquire_token_silent(scope, account=accounts[0])
		_save_cache(cache)
		return result

def _get_authority(tenant: str) -> str:
	return f"{tenant}"
	#return f'https://login.microsoftonline.com/{tenant}'

def _has_read_access(user: dict):
	return _has_admin_access(user) or _has_write_access(user) or any("READ" in role.upper() for role in user.get('roles', []))

def _has_write_access(user: dict):
	return _has_admin_access(user) or any("WRITE" in role.upper() for role in user.get('roles', []))

def _has_admin_access(user: dict):
	return any("ADMIN" in role.upper() for role in user.get('roles', []))
