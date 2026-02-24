import json
from . mputil import *

class WSResult():

	def __init__(self):
		self.errorno = 0
		self.errormsg = ''
		self.data = {}
		self.signature = ''

	def resultWithSignature(self, **kwargs):
		self.data = kwargs.get('data', self.data)

		_dict = {}
		_dict['errorno'] = kwargs.get('errorno', self.errorno)
		_dict['errormsg'] = kwargs.get('errormsg', self.errormsg)
		_dict['result'] = self.data
		_dict['signature'] = self.genSignature()

		return _dict

	def resultNoSignature(self, **kwargs):
		_dict = {}
		_dict['errorno'] = kwargs.get('errorno', self.errorno)
		_dict['errormsg'] = kwargs.get('errormsg', self.errormsg)
		_dict['result'] = kwargs.get('data', self.data)
		_dict['signature'] = 'NA'

		return _dict

	def genSignature(self):
		if self.data['data'] is not None:
			return signData(json.dumps(self.data['data']))
		else:
			return "ERRDATA"

class WSData():

	def __init__(self):
		self.data = None
		self.type = None

	def toDict(self):
		_dict = {}
		_dict['data'] = self.data
		_dict['type'] = self.type

		return _dict
