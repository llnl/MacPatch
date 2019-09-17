from flask import request
from flask_restful import reqparse

from . import *

from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *
from .. wsresult import *
from .. shared.agentRegistration import *

from M2Crypto import RSA
import hashlib
import base64
import uuid
import os


# Client Reg Process
class Registration(MPResource):

	def __init__(self):
		# self.reqparse = reqparse.RequestParser()
		super(Registration, self).__init__()
	'''
	@swagger.operation(
		notes='Post Client Reg',
		parameters=[
			{
				"name": "body",
				"description": "",
				"required": False,
				"allowMultiple": False,
				"dataType": "MpClientsRegistration",
				"paramType": "body"
			}
		])
	'''
	def post(self, client_id, regKey="NA"):
		log_Info('[Registration][Post]: Register client (%s) using key (%s).' % (client_id, regKey))
		# print client_id
		'''
			Content Dict: cKey, CPubKeyPem, CPubKeyDer, ClientHash
			cKey = Client Auth Key, used for signatures
			CPubKeyPem = Client Pub Key - PEM
			CPubKeyDer = Client Pub Key - DER
			ClientHash = Client Agent Parts Hash (MPAgent, MPAgentExec, MPWorker)
			ClientHash = Client Key Hash (SHA1)
			HostName = Agent Host Name (Used For Parking)
			SerialNo = System Serial No (Used For Parking)
		'''
		# print('[Registration][Post]: Register client (%s) succeed.' % (client_id))
		content = request.get_json(silent=True)
		# print content

		if all(key in content for key in ("cKey", "CPubKeyPem", "ClientHash", "HostName", "SerialNo", "CheckIn")):

			valid_reg_key   = False
			use_reg_key     = False
			reg_key_id      = 0
			use_parking     = isClientParkingEnabled()
			client_enabled  = 1
			auto_reg        = isAutoRegEnabled()
			auto_reg_rereg  = True

			# Is Client Already Registered
			if isClientRegistered(client_id):
				log_Info('[Registration][Post]: Client (%s) already registered.' % (client_id))
				if auto_reg is True and auto_reg_rereg is True:
					log_Info('[Registration][Post]: Client (%s) will update its registration.' % (client_id))
				else:
					return {"result": '', "errorno": 406, "errormsg": 'Failed to register client.'}, 406

			# AutoReg is disabled
			if auto_reg is False:
				log_Info('[Registration][Post]: Using registration key, autoreg not enabled.')
				# Verify Reg Key for Client ID
				validKey = isValidRegKey(regKey, client_id)

				if validKey[0]:
					log_Debug('[Registration][Post]: Verify reg key (%s) for client (%s) succeed.' % (regKey, client_id))
					reg_key_id = validKey[1]
					use_reg_key = True
				elif use_parking:
					client_enabled = 0
				else:
					log_Info('[Registration][Post]: Failed to verify reg key (%s) for client (%s).' % (regKey, client_id))
					return {"result": '', "errorno": 401, "errormsg": 'Failed to verify reg key for client.'}, 401

			# Begin Client Registration

			# Verify that the client key is valid
			# First decoded the encrypted client key, then gen a SHA1 hash and compare
			decoded_client_key = decodeClientKey(content['cKey'])
			if verifyClientHash(decoded_client_key, content['ClientHash']):
				log_Debug('[Registration][Post]: Verify client key hash succeed (%s)' % (content['ClientHash']))

			else:
				log_Info('[Registration][Post]: Failed to verify hash (%s)' % (content['ClientHash']))
				return {"result": '', "errorno": 412, "errormsg": 'Failed to verify client key hash'}, 412

			# Write Client Data to Database
			if writeRegInfoToDatabase(content, decoded_client_key, client_enabled) is False:
				return {"result":  datetime.now().strftime('%Y-%m-%d %H:%M:%S'), "errorno": 400, "errormsg": 'Failed to register client. Please see server logs.'}, 400
			else:
				# Add Agent Data to MPClient, this way the agent config data can be sent to client
				self.addOrUpdateClientData(client_id, content['CheckIn'])

				# Make sure we are using a regKey, if true then set it as used.
				if use_reg_key:
					if reg_key_id >= 1:
						setRegKeyUsed(client_id, regKey, reg_key_id)
						# setClientRegKeyUsed(cuuid, regKey)

				return {"result": 'Client Registered', "errorno": 0, "errormsg": ''}, 201

		else:
			return {"result": '', "errorno": 300, "errormsg": 'Required Keys are missing.'}, 300

		return {"result": '', "errorno": 404, "errormsg": 'Should never get here'}, 404

	def addOrUpdateClientData(self, client_id, client_data):

		client_obj = MpClient.query.filter_by(cuuid=client_id).first()
		log_Debug('[addOrUpdateClientData][Update]: Client (%s) Data %s' % (client_id, client_data))

		if client_obj:
			# Update
			log_Info('[AgentBase][Post]: Updating client (%s) record.' % (client_id))
			for col in client_obj.columns:
				if col != 'mdate':
					if col in client_data:
						if client_data[col] is not None:
							setattr(client_obj, col, client_data[col])

			setattr(client_obj, 'mdate', datetime.now())
			db.session.commit()

		else:
			# Add
			log_Info('[addOrUpdateClientData][Add]: Client (%s) Data %s' % (client_id, client_data))
			client_object = MpClient()
			# print client_object.columns

			client_object.cuuid = client_id
			for col in client_object.columns:
				if col != 'mdate':
					if col in client_data:
						if client_data[col] is not None:
							setattr(client_object, col, client_data[col])

			setattr(client_object, 'mdate', datetime.now())
			db.session.add(client_object)
			db.session.commit()

