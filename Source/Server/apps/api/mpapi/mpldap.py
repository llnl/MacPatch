from ldap3 import Server, Connection, ALL, SUBTREE, ALL_ATTRIBUTES, BASE
from ldap3 import ServerPool, FIRST, ROUND_ROBIN
from ldap3.core.exceptions import LDAPExceptionError, LDAPBindError

import dns.resolver

class MPldap():

	def __init__(self, app):
		self.app = app
		self.config = app.config
		self.ldap_servers = []
		self.setupLDAPServers()

	def setupLDAPServers(self):
		_servers = []
		if self.config['LDAP_SRVC_MULTISERVER']:
			answers = dns.resolver.query(self.config['LDAP_SRVC_SERVER'], 'A')
			for rdata in answers:
				_servers.append(Server(str(rdata), port=self.config['LDAP_SRVC_PORT'], use_ssl=True, get_info=ALL, mode='IP_V4_PREFERRED'))	
			
			self.log_Debug(f"LDAP_SRVC_POOL_TYPE = {self.config['LDAP_SRVC_POOL_TYPE']}")
			if self.config['LDAP_SRVC_POOL_TYPE'] == 'ROUND_ROBIN':
				self.ldap_servers = ServerPool(_servers, ROUND_ROBIN, active=True)
			else:
				self.ldap_servers = ServerPool(_servers, FIRST, active=True)
		else:
			_servers.append(Server(self.config['LDAP_SRVC_SERVER'], port=self.config['LDAP_SRVC_PORT'], use_ssl=True, get_info=ALL, mode='IP_V4_PREFERRED'))
			self.ldap_servers = ServerPool(_servers)
		
	def findOUN(self, oun):
		try:
			conn = Connection(self.ldap_servers, user=self.config['LDAP_SRVC_USERDN'], password=self.config['LDAP_SRVC_PASS'], auto_bind=True)
			didBind = conn.bind()

			search_criteria = f"(&(objectClass=*)(sAMAccountName={oun}))"
			didSearch = conn.search(search_base=self.config['LDAP_SRVC_SEARCHBASE'], search_filter=search_criteria,
									search_scope=SUBTREE, attributes=['distinguishedName'], get_operational_attributes=True)

			res = conn.entries
			if len(res) == 1:
				self.log_Info(f"[findOUN] OUN {oun} was found in directory")
				return res[0].distinguishedName
			else:
				self.log_Error(f"[findOUN] OUN {oun} not found in directory")
		
		except LDAPExceptionError as lErr:
			self.log_Error(lErr)
			return None
		
	def authOUN(self, ounDN, oun, ounPass):
		try:
			_conn = Connection(self.ldap_servers, user=str(ounDN), password=str(ounPass), auto_bind=True, auto_referrals=False)
			didBind = _conn.bind()
				
			_search_criteria = f"(&(objectClass=*)(sAMAccountName={oun}))"
			didSearch = _conn.search(search_base=self.config['LDAP_SRVC_SEARCHBASE'], search_filter=_search_criteria,
										search_scope=SUBTREE, attributes=ALL_ATTRIBUTES, 
										get_operational_attributes=True)
			
			res = _conn.entries

			if not didSearch:
				_conn.unbind()
				self.log_Error(f"Error unable to find user sAMAccountName={oun} info in directory ({self.config['LDAP_SRVC_SEARCHBASE']}).")
				return False
			else:
				_conn.unbind()
				self.log_Error(f"[authOUN] Was able to authenticate {oun}")
				return True
			
		except LDAPBindError:
			self.log_Error(f"Authentication was not successful for user '{oun}'")
		except Exception as lErr:
			self.log_Error(lErr)
			
	def isUserInGroup(self, user_cn, groupName):
		try:
			conn = Connection(self.ldap_servers, user=self.config['LDAP_SRVC_USERDN'], password=self.config['LDAP_SRVC_PASS'], auto_bind=True)
			didBind = conn.bind()

			group_filter_str = '(&(objectClass=GROUP)(cn={group_name}))'
			filter = group_filter_str.replace('{group_name}', groupName)
			conn.search(search_base=self.config['LDAP_SRVC_SEARCHBASE'],search_filter=filter, search_scope=SUBTREE, attributes=ALL_ATTRIBUTES)

			members = []
			for entry in conn.response:
				if 'member' in entry['attributes']:
					for m in entry['attributes']['member']:
						members.append(m)

			if len(members) > 0:
				for member in members:
					_cn = self.getMemberCN(conn, member)
					if _cn == user_cn:
						return True

			conn.unbind()
			self.log_Info(f"Unable to find {user_cn} in group {groupName} using search base {self.config['LDAP_SRVC_SEARCHBASE']}")
			return False
				
		except LDAPBindError:
			self.log_Error(f"[isUserInGroup] Authentication was not successful.")
			return False
		except Exception as lErr:
			self.log_Error(lErr)
			return False

	def getMemberCN(self, ldap_conn, memberDN):
		if ldap_conn.bind():
			ldap_conn.search(search_base=memberDN, search_filter='(objectClass=*)', search_scope=BASE, attributes='cn')

			if len(ldap_conn.entries) == 1:
				return ldap_conn.entries[0]['cn']

		return None
	
	# Logging

	def log(self, logString):
		if self.config['LOGGING_LEVEL'].lower() == 'info':
			self.app.logger.info(logString)
		elif self.config['LOGGING_LEVEL'].lower() == 'debug':
			self.app.logger.debug(logString)
		elif self.config['LOGGING_LEVEL'].lower() == 'warning':
			self.app.logger.warning(logString)
		elif self.config['LOGGING_LEVEL'].lower() == 'error':
			self.app.logger.error(logString)
		elif self.config['LOGGING_LEVEL'].lower() == 'critical':
			self.app.logger.critical(logString)
		else:
			self.app.logger.info(logString)

	def log_Crit(self, logString):
		self.app.logger.critical(logString)

	def log_Error(self, logString):
		self.app.logger.error(logString)

	def log_Warn(self, logString):
		self.app.logger.warning(logString)

	def log_Info(self, logString):
		self.app.logger.info(logString)

	def log_Debug(self, logString):
		self.app.logger.debug(logString)
