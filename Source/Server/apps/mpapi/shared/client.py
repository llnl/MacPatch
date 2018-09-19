from .. model import *

class Client():

	def __init__(self, client_id):
		self.cuuid = client_id
		pass

	def settings(self):
		pass

	def getPatchGroupForClient(self, cuuid):
		patch_group_id = 'NA'
		group_id = 0
		qGroupMembership = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == cuuid).first()
		if qGroupMembership is not None:
			group_id = qGroupMembership.group_id

		qGroupData = MpClientSettings.query.filter(MpClientSettings.group_id == group_id, MpClientSettings.key == 'patch_group').first()
		if qGroupData is not None:
			patch_group_id = qGroupData.value

		return patch_group_id

# Model
class AgentSettings():

	def __init__(self):
		self.allow_client = None
		self.allow_reboot = None
		self.allow_server = None
		self.inherited_software_group = None
		self.inherited_software_group_id = None
		self.patch_group = None
		self.patch_group_id = None
		self.patch_state = None
		self.software_group = None
		self.software_group_id = None
		self.verify_signatures = None
		self.client_group = None
		self.client_group_id = None

	def populateSettings(self, client_id):

		_group_id = 0

		qGroupMembership = MpClientGroupMembers.query.filter(MpClientGroupMembers.cuuid == client_id).first()
		if qGroupMembership is not None:
			_group_id = qGroupMembership.group_id
			self.client_group_id = _group_id
			qClientGroup = MpClientGroups.query.filter(MpClientGroups.group_id == _group_id ).first()
			if qClientGroup is not None:
				self.client_group = qClientGroup.group_name

		qGroupData = MpClientSettings.query.filter(MpClientSettings.group_id == _group_id).all()
		if qGroupData is not None:
			for row in qGroupData:
				for key in self.__dict__.keys():
					if row.key == key:
						setattr(self, key, row.value)
						#self[key] = row.value

	def getVariablesClass(inst):
		var = []

		cls = inst.__class__
		for v in cls.__dict__:
			if not callable(getattr(cls, v)):
				var.append(v)

		return var
