from flask import request
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
from distutils.version import LooseVersion
import base64

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *
from .. wsresult import *
from .. shared.software import *

parser = reqparse.RequestParser()

# REST Software Methods
class SoftwareRestrictions(MPResource):

	def __init__(self):
		self.reqparse = reqparse.RequestParser()
		super(SoftwareRestrictions, self).__init__()

	def get(self, client_id):

		wsResult = WSResult()
		wsData = WSData()
		wsData.data = {}
		wsData.type = 'SoftwareRestriction'
		wsResult.result = wsData

		try:
			if self.req_agent == 'iLoad':
				log_Info("[SoftwareRestrictions][Get]: iLoad Request from %s" % (client_id))
			else:
				if not isValidClientID(client_id):
					log_Error('[SoftwareRestrictions][Get]: Failed to verify ClientID (%s)' % (client_id))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify ClientID'), 424

				if not isValidSignature(self.req_signature, client_id, self.req_uri, self.req_ts):
					log_Error('[SoftwareRestrictions][Get]: Failed to verify Signature for client (%s)' % (client_id))
					return wsResult.resultNoSignature(errorno=424, errormsg='Failed to verify Signature'), 424

			_global_count = 0
			_group_rev = 0
			_group_id = 0
			qGroupMembership = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_id).first()
			if qGroupMembership is not None:
				_group_id = qGroupMembership.group_id

			_res_list = []
			_global_res_list = self.globalRestrictions()
			_group_res_list = self.clientGroupRestrictions(_group_id)

			# add global rules
			for i in _global_res_list:
				if not any(d['appID'] == i['appID'] for d in _group_res_list):
					_global_count = _global_count + 1
					_res_list.append(i)

			# add group rules, group trumps global
			for i in _group_res_list:
				_res_list.append(i)

			_gres = MPGroupConfig.query.filter(MPGroupConfig.group_id == _group_id).first()
			if _gres is not None:
				_group_rev = _gres.restrictions_version

			_sw_res_rev = "{}-{}".format(_global_count,_group_rev)
			_data = {'revision':_sw_res_rev,'rules':_res_list}
			wsData.data = _data
			wsResult.data = wsData.toDict()
			return wsResult.resultWithSignature(), 200

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[SoftwareTasksForGroup][Get][Exception][Line: {}] CUUID: {} Message: {}'.format(exc_tb.tb_lineno, client_id, message))
			return wsResult.resultNoSignature(errorno=500, errormsg=message), 500

	def globalRestrictions(self):
		_sw_res_list = []
		# grab all global restrictions
		swResList = MpSoftwareRestrictions.query.filter(MpSoftwareRestrictions.enabled == 1,
													MpSoftwareRestrictions.isglobal == 1).all()
		if swResList is not None:
			for swRes in swResList:
				_sw = {'displayName': swRes.displayName, 'processName': swRes.processName, 'message': swRes.message,
					   'killProc': swRes.killProc, 'sendEmail': swRes.sendEmail}
				_sw_res_list.append(_sw)

		return _sw_res_list

	def clientGroupRestrictions(self,group_id):
		# grab all enabled sw restriction for the client group
		cgList = MpClientGroupSoftwareRestrictions.query.filter(MpClientGroupSoftwareRestrictions.group_id == group_id,MpClientGroupSoftwareRestrictions.enabled == 1).all()
		_sw_res_list = []
		if cgList is not None:
			for s in cgList:
				swRes = self.swRestrictionForAppID(s.appID)
				if swRes is not None:
					_sw = {'displayName':swRes.displayName,'processName':swRes.processName,'message':swRes.message,
						   'killProc':swRes.killProc,'sendEmail':swRes.sendEmail}
					_sw_res_list.append(_sw)

		return _sw_res_list

	def swRestrictionForAppID(self,appID):
		swRes = MpSoftwareRestrictions.query.filter(MpSoftwareRestrictions.enabled == 1, MpSoftwareRestrictions.isglobal == 0, MpSoftwareRestrictions.appID == appID).first()
		if swRes is not None:
			return swRes
		else:
			return None

# Add Routes Resources
software_3_api.add_resource(SoftwareRestrictions,		'/sw/restrictions/<string:client_id>')
