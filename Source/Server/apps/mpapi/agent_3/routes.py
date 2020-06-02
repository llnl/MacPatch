from flask import request
from flask_restful import reqparse
from datetime import datetime

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

# Agent Updates
class AgentInstall(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(AgentInstall, self).__init__()

	def post(self, client_id, agent_ver):
		try:

			ai = AgentInstall()
			setattr(ai, 'cuuid', client_id)
			setattr(ai, 'install_date', datetime.now())
			setattr(ai, 'agent_ver', agent_ver)
			db.session.add(ai)
			db.session.commit()

			return {"errorno": 0, "errormsg": 'none', "result": {}, 'signature': {}}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AgentConfigInfo][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500


# Add Routes Resources
agent_3_api.add_resource(AgentInstall,          '/agent/install/<string:client_id>/<string:agent_ver>')