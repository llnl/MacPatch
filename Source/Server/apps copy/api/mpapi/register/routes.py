from flask_restful import reqparse
# from flask_restful_swagger import swagger

import base64
import hashlib
from datetime import datetime

import M2Crypto
from flask_restful import reqparse

from . import *

from mpapi.model import *
from mpapi.mplogger import *
from mpapi.mputil import *
from .. shared.agentRegistration import *

# Client Reg Test
class Test(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(Test, self).__init__()
	'''
	@swagger.operation(notes='Get: Test Registration')
	def get(self):
		return {
			'Reg': 'Test',
		}
	'''

# Client Reg Process
class Registration(MPResource):

	def __init__(self):
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
	def post(self, cuuid, regKey="NA"):
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

		content = request.get_json(silent=True)
		print(content)

		if all(key in content for key in ("cKey", "CPubKeyPem", "ClientHash", "HostName", "SerialNo")):

			valid_reg_key   = False
			use_reg_key     = False
			reg_key_id      = 0
			use_parking     = isClientParkingEnabled()
			client_enabled  = 1
			auto_reg        = isAutoRegEnabled()

			# Is Client Already Registered
			if isClientRegistered(cuuid):
				return {"result": '', "errorno": 406, "errormsg": 'Failed to register client.'}, 406

			# AutoReg is disabled
			if auto_reg is False:
				# Verify Reg Key for Client ID
				validKey = isValidRegKey(regKey, cuuid)

				if validKey[0]:
					log_Debug('[Registration][Post]: Verify reg key (%s) for client (%s) succeed.' % (regKey, cuuid))
					reg_key_id = validKey[1]
					use_reg_key = True
				elif use_parking:
					client_enabled = 0
				else:
					log_Info('[Registration][Post]: Failed to verify reg key (%s) for client (%s).' % (regKey, cuuid))
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
				# Make sure we are using a regKey, if true then set it as used.
				if use_reg_key:
					if reg_key_id >= 1:
						setRegKeyUsed(cuuid, regKey, rid)
						# setClientRegKeyUsed(cuuid, regKey)

				return {"result": 'Client Registered', "errorno": 0, "errormsg": ''}, 201

		else:
			return {"result": '', "errorno": 300, "errormsg": 'Required Keys are missing.'}, 300

		return {"result": '', "errorno": 404, "errormsg": 'Should never get here'}, 404


# Client Registration Status
class RegistrationStatus(MPResource):

	def __init__(self):
		super(RegistrationStatus, self).__init__()
	'''
	@swagger.operation(notes='Get Client registration Status')
	'''
	def get(self, cuuid, keyHash='NA'):

		reg_query_object = MPAgentRegistration.query.filter_by(cuuid=cuuid).first()

		if reg_query_object is not None:
			rec = reg_query_object.asDict
			if keyHash != 'NA':
				if rec['enabled'] == 1 and verifyClientHash(rec['clientKey'], keyHash):
					return {"result": True, "errorno": 0, "errormsg": ""}, 200
			else:
				if rec['enabled'] == 1:
					return {"result": True, "errorno": 0, "errormsg": ""}, 200

			return {"result": False, "errorno": 206, "errormsg": ""}, 206

		return {"result": False, "errorno": 204, "errormsg": ""}, 204


''' Private Methods '''
def verifyClientHash(encodedKey, hash):
	if encodedKey is not None:
		if isinstance(encodedKey, (bytes, bytearray)) == False:
			# Object is not encoded, needs to be
			encodedKey = encodedKey.encode('utf-8')

		_lHash = hashlib.sha1(encodedKey).hexdigest()
		if _lHash.lower() == hash.lower():
			return True
		else:
			return False
	else:
		return False

def decodeClientKey(encodedKey):
	try:
		priKeyFile = return_data_for_server_key('priKey')
		priv = M2Crypto.RSA.load_key(priKeyFile)
		decrypted = priv.private_decrypt(base64.b64decode(encodedKey), M2Crypto.RSA.pkcs1_oaep_padding)

		return decrypted
	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		message=str(e.args[0]).encode("utf-8")
		log_Error('[Registration][decodeClientKey][Line: %d] Message: %s' % (exc_tb.tb_lineno, message))
		return None


# Add Routes Resources
register_api.add_resource(Test,                 '/client/RegTest')
register_api.add_resource(Registration,         '/client/register/<string:cuuid>', endpoint='noRegKey')
register_api.add_resource(Registration,         '/client/register/<string:cuuid>/<string:regKey>', endpoint='yaRegKey')
register_api.add_resource(RegistrationStatus,   '/client/register/status/<string:cuuid>', endpoint='noHash')
register_api.add_resource(RegistrationStatus,   '/client/register/status/<string:cuuid>/<string:keyHash>', endpoint='yesHash')
