"""
Helpers shared by the /api/v5 route packages (*_5).

Conventions
  - The client ID URL variable is always named `client_id`.
  - Every response is {"errorno": int, "errormsg": str, "result": ...}; resources that
    return signed data add a "signature" key.
  - Request signatures follow the client (MPHTTPRequest.m): the HMAC covers the request
    body when there is one, otherwise the request path.
"""
import functools
import json
import sys

from flask import request, current_app

from mpapi.mputil import isValidClientID, isValidSignature, signData
from mpapi.mplogger import log_Info, log_Error

__all__ = ['client_endpoint', 'ok', 'fail', 'signed']


def ok(result=None, code=200, errormsg='none'):
	return {'errorno': 0, 'errormsg': errormsg, 'result': {} if result is None else result}, code


def fail(code, errormsg, errorno=None, result=None):
	return {'errorno': code if errorno is None else errorno,
			'errormsg': errormsg,
			'result': {} if result is None else result}, code


def signed(rtype, data, code=200):
	"""Standard signed payload: result {'type': rtype, 'data': data} plus a signature of data."""
	body, code = ok({'type': rtype, 'data': data}, code=code)
	body['signature'] = signData(data if isinstance(data, str) else json.dumps(data))
	return body, code


def _signature_ok(resource, client_id):
	data = request.data if request.data else request.path
	if isValidSignature(resource.req_signature, client_id, data, resource.req_ts):
		return True
	if current_app.config['ALLOW_MIXED_SIGNATURES']:
		log_Info('ALLOW_MIXED_SIGNATURES is enabled, allowing unverified signature for (%s)' % client_id)
		return True
	return False


def client_endpoint(verify_id=True, verify_signature=True, allow_iload=False):
	"""
	Decorator for MPResource methods that take a `client_id` URL variable.

	Runs the client ID and signature checks and turns uncaught exceptions into a logged 500.
	Pass verify_id / verify_signature=False only for endpoints that have to be reachable by
	unregistered clients; that choice then shows at the call site. allow_iload skips both
	checks for iLoad provisioning requests (X-Agent-ID: iLoad).
	"""
	def decorator(fn):
		@functools.wraps(fn)
		def wrapper(self, *args, **kwargs):
			client_id = kwargs.get('client_id')
			tag = '[%s][%s]' % (type(self).__name__, request.method)
			try:
				if allow_iload and self.req_agent == 'iLoad':
					log_Info('%s iLoad request from %s' % (tag, client_id))
				else:
					if verify_id and not isValidClientID(client_id):
						log_Error('%s Failed to verify ClientID (%s)' % (tag, client_id))
						return fail(424, 'Failed to verify ClientID')
					if verify_signature and not _signature_ok(self, client_id):
						log_Error('%s Failed to verify Signature for client (%s)' % (tag, client_id))
						return fail(424, 'Failed to verify Signature')
				return fn(self, *args, **kwargs)
			except Exception as e:
				_, _, tb = sys.exc_info()
				log_Error('%s[Exception][Line: %s] Client: %s Message: %s' % (tag, tb.tb_lineno, client_id, e))
				return fail(500, str(e))
		return wrapper
	return decorator
