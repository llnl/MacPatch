from mpapi.model import MpServerList, MpServer, MpAsusCatalogList, MpAsusCatalog


class Server(object):
	"""Client-facing view of an MpServer row."""

	def __init__(self):
		self.host = "localhost"
		self.port = "2600"
		self.useHTTPS = 1
		self.allowSelfSigned = 0
		self.useTLSAuth = 0
		self.serverType = 0

	def importFromRowReturnDictionary(self, row):
		fields = {'host': 'server', 'port': 'port', 'useHTTPS': 'useSSL',
				  'allowSelfSigned': 'allowSelfSignedCert', 'useTLSAuth': 'useSSLAuth'}
		for attr, column in fields.items():
			setattr(self, attr, row[column])

		if int(row['isMaster']) == 1:
			self.serverType = 0
		elif int(row['isProxy']) == 0:
			self.serverType = 1
		else:
			self.serverType = 2

		return dict(self.__dict__)


def serverListForID(list_id):
	"""MacPatch servers for a server list: {'version': int, 'data': [server dicts]}."""
	server_list = MpServerList.query.filter(MpServerList.name == "Default", MpServerList.listid == list_id).first()
	if server_list is None:
		return {'version': 0, 'data': []}

	rows = MpServer.query.filter(MpServer.active == 1, MpServer.listid == list_id).all()
	return {'version': server_list.version,
			'data': [Server().importFromRowReturnDictionary(row.asDict) for row in rows]}


def suServerListForID(list_id, os_ver):
	"""Software update catalogs for an OS version: {'version': int|str, 'data': [catalog dicts]}."""
	catalog_list = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == list_id).first()
	if catalog_list is None:
		return {'version': '0', 'data': []}

	major, minor = os_ver.split('.')[:2]
	catalogs = (MpAsusCatalog.query
				.filter(MpAsusCatalog.os_major == int(major), MpAsusCatalog.os_minor == int(minor))
				.order_by(MpAsusCatalog.c_order.asc()).all())

	return {'version': catalog_list.version,
			'data': [{'CatalogURL': c.catalog_url, 'serverType': 1 if c.proxy == 1 else 0} for c in catalogs]}
