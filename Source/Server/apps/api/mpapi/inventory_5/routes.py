from datetime import datetime

from flask import request
from sqlalchemy.exc import IntegrityError

from mpapi.app import db
from mpapi.mputil import MPResource
from mpapi.model import MpInvState
from mpapi.mplogger import log_Info, log_Error, log_Debug
from mpapi.shared.rest import client_endpoint, ok, fail
from mpapi.shared.inventory import storeInventory

from . import inventory_5_api


class AddInventoryData(MPResource):
	"""
	Receive one inventory table from a client. Small tables are loaded now, large ones are
	saved for MPInventoryD to load, see shared/inventory.py.
	"""

	@client_endpoint()
	def post(self, client_id):
		success, code, message = storeInventory(client_id, request.get_json(force=True, silent=True))
		if success:
			return ok(code=code, errormsg='')
		return fail(code, message)


class InventoryState(MPResource):
	"""Has this client ever sent inventory data? GET reads the flag, POST sets it."""

	@client_endpoint()
	def get(self, client_id):
		state = MpInvState.query.filter(MpInvState.cuuid == client_id).first()
		return ok({'data': state is not None}, errormsg='')

	@client_endpoint()
	def post(self, client_id):
		try:
			if MpInvState.query.filter(MpInvState.cuuid == client_id).first() is None:
				db.session.add(MpInvState(cuuid=client_id, mdate=datetime.now()))
				db.session.commit()
		except IntegrityError as e:
			db.session.rollback()
			log_Error('[InventoryState][POST] Client: %s Message: %s' % (client_id, e))
			return fail(500, str(e), result={'data': False})

		return ok({'data': True}, errormsg='')


# Add Routes Resources
inventory_5_api.add_resource(AddInventoryData, '/client/inventory/<string:client_id>')
inventory_5_api.add_resource(InventoryState,   '/client/inventory/state/<string:client_id>')
