from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
import datetime
import json
import sys

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *
from mpapi.shared.inventory import stageInventory

parser = reqparse.RequestParser()

class AddInventoryData(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(AddInventoryData, self).__init__()

	def post(self, cuuid):

		if not isValidClientID(cuuid):
			log_Error('[AddInventoryData][Post]: Failed to verify ClientID (%s)' % (cuuid))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify ClientID'}, 412

		if not isValidSignature(self.req_signature, cuuid, request.data, self.req_ts):
			log_Error('[AddInventoryData][Post]: Failed to verify Signature for client (%s)' % (cuuid))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify Signature'}, 412

		# Saved for MPInventoryD to load, see shared/inventory.py
		success, code, message = stageInventory(cuuid, request.get_json(force=True, silent=True))
		if success:
			return {"result": '', "errorno": 0, "errormsg": ''}, code
		return {"result": '', "errorno": code, "errormsg": message}, code


class InventoryState(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(InventoryState, self).__init__()

	def get(self, cuuid):

		try:
			if not isValidClientID(cuuid):
				log_Error('[InventoryState][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 412, "errormsg": 'Failed to verify ClientID'}, 412

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[InventoryState][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 412, "errormsg": 'Failed to verify Signature'}, 412

			_result = 0
			q_result = MpInvState.query.filter(MpInvState.cuuid == cuuid).first()
			if q_result is not None:
				if q_result.cuuid == cuuid:
					_result = 1
				else:
					_result = 0

			return {'errorno': '0', 'errormsg': '', 'result': _result}, 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[InventoryState][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

	def post(self, cuuid):

		try:
			if not isValidClientID(cuuid):
				log_Error('[InventoryState][Post]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[InventoryState][Post]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			try:
				q_InvObj = MpInvState.query.filter(MpInvState.cuuid == cuuid).first()
				if q_InvObj is None:
					# Add
					_mpInvObj = MpInvState()

					setattr(_mpInvObj, 'cuuid', cuuid)
					setattr(_mpInvObj, 'mdate', datetime.now())

					db.session.add(_mpInvObj)
					db.session.commit()

				return {'errorno': '0', 'errormsg': '', 'result': 0}, 200

			except IntegrityError as exc:
				db.engine.rollback()
				log_Error('[except] CUUID: %s Message: %s' % (cuuid, exc.message))
				return {'errorno': 500, 'errormsg': exc.message, 'result': 1}, 500

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[InventoryState][Post][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, cuuid, message))
			return {'errorno': 500, 'errormsg': message, 'result': {}}, 500

		


# Add Routes Resources
inventory_api.add_resource(AddInventoryData,    '/client/inventory/<string:cuuid>')
inventory_api.add_resource(InventoryState,      '/client/inventory/state/<string:cuuid>')
