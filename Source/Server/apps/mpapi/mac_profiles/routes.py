from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
import base64

from . import *
from .. import db
from .. mputil import *
from .. model import *
from .. mplogger import *

parser = reqparse.RequestParser()

# Clientin Info/Status
class ProfilesForClient(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(ProfilesForClient, self).__init__()

	def get(self, cuuid):

		try:
			if not isValidClientID(cuuid):
				log_Error('[ProfilesForClient][Get]: Failed to verify ClientID (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[ProfilesForClient][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": '', "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			cProfileObj = ClientProfile()
			_clientGroup = cProfileObj.clientGroup(cuuid)
			# Get Client Group Assigned Profiles and Global Assigned Profiles
			_profileIDList = cProfileObj.profilesForGroup(_clientGroup)
			_profiles = []
			if _profileIDList is not None:
				q_result = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.profileID.in_(_profileIDList)).all()
				if q_result is not None:
					for row in q_result:
						_profile = {}
						_profile['id'] = row.profileID
						_profile['profileIdentifier'] = row.profileIdentifier
						_profile['rev'] = row.profileRev
						_profile['data'] = base64.b64encode(row.profileData)
						_profile['remove'] = row.uninstallOnRemove
						_profiles.append(_profile)

			return {'errorno': '0', 'errormsg': '', 'result': _profiles}, 200

		except IntegrityError as exc:
			log_Error('[ProfilesForClient][Get][IntegrityError] CUUID: %s Message: %s' % (cuuid, exc.message))
			return {'errorno': 500, 'errormsg': exc.message, 'result': []}, 500
		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[ProfilesForClient][Get][Exception][Line: %d] CUUID: %s Message: %s' % (exc_tb.tb_lineno, cuuid, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': []}, 500


''' ------------------------------- '''
''' NOT A WEB SERVICE CLASS         '''

class ClientProfile():

	def __init__(self):
		pass

	def clientGroup(self, cuuid):
		_group_name = "Default"

		q_result = MpClientPlist.query.filter(MpClientPlist.cuuid == cuuid).first()
		if q_result is not None and q_result.Domain is not None:
			_group_name = q_result.Domain
		return _group_name

	def profilesForGroup(self, clientGroupID):
		_profiles = []

		q_grp_result = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.groupID == clientGroupID).all()
		q_glb_result = MpOsConfigProfilesAssigned.query.filter(MpOsConfigProfilesAssigned.groupID == 'Global').all()

		if q_grp_result is not None:
			for row in q_grp_result:
				_profiles.append(row.profileID)

		if q_glb_result is not None:
			for row in q_glb_result:
				_profiles.append(row.profileID)

		return _profiles

''' ------------------------------- '''
''' Private Class Model             '''

class Profile(object):
	def __init__(self):
		self.id = ""
		self.profileIdentifier = ""
		self.rev = "0"
		self.data = ""
		self.remove = ""

	def struct(self):
		return(self.__dict__)

	def keys(self):
		return list(self.__dict__.keys())

# Add Routes Resources
mac_profiles_api.add_resource(ProfilesForClient,     '/client/profiles/<string:cuuid>')
