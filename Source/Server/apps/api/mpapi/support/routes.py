from flask import request
from werkzeug.utils import secure_filename
from flask import current_app as app
from flask_mail import Message
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
from distutils.version import LooseVersion
import base64
import os
import shutil

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *
from .. wsresult import *
from .. shared.software import *

from flask_mail import Mail

parser = reqparse.RequestParser()

class SupportDataMessage(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SupportDataMessage, self).__init__()

	def post(self, client_id, hostname):

		req = request

		if 'file' in req.files:
			file = req.files['file']
			fileName = secure_filename(file.filename)
			basePath = os.path.join('/tmp', client_id)
			if os.path.exists(basePath):
				shutil.rmtree(basePath)
			os.mkdir(basePath)
			filePath = os.path.join(basePath, fileName)
			file.save(filePath)

			mail = Mail()
			mail.init_app(app)

			msg = Message("MacPatch - Support Data From {}".format(hostname), sender='mpprod01@llnl.gov', recipients=['macpatch-help@llnl.gov'])
			msg.body = "Log Capture From {} \n".format(client_id)

			with app.open_resource(filePath) as fp:
				msg.attach(fileName, "application/zip", fp.read())

			mail.send(msg)
			if os.path.exists(basePath):
				shutil.rmtree(basePath)

		return {"result": {}, "errorno": 200, "errormsg": ''}, 200

# Add Routes Resources
support_api.add_resource(SupportDataMessage,		'/support/data/<string:client_id>/<string:hostname>')