from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

# Client AV Data Collection
class AVDefsData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(AVDefsData, self).__init__()

	def post(self, engine):

		try:
			r = request
			_jdata = request.get_json(silent=True)
			#_defs = _jdata['defs']
			print(_jdata)


			#if not isValidSignature(self.req_signature, cuuid, request.data, self.req_ts):
			#	log_Error('[AVData][Post]: Failed to verify Signature for client (' + cuuid + ')')
			#	return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			addNew=False
			curDefs=None
			curDefsRev=None
			q_task = AvDefs.query.filter(AvDefs.current == 1).first()
			if q_task is not None:
				curDefs = q_task.defs_date_str.split('-')[0]
				curDefsRev = q_task.defs_date_str.split('-')[1]

			if curDefs is not None:
				_defs = _jdata["defDate"].split('-')[0]
				_defsRev = _jdata["defDate"].split('-')[1]
				if _defs == curDefs:
					# Equal, check rev and see if it needs updating
					if _defsRev > curDefsRev:
						self.changeCurrentToNot()
						addNew=True
				elif _defs > curDefs:
					self.changeCurrentToNot()
					addNew = True
			else:
				addNew=True


			if addNew == True:
				av_new12 = AvDefs()
				_sep12 = _jdata['sep12']
				setattr(av_new12, 'engine', 'sep')
				setattr(av_new12, 'current', '1')
				setattr(av_new12, 'defs_date_str', _sep12['defDate'])
				setattr(av_new12, 'file', _sep12['url'])
				setattr(av_new12, 'mdate', datetime.now())
				db.session.add(av_new12)

				av_new14 = AvDefs()
				_sep14 = _jdata['sep14']
				setattr(av_new14, 'engine', 'sep')
				setattr(av_new14, 'current', '1')
				setattr(av_new14, 'defs_date_str', _sep14['defDate'])
				setattr(av_new14, 'file', _sep14['url'])
				setattr(av_new14, 'mdate', datetime.now())
				db.session.add(av_new14)

				db.session.commit()
				return {"result": '', "errorno": 0, "errormsg": 'none'}, 201

			return {"result": '', "errorno": 0, "errormsg": 'none'}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[AVData][Get][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def changeCurrentToNot(self):

		q_task = AvDefs.query.filter(AvDefs.current == 1).all()
		if q_task is not None:
			for row in q_task:
				setattr(row, 'current', '0')

		db.session.commit()

# Add Routes Resources
antivirus_2_api.add_resource(AVDefsData, '/av/<string:engine>')
