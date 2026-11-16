import base64
import hashlib
from datetime import datetime

from flask import request, current_app
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import load_pem_private_key

from mpapi.app import db
from mpapi.mputil import MPResource
from mpapi.model import MpClient, MPAgentRegistration, MpSiteKeys
from mpapi.mplogger import log_Info, log_Error, log_Debug
from mpapi.MSIntune import MPTaskJobs
from mpapi.shared.rest import client_endpoint, ok, fail
from mpapi.shared.agentRegistration import (isClientRegistered, isAutoRegEnabled, isClientParkingEnabled,
											isValidRegKey, setRegKeyUsed, writeRegInfoToDatabase)

from . import register_5_api

REQUIRED_KEYS = ("cKey", "CPubKeyPem", "ClientHash", "HostName", "SerialNo", "CheckIn")


def verifyClientHash(key, key_hash):
	"""Does the SHA1 of the client key match key_hash?"""
	if key is None:
		return False
	if not isinstance(key, (bytes, bytearray)):
		key = key.encode('utf-8')
	return hashlib.sha1(key).hexdigest().lower() == key_hash.lower()


def decodeClientKey(encoded_key):
	"""Decrypt the client key with the active site private key, None if that fails."""
	try:
		site_key = MpSiteKeys.query.filter(MpSiteKeys.active == '1').first()
		private_key = load_pem_private_key(site_key.priKey.encode(), password=None)
		return private_key.decrypt(base64.b64decode(encoded_key),
								   padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA1()),
												algorithm=hashes.SHA1(), label=None))
	except Exception as e:
		log_Error('[Registration][decodeClientKey] Message: %s' % e)
		db.session.rollback()
		return None


def addOrUpdateClientData(client_id, client_data):
	"""Store the client info sent with the registration so its config can be served right away."""
	log_Debug('[Registration] Client (%s) Data %s' % (client_id, client_data))
	client = MpClient.query.filter_by(cuuid=client_id).first()
	if client is None:
		client = MpClient(cuuid=client_id)
		db.session.add(client)

	for col in client.columns:
		if col != 'mdate' and client_data.get(col) is not None:
			setattr(client, col, client_data[col])

	client.mdate = datetime.now()
	db.session.commit()


class Registration(MPResource):
	"""Register a client (and its client key). Unregistered clients call this, so no auth checks."""

	@client_endpoint(verify_id=False, verify_signature=False)
	def post(self, client_id, regKey='NA'):
		log_Info('[Registration][POST] Register client (%s) using key (%s).' % (client_id, regKey))

		# cKey = encrypted client auth key (used for signatures), CPubKeyPem = client public key,
		# ClientHash = SHA1 of the client key, HostName/SerialNo = used for parking,
		# CheckIn = client info for mp_clients
		content = request.get_json(silent=True) or {}
		if not all(key in content for key in REQUIRED_KEYS):
			return fail(300, 'Required Keys are missing.')

		use_parking = isClientParkingEnabled()
		auto_reg = isAutoRegEnabled()
		client_enabled = 1
		reg_key_id = 0

		if isClientRegistered(client_id):
			log_Info('[Registration][POST] Client (%s) already registered.' % client_id)
			if not auto_reg:
				return fail(406, 'Failed to register client.')
			log_Info('[Registration][POST] Client (%s) will update its registration.' % client_id)

		if not auto_reg:
			log_Info('[Registration][POST] Using registration key, autoreg not enabled.')
			valid, reg_key_id = isValidRegKey(regKey, client_id)[:2]
			if valid:
				log_Debug('[Registration][POST] Verify reg key (%s) for client (%s) succeed.' % (regKey, client_id))
			elif use_parking:
				client_enabled = 0
			else:
				log_Info('[Registration][POST] Failed to verify reg key (%s) for client (%s).' % (regKey, client_id))
				return fail(401, 'Failed to verify reg key for client.')
		else:
			valid = False

		# Verify the client key: decrypt it, hash it and compare with the hash the client sent
		decoded_client_key = decodeClientKey(content['cKey'])
		if not verifyClientHash(decoded_client_key, content['ClientHash']):
			log_Info('[Registration][POST] Failed to verify hash (%s)' % content['ClientHash'])
			return fail(412, 'Failed to verify client key hash')

		if writeRegInfoToDatabase(content, decoded_client_key, client_enabled) is False:
			return fail(400, 'Failed to register client. Please see server logs.',
						result=datetime.now().strftime('%Y-%m-%d %H:%M:%S'))

		addOrUpdateClientData(client_id, content['CheckIn'])

		if valid and reg_key_id >= 1:
			setRegKeyUsed(client_id, regKey, reg_key_id)

		if current_app.config.get('ENABLE_INTUNE'):
			intune = MPTaskJobs()
			intune.init_app(current_app)
			intune.AddCorporateDevice(content['SerialNo'], client_id)

		return ok('Client Registered', code=201, errormsg='')


class RegistrationStatus(MPResource):
	"""Is the client registered and enabled? With keyHash, also does its client key match."""

	@client_endpoint(verify_id=False, verify_signature=False)
	def get(self, client_id, keyHash='NA'):
		registration = MPAgentRegistration.query.filter_by(cuuid=client_id).first()
		if registration is None:
			return fail(204, 'Client not registered.', result={'data': False})

		reg = registration.asDict
		if keyHash != 'NA':
			if reg['enabled'] == 1 and verifyClientHash(reg['clientKey'], keyHash):
				return ok({'data': True}, errormsg='')
			return fail(409, 'Registration key mis-match. Suggest, re-registering client.', result={'data': False})

		if reg['enabled'] == 1:
			return ok({'data': True}, errormsg='')
		return fail(400, 'Error, validating registration.', result={'data': False})


# Add Routes Resources
register_5_api.add_resource(Registration,       '/client/register/<string:client_id>', endpoint='noRegKey')
register_5_api.add_resource(Registration,       '/client/register/<string:client_id>/<string:regKey>', endpoint='yaRegKey')
register_5_api.add_resource(RegistrationStatus, '/client/register/status/<string:client_id>', endpoint='noHash')
register_5_api.add_resource(RegistrationStatus, '/client/register/status/<string:client_id>/<string:keyHash>', endpoint='yesHash')
