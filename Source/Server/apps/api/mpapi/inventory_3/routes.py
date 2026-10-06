from flask import request

from . import inventory_3_api
from mpapi.mputil import MPResource, isValidClientID, isValidSignature
from mpapi.mplogger import log_Error
from mpapi.shared.inventory import storeInventory

# The inventory processing code (create/alter table, purge and insert) now lives in
# mpapi/shared/inventory.py and inventory_core.py, shared with /api/v5 and MPInventoryD.


class AddInventoryData(MPResource):

	def post(self, client_id):
		if not isValidClientID(client_id):
			log_Error('[AddInventoryData][Post]: Failed to verify ClientID (%s)' % (client_id))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify ClientID'}, 412

		if not isValidSignature(self.req_signature, client_id, request.data, self.req_ts):
			log_Error('[AddInventoryData][Post]: Failed to verify Signature for client (%s)' % (client_id))
			return {"result": '', "errorno": 412, "errormsg": 'Failed to verify Signature'}, 412

		success, code, message = storeInventory(client_id, request.get_json(force=True, silent=True))
		if success:
			return {"result": {}, "errorno": 0, "errormsg": ''}, code
		return {"result": {}, "errorno": code, "errormsg": message}, code


# Add Routes Resources
inventory_3_api.add_resource(AddInventoryData,    '/client/inventory/<string:client_id>')