# Client Registration Status
class RegistrationStatus(MPResource):

	def __init__(self):
		super(RegistrationStatus, self).__init__()

	def get(self, client_id, keyHash='NA'):

		reg_query_object = MPAgentRegistration.query.filter_by(cuuid = client_id).first()

		if reg_query_object is not None:
			rec = reg_query_object.asDict
			if keyHash != 'NA':
				if rec['enabled'] == 1 and verifyClientHash(rec['clientKey'], keyHash):
					return {"result": {'data':True}, "errorno": 0, "errormsg": ""}, 200
				else:
					return {"result": {'data': False}, "errorno": 409, "errormsg": "Registration key mis-match. Suggest, re-registering client."}, 409
			else:
				if rec['enabled'] == 1:
					return {"result": {'data':True}, "errorno": 0, "errormsg": ""}, 200

			return {"result": {'data':False}, "errorno": 400, "errormsg": "Error, validating registration."}, 400

		return {"result": {'data':False}, "errorno": 204, "errormsg": "Client not registered."}, 204

''' Private Methods '''
def verifyClientHash(encodedKey, hash):
	if encodedKey is not None:
		_lHash = hashlib.sha1(str(encodedKey).encode('utf-8')).hexdigest()
		if _lHash.lower() == hash.lower():
			return True
		else:
			return False
	else:
		return False

def decodeClientKey(encodedKey):
	try:
		qKeys = MpSiteKeys.query.filter(MpSiteKeys.active == '1').first()
		priKeyFile = "/tmp/." + str(uuid.uuid4())
		f = open(priKeyFile, "w")
		f.write(qKeys.priKey)
		f.close()

		priv = RSA.load_key(priKeyFile)
		decrypted = priv.private_decrypt(base64.b64decode(encodedKey), RSA.pkcs1_padding)
		os.remove(priKeyFile)
		return decrypted

	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		message=str(e.args[0]).encode("utf-8")
		log_Error('[Registration][decodeClientKey][Line: %d] Message: %s' % (exc_tb.tb_lineno, message))
		db.session.rollback()
		return None

# Add Routes Resources
register_2_api.add_resource(Registration,         '/client/register/<string:client_id>', endpoint='noRegKey')
register_2_api.add_resource(Registration,         '/client/register/<string:client_id>/<string:regKey>', endpoint='yaRegKey')

register_2_api.add_resource(RegistrationStatus,   '/client/register/status/<string:client_id>', endpoint='noHash')
register_2_api.add_resource(RegistrationStatus,   '/client/register/status/<string:client_id>/<string:keyHash>', endpoint='yesHash')
