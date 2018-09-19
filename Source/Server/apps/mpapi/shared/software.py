import base64

class SWObj(object):

	KEYS = ['suuid', 'patch_bundle_id', 'auto_patch', 'sState', 'sName', 'sVendor', 'sVersion',
			'sDescription', 'sVendorURL', 'sReboot', 'sw_type', 'sw_url', 'sw_size', 'sw_hash',
			'sw_pre_install_script', 'sw_post_install_script', 'sw_uninstall_script',
			'sw_env_var', 'sw_img_path']

	DEFAULTS = {'suuid': '0', 'patch_bundle_id': 'NA', 'auto_patch': 0, 'sState': 0, 'sName': 'NA',
				'sVendor': 'NA', 'sVersion': 'NA', 'sDescription': 'NA', 'sVendorURL': 'NA', 'sReboot': 0,
				'sw_type': 'NA', 'sw_url': 'NA', 'sw_size': 0, 'sw_hash': 'NA', 'sw_pre_install_script': 'NA',
				'sw_post_install_script': 'NA', 'sw_uninstall_script': 'NA', 'sw_env_var': 'NA',
				'sw_img_path': 'NA' }

	INTKEYS = ['sState', 'auto_patch', 'sw_size', 'sReboot']

	def __init__(self, initial_data=None):
		for key in self.KEYS:
				setattr(self, key, 'NA')
		try:
			if initial_data is not None:
				for k in initial_data:
					if k in self.KEYS:
						_val = initial_data[k]
						if k in self.INTKEYS:
							# All Values are Strings to the client
							_val = str(_val)

						setattr(self, k, _val)

			print self.__dict__

		except Exception as e:
			exc_type, exc_obj, exc_tb = sys.exc_info()
			print('[Line: %d] Message: %s' % (exc_tb.tb_lineno, e.message))



	def asDict(self):
		b64Keys = ['sw_post_install_script', 'sw_pre_install_script', 'sw_uninstall_script']
		res = self.__dict__
		for k in b64Keys:
			_res = res[k]
			if _res != "NA" and _res != None and len(_res) >= 3:
				res[k] = base64.b64encode(_res)

		return res

class SWObjCri(object):
	KEYS = ['os_type', 'arch_type', 'os_vers']
	DEFAULTS = {'os_type': 'Mac OS X, Mac OS X Server', 'arch_type': 'X86', 'os_vers': '*'}

	def __init__(self, initial_data=None):
		for d in self.KEYS:
			setattr(self, d, self.DEFAULTS[d])

		if initial_data is not None:
			for key in initial_data:
				if key in self.KEYS:
					setattr(self, key, initial_data[key])

	def importDict(self,data):
		if data is not None:
			for key in data:
				if key in self.KEYS:
					setattr(self, key, data[key])

	def asDict(self):
		res = self.__dict__
		return res



