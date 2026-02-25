from flask import redirect, url_for, render_template, current_app
from sqlalchemy.exc import SQLAlchemyError

from . import main
from mpconsole.app import login_manager
from mpconsole.model import *
from mpconsole.config import Config
from mpconsole.app_decorators import login_required

@login_manager.user_loader
def load_user(userid):
	if userid != 'None':
		try:
			admUsr = AdmUsers.query.get(int(userid))
			return admUsr
		except SQLAlchemyError:
			return AdmUsers()

@main.route('/')
def index():
	_conf = Config() # Just In Case the flask current app is not available
	return render_template('auth_welcome.html', allow_local=_conf.LOCAL_AUTH_ALLOWED)

@main.route('/landing')
@login_required
def landing():
    return redirect(url_for('dashboard.index'))