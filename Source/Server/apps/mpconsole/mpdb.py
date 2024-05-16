import uuid
import hashlib
import os.path
from datetime import datetime
from werkzeug.security import generate_password_hash
from . import db

from mpconsole.mputil import return_data_for_root_key, read_config_file
from . model import MpClientGroups, MpClient, MpClientGroupMembers, MpClientTasks
from . model import MpClientSettings, AdmUsers


basedir = os.path.abspath(os.path.dirname(__file__))

from sqlalchemy import *

'''
	Commands for mpconsole.py
'''
# Add Default Admin Account ----------------------------------------------------
def addDefaultAdminAccount():
	# Read from siteconfig file
	usr_dict = return_data_for_root_key('users')
	if 'admin' in usr_dict:
		adm_account = usr_dict['admin']
		if adm_account['enabled']:
			_pass = generate_password_hash(adm_account['pass'])
			db.session.add(AdmUsers(user_id=adm_account['name'], user_RealName="MPAdmin", user_pass=_pass, enabled='1'))
			db.session.commit()
		return True
	return False

# Upgrade Tasks ---------------------------------------------------------------
def addUnassignedClientsToGroup():
	# Check for config
	res0 = MpClientGroups.query.filter(MpClientGroups.group_name == 'Default').first()
	res1 = MpClient.query.all()
	res2 = MpClientGroupMembers.query.all()

	default_gid = 0
	if res0:
		default_gid = res0.group_id
	else:
		return

	clients_in_group = []
	for x in res2:
		clients_in_group.append(str(x.cuuid))

	for x in res1:
		if x.cuuid in clients_in_group:
			continue
		else:
			db.session.add(MpClientGroupMembers(group_id=default_gid, cuuid=x.cuuid))

	db.session.commit()
