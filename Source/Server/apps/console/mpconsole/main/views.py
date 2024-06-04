from flask import redirect, url_for
from flask_login import login_required
from sqlalchemy.exc import SQLAlchemyError

from . import main
from mpconsole.app import login_manager
from mpconsole.model import *

@login_manager.user_loader
def load_user(userid):
	if userid != 'None':
		try:
			admUsr = AdmUsers.query.get(int(userid))
			return admUsr
		except SQLAlchemyError:
			return AdmUsers()

@main.route('/')
@login_required
def index():
	return redirect(url_for('dashboard.index'))