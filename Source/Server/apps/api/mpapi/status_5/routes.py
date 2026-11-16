from mpapi.mputil import MPResource
from mpapi.shared.rest import ok

from . import status_5_api


class ServerStatusNoDB(MPResource):
	"""Liveness check, no DB access and no auth. Used by the client's server ping."""

	def get(self):
		return ok({'status': 'Server is up flask is working.'})


# Add Routes Resources
status_5_api.add_resource(ServerStatusNoDB, '/server/status/nodb')
