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
				return {"result": {'data':[], 'type': 'MacProfiles'}, "errorno": 424, "errormsg": 'Failed to verify ClientID'}, 424

			if not isValidSignature(self.req_signature, cuuid, self.req_uri, self.req_ts):
				log_Error('[ProfilesForClient][Get]: Failed to verify Signature for client (%s)' % (cuuid))
				return {"result": {'data':[], 'type': 'MacProfiles'}, "errorno": 424, "errormsg": 'Failed to verify Signature'}, 424

			cProfileObj = ClientProfile()
			_clientGroupID = cProfileObj.clientGroupID(cuuid)

			# Get Client Group Assigned Profiles and Global Assigned Profiles
			_profileIDList = cProfileObj.profilesForGroup(_clientGroupID)
			_profiles = []
			if _profileIDList is not None:
				q_result = MpOsConfigProfiles.query.filter(MpOsConfigProfiles.profileID.in_(_profileIDList)).all()
				if q_result is not None:
					for row in q_result:
						if row.enabled == 1:
							res = self.evaluateCriteriaForProfile(cuuid,_clientGroupID,row.profileID,row.isglobal)
							if res[0] == True:
								_profile = {}
								_profile['id'] = row.profileID
								_profile['profileIdentifier'] = row.profileIdentifier
								_profile['rev'] = row.profileRev
								_profile['data'] = base64.b64encode(row.profileData)
								_profile['remove'] = row.uninstallOnRemove
								_profile['name'] = row.profileName
								_profile['description'] = row.profileDescription
								_profile['criteria'] = res[1]
								_profiles.append(_profile)
							else:
								log_Debug('{} did not match criteria evaluation.'.format(row.profileID))

			return {'errorno': '0', 'errormsg': '', 'result': {'data': _profiles, 'type': 'MacProfiles'}}, 200

		except IntegrityError, exc:
			log_Error('[ProfilesForClient][Get][IntegrityError] CUUID: %s Message: %s' % (cuuid, exc.message))
			return {'errorno': 500, 'errormsg': exc.message, 'result': {'data':[], 'type': 'MacProfiles'}}, 500

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			log_Error('[ProfilesForClient][Get][Exception][Line: %d] CUUID: %s Message: %s' % (exc_tb.tb_lineno, cuuid, e.message))
			return {'errorno': 500, 'errormsg': e.message, 'result': {'data':[], 'type': 'MacProfiles'}}, 500

	#
	def evaluateCriteriaForProfile(self, clientID, clientGroupID, profileID, isGlobal):
		_groupID = None
		if isGlobal:
			_groupID = 0
		else:
			_groupID = clientGroupID

		# Get the criteria for the policy id
		q_result = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.groupID == _groupID,
														  MpOsProfilesGroupAssigned.profileID == profileID).first()

		if q_result is not None:
			# Get the criteria policy id for the profile for the client
			res =  self.policyCriteriaTest(clientID,q_result.gPolicyID)
			if res[0] == 1:
				return (True, res[1])

		return (False, [])

	# Will check, SYSType:OSType:ModelType:OSVersion criteria
	def policyCriteriaTest(self,clientID,policyID):

		criteria = []
		result = 0
		q_result = MpOsProfilesCriteria.query.filter(MpOsProfilesCriteria.gPolicyID == policyID).all()
		if q_result is not None:
			c_result = MpClient.query.filter(MpClient.cuuid == clientID).first()
			c_resultHW = MPISPHardwareOverview.query.filter(MPISPHardwareOverview.cuuid == clientID).first()

			# Replace the comma in model name, so a list can use a comma
			_model = c_resultHW.mpa_Model_Name.replace(",",".")
			_type = "Desktop"
			if "book".upper() in _model.upper():
				_type = "Laptop"

			for row in q_result:
				if row.type == "SYSType":
					if row.type_data == "*":
						continue
					else:
						if _type.upper() in row.type_data.upper():
							# Pass
							continue
						else:
							log_Error("{} was not found in {} ".format(_type,row.type_data))
							result = result + 1

				elif row.type == "OSType":
					if row.type_data == "*":
						continue
					else:
						if not self.versionCheck(row.type_data, c_result.osver):
							result = result + 1
						continue

				elif row.type == "ModelType":
					if row.type_data == "*":
						continue
					else:
						if not self.modelCheck(row.type_data, _model):
							result = result + 1
						continue

				elif row.type == "OSVersion":
					if row.type_data == "*":
						continue
					else:
						if not self.versionCheck(row.type_data, c_result.osver):
							result = result + 1
						continue
				else:
					criteria.append({'type':row.type,'type_data':base64.b64encode(row.type_data)})

		return (result,criteria)


	def modelCheck(self, modelList, clientModel):
		result = False
		model_list = modelList.split(",")
		for v in model_list:
			if "*" in v:
				_v = v.replace("*","")
				if _v.upper() in clientModel.upper():
					result = True
					break
			else:
				if v in clientModel:
					result = True
					break

		return result

	def versionCheck(self, verStrList, clientOSVer):
		result = False
		version_list = verStrList.split(",")
		for v in version_list:
			if "*" in v:
				_v = v.replace("*","")
				if _v in clientOSVer:
					result = True
					break
			# 10.14+
			elif "+" in v:
				_v = v.replace("+", "")
				if LooseVersion(clientOSVer) >= LooseVersion(_v):
					result = True
					break
			else:
				if v == clientOSVer:
					result = True
					break

		return result


''' ------------------------------- '''
''' NOT A WEB SERVICE CLASS         '''

class ClientProfile():

	def __init__(self):
		pass

	def clientGroupID(self, cuuid):
		_group_id = '0'

		q_result = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == cuuid).first()
		if q_result is not None and q_result.group_id is not None:
			_group_id = q_result.group_id
		return _group_id

	def profilesForGroup(self, clientGroupID):
		_profiles = []

		q_grp_result = MpOsProfilesGroupAssigned.query.filter(MpOsProfilesGroupAssigned.groupID == clientGroupID).all()
		q_glb_result = MpOsConfigProfilesAssigned.query.filter(MpOsConfigProfilesAssigned.groupID == 'Global').all()

		if q_grp_result is not None:
			for row in q_grp_result:
				_profiles.append(row.profileID)

		if q_glb_result  is not None:
			for row in q_glb_result :
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
		return self.__dict__.keys()

# Add Routes Resources
mac_profiles_2_api.add_resource(ProfilesForClient,     '/client/profiles/<string:cuuid>')
