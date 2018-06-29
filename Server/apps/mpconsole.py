#!/usr/bin/env python

import os
from flask_script import Manager, Command, Option, Server
from flask_migrate import Migrate
from mpdb import addDefaultData, addUnassignedClientsToGroup
from mpapi.extensions import db
import multiprocessing
from werkzeug.security import generate_password_hash

from mpconsole import create_app
from mpconsole.model import *

# Create app -----------------------------------------------------------------
app = create_app()
manager = Manager(app)


# Gunicorn -------------------------------------------------------------------
class GunicornServer(Command):
	"""Start GUNICORN Server"""
	description = 'Run the app within Gunicorn'

	def __init__(self, host='127.0.0.1', port=int(os.environ.get("PORT", 5000)), workers=2, daemon=False):
		self.port = port
		self.host = host
		self.workers = workers
		self.daemon = daemon

	def get_options(self):
		return [
			Option('-h', '--host', dest='host', default=self.host),
			Option('-p', '--port', dest='port', type=int, default=self.port),
			Option('--workers', dest='workers', type=int, default=self.workers),
			Option('--daemon', dest='daemon', action='store_true'),
		]

	def run(self, *args, **kwargs):
		from gunicorn.app.base import Application
		host = kwargs['host']
		port = kwargs['port']
		workers = multiprocessing.cpu_count() + 1
		daemon = kwargs['daemon']

		print("Starting gunicorn server on %s:%d ...\n " % (host, port))
		class FlaskApplication(Application):
			def init(self, parser, opts, args):
				return {
					'bind': '{0}:{1}'.format(host, port),
					'workers': workers,
					'daemon': daemon,
					'worker_class': 'gevent',
					'preload_app': True,
					'accesslog': '/opt/MacPatch/Server/logs/console_access.log',
					'errorlog': '/opt/MacPatch/Server/logs/console_error.log',
					'loglevel': 'info',
				}

			def load(self):
				return app

		FlaskApplication().run()

# DB Migrate -----------------------------------------------------------------
# Not Needed, this is done with the mpapi app
# manager.add_command('db', MigrateCommand)

@manager.command
def insert_data():
	_pass = generate_password_hash('*mpadmin*')
	db.session.add(AdmUsers(user_id="mpadmin", user_RealName="MPAdmin", user_pass=_pass, enabled='1'))
	db.session.commit()

@manager.command
def populateDB():
	print 'Add Default Data To Database'
	addDefaultData()
	print 'Default Data Added Database'

@manager.command
def migrateClientsToGroup():
	print 'Migrate Clients to Default Group'
	addUnassignedClientsToGroup()
	print 'Clients have been migrated to Default Group'

# Override default runserver with options from config.py
manager.add_command('runserver', Server(host=app.config['SRV_HOST'], port=app.config['SRV_PORT']) )

# Add gunicorn command to the manager
manager.add_command("gunicorn", GunicornServer())

if __name__ == '__main__':
	manager.run()
