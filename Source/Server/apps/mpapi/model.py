from mpapi import db

# Rev 15
#

from datetime import *
from sqlalchemy import BigInteger, Column, DateTime, Integer, LargeBinary, String, Text, ForeignKey, Boolean
from sqlalchemy.dialects.mysql import LONGTEXT, MEDIUMTEXT, TEXT, INTEGER

from flask_login import UserMixin
from werkzeug.security import check_password_hash, generate_password_hash

class CommonBase(db.Model):
	__abstract__ = True
	__tablelabel__ = ''

	@property
	def asDict(self):
		"""Convert date/datetime to string inorder to jsonify"""
		result = {}
		for column in self.__table__.columns:
			if column.name != "rid":
				try:
					if column.type.python_type in [type(date(2000, 1, 1)), type(datetime(2000, 1, 1))]:
						if getattr(self, column.name) is not None:
							result[column.name] = str(getattr(self, column.name))
						else:
							# don't convert None to string
							result[column.name] = getattr(self, column.name)
					else:
						result[column.name] = getattr(self, column.name)
				except Exception as e:
					result[column.name] = getattr(self, column.name)

		return result

	@property
	def asDictWithRID(self):
		"""Convert date/datetime to string inorder to jsonify"""
		result = {}
		for column in self.__table__.columns:
			try:
				if column.type.python_type in [type(date(2000, 1, 1)), type(datetime(2000, 1, 1))]:
					if getattr(self, column.name) is not None:
						result[column.name] = str(getattr(self, column.name))
					else:
						# don't convert None to string
						result[column.name] = getattr(self, column.name)
				else:
					result[column.name] = getattr(self, column.name)
			except Exception as e:
				result[column.name] = getattr(self, column.name)

		return result

	@property
	def columns(self):
		results = []
		for column in self.__table__.columns:
			if column.name != "rid":
				results.append(column.name)

		return results

	@property
	def columnsAlt(self):
		results = []
		for column in self.__table__.columns:
			if column.name != "rid" or column.name != "date" or column.name != "mdate" or column.name != "rid":
				results.append(column.name)

		return results

	@property
	def hasColumn(self, col):
		result = False
		for column in self.__table__.columns:
			if column.name != col:
				result = True
				break

		return result


def get_class_by_tablename(tablename):
	"""Return class reference mapped to table.

	:param tablename: String with name of table.
	:return: Class reference or None.
	"""
	for c in list(CommonBase._decl_class_registry.values()):
		if hasattr(c, '__tablename__') and c.__tablename__ == tablename:
			return c

	return None

''' Database Tables '''

# LDAP
class User(UserMixin):
	def __init__(self, username, data):
		self.username = username
		self.data = data

	@property
	def password(self):
		raise AttributeError('password: write-only field')

	@password.setter
	def password(self, password):
		self.password_hash = generate_password_hash(password)

	def check_password(self, password):
		return check_password_hash(self.password_hash, password)

	@staticmethod
	def get_by_username(username):
		return MPUser.query.filter_by(username=username).first()

	def __repr__(self):
		return "<User '{}'>".format(self.username)

# mp_user
class MPUser(CommonBase):
	__tablename__ = 'mp_user'

	rid             = Column(Integer, primary_key=True)
	username        = Column(String(80), unique=True)
	email           = Column(String(120), unique=True)
	password_hash   = Column(String(255))

# ------------------------------------------
''' START - Tables for Web Services'''

# ------------------------------------------
## Registration

# mp_agent_registration
class MPAgentRegistration(CommonBase):
	__tablename__ = 'mp_agent_registration'

	rid = Column(BigInteger, primary_key=True, autoincrement=True, info='rid')
	cuuid = Column(String(50), nullable=False, info='Client ID')
	enabled = Column(Integer, server_default='0', info='Enabled')
	clientKey = Column(String(100), server_default='NA')
	pubKeyPem = Column(MEDIUMTEXT())
	pubKeyPemHash = Column(MEDIUMTEXT())
	hostname = Column(String(255), nullable=False, info='Hostname')
	serialno = Column(String(255), nullable=False, info='Serial No')
	reg_date = Column(DateTime, nullable=False, server_default='1970-01-01 00:00:00', info='Reg Date')

# mp_clients_wait_reg
class MpClientsWantingRegistration(CommonBase):
	__tablename__ = 'mp_clients_wait_reg'

	rid = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True, info='rid')
	cuuid = Column(String(50), nullable=False, unique=True, info='Client ID')
	hostname = Column(String(255), nullable=False, info='Hostname')
	req_date = Column(DateTime, nullable=True, info='Request Date')

# mp_clients_reg_conf
class MpClientsRegistrationSettings(CommonBase):
	__tablename__ = 'mp_clients_reg_conf'

	rid = Column(Integer, primary_key=True, nullable=False, autoincrement=True)
	autoreg = Column(Integer, nullable=True, server_default='0')
	autoreg_key = Column(Integer, nullable=True, server_default='999999')
	client_parking = Column(Integer, nullable=True, server_default='0')

# mp_client_reg_keys
class MpClientRegKeys(CommonBase):
	__tablename__ = 'mp_client_reg_keys'

	rid = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	cuuid = Column(String(50), nullable=False, unique=True)
	regKey = Column(String(255), nullable=False)
	active = Column(Integer, nullable=True, server_default='1')
	reg_date = Column(DateTime, nullable=True, server_default='1970-01-01 00:00:00')

# mp_reg_keys
class MpRegKeys(CommonBase):
	__tablename__ = 'mp_reg_keys'

	rid = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True, info='rid')
	regKey = Column(String(255), nullable=False, info='Registration Key')
	keyType = Column(Integer, nullable=True, server_default='0', info='Key Type')
	keyQuery = Column(String(255), nullable=False, info='Key Query')
	active = Column(Integer, nullable=True, server_default='1', info='Active')
	validFromDate = Column(DateTime, nullable=True, server_default='1970-01-01 00:00:00', info='Date - Available From')
	validToDate = Column(DateTime, nullable=True, server_default='1970-01-01 00:00:00', info='Date - Available To')

# mp_site_keys
class MpSiteKeys(CommonBase):
	__tablename__ = 'mp_site_keys'

	rid = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	pubKey = Column(MEDIUMTEXT(), nullable=False)
	pubKeyHash = Column(String(255), nullable=False)
	priKey = Column(MEDIUMTEXT(), nullable=False)
	priKeyHash = Column(String(255), nullable=False)
	active = Column(Integer, nullable=True, server_default='1')
	request_new_key = Column(Integer, nullable=True, server_default='0')
	mdate = Column(DateTime, nullable=True, server_default='1970-01-01 00:00:00')

# mp_server_log_req
class MpServerLogReq(CommonBase):
	__tablename__ = 'mp_server_log_req'

	rid = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	uuid = Column(String(50), nullable=False)
	dts = Column(String(255), nullable=False)
	type = Column(String(255), nullable=False)

# ------------------------------------------
## Main

# mp_clients
class MpClient(CommonBase):
	__tablename__ = 'mp_clients'

	rid             = Column(BigInteger, primary_key=True, doc='99', autoincrement=True)
	cuuid           = Column(String(50), nullable=False, index=True, unique=True, info='ClientID', doc='0')
	mdate           = Column(DateTime, server_default='1970-01-01 00:00:00', info='Mod Date', doc='98')
	serialno        = Column(String(100), server_default='NA', info='Serial No', doc='6')
	hostname        = Column(String(255), server_default='NA', index=True, info='Host Name', doc='1')
	computername    = Column(String(255), server_default='NA', index=True, info='Computer Name', doc='2')
	ipaddr          = Column(String(64), server_default='NA', index=True, info='IP Address', doc='7')
	macaddr         = Column(String(64), server_default='NA', info='MAC Address', doc='8')
	osver           = Column(String(255), server_default='NA', info='OS Ver', doc='9')
	ostype          = Column(String(255), server_default='NA', info='OS Type', doc='12')
	consoleuser     = Column(String(255), server_default='NA', info='Console User', doc='10')
	needsreboot     = Column(String(255), server_default='NA', info='Needs Reboot', doc='11')
	agent_version   = Column(String(20), server_default='NA', info='Agent Ver', doc='3')
	agent_build     = Column(String(10), server_default='0', info='Agent Build', doc='4')
	client_version  = Column(String(20), server_default='NA', info='Client Ver', doc='5')
	fileVaultStatus = Column(String(255), nullable=True, server_default='NA', info='FileVault Status', doc='13')
	firmwareStatus  = Column(String(255), nullable=True, server_default='NA', info='Firmware Status', doc='14')
	hasPausedPatching = Column(String(1), server_default='0', info='Patching Paused', doc='15')
	depEnrolled 	= Column(String(50), server_default='NA', info='DEP Enrolled', doc='16')
	mdmEnrolled 	= Column(String(50), server_default='NA', info='MDM Enrolled', doc='17')

# mp_clients_plist
class MpClientPlist(CommonBase):
	# Deprecated as of MP3.1
	__tablename__ = 'mp_clients_plist'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid               = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=True)
	mdate               = Column(DateTime, nullable=True, server_default='1970-01-01 00:00:00')
	EnableASUS          = Column(String(255), server_default='NA')
	MPDLTimeout         = Column(String(255), server_default='NA')
	AllowClient         = Column(String(255), server_default='NA')
	MPServerSSL         = Column(String(255), server_default='NA')
	Domain              = Column(String(255), server_default='NA', index=True)
	Name                = Column(String(255), server_default='NA')
	MPInstallTimeout    = Column(String(255), server_default='NA')
	MPServerDLLimit     = Column(String(255), server_default='NA')
	PatchGroup          = Column(String(255), server_default='NA', index=True)
	MPProxyEnabled      = Column(String(255), server_default='NA')
	Description         = Column(String(255), server_default='NA')
	MPDLConTimeout      = Column(String(255), server_default='NA')
	MPProxyServerPort   = Column(String(255), server_default='NA')
	MPProxyServerAddress = Column(String(255), server_default='NA')
	AllowServer         = Column(String(255), server_default='NA')
	MPServerAddress     = Column(String(255), server_default='NA')
	MPServerPort        = Column(String(255), server_default='NA')
	MPServerTimeout     = Column(String(255), server_default='NA')
	Reboot              = Column(String(255), server_default='NA')
	DialogText          = Column(String(255), server_default='NA')
	PatchState          = Column(String(255), server_default='NA')
	ClientScanInterval  = Column(String(255), server_default='NA')
	MPAgentExecDebug    = Column(String(255), server_default='NA')
	MPAgentDebug        = Column(String(255), server_default='NA')
	SWDistGroup         = Column(String(255), server_default='NA')
	CheckSignature      = Column(String(255), server_default='NA')
	SWDistGroupState    = Column(String(255), server_default='NA')

# mp_client_groups
class MpClientGroups(CommonBase):
	__tablename__ = 'mp_client_groups'

	rid             = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id        = Column(String(50), nullable=False, index=True, unique=True, info="Group ID")
	group_name      = Column(String(255), nullable=False, index=True, unique=True, info="Group Name")
	group_owner     = Column(String(255), server_default='NA', index=True, info="Group Owner")

# mp_client_group_admins
class MpClientGroupAdmins(CommonBase):
	__tablename__ = 'mp_client_group_admin'

	rid             = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id        = Column(String(50), nullable=False, index=True, unique=False)
	group_admin     = Column(String(255), nullable=False, index=True, unique=False)

# mp_client_group_members
class MpClientGroupMembers(CommonBase):
	__tablename__ = 'mp_client_group_members'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id    = Column(String(50), nullable=False, index=True, unique=False)
	cuuid       = Column(String(255), nullable=False, index=True, unique=False)

# mp_client_group_software
class MpClientGroupSoftware(CommonBase):
	__tablename__ = 'mp_client_group_software'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id    = Column(String(50), nullable=False, index=True, unique=False)
	tuuid       = Column(String(50), nullable=False, index=True, unique=False)

# mp_client_group_software_restrictions
class MpClientGroupSoftwareRestrictions(CommonBase):
	__tablename__ = 'mp_client_group_software_restrictions'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id    = Column(String(50), nullable=False, index=True, unique=False)
	appID       = Column(String(50), nullable=False, index=True, unique=False)
	enabled 	= Column(INTEGER(unsigned=True), nullable=False)

# mp_client_tasks
class MpClientTasks(CommonBase):
	__tablename__ = 'mp_client_tasks'

	rid             = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id        = Column(String(50), nullable=False, index=True, unique=False)

	id  			= Column(INTEGER(4, unsigned=True),   info="Task ID")
	name 			= Column(String(255), nullable=False, info="Name")
	cmd 			= Column(String(255), nullable=False, info="Command")
	description 	= Column(String(255), nullable=False, info="Description")
	active 			= Column(String(255), nullable=False, info="Active", server_default='1')
	startdate 		= Column(String(255), nullable=False, info="Start Date", server_default='2016-01-01')
	enddate 		= Column(String(255), nullable=False, info="End Date", server_default='2050-01-01')
	interval 		= Column(String(255), nullable=False, info="Interval")
	idrev 			= Column(String(255), nullable=False, info="Task Revision", server_default='1')
	parent 			= Column(String(255), nullable=False, info="Parent", server_default='0')
	scope 			= Column(String(255), nullable=False, info="Scope", server_default='Global')
	cmdalt 			= Column(String(255), nullable=False, info="Alt Command", server_default='0')
	mode 			= Column(String(255), nullable=False, info="Mode", server_default='0')
	idsig 			= Column(String(255), nullable=False, info="Signature", server_default='0')

# mp_group_config
class MPGroupConfig(CommonBase):
	__tablename__ = 'mp_group_config'

	rid = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id = Column(String(50), index=True, nullable=False)
	rev_settings = Column(BigInteger, server_default='1')
	rev_tasks = Column(BigInteger, server_default='1')
	tasks_version = Column(BigInteger, server_default='0')
	restrictions_version = Column(BigInteger, server_default='0')

# mp_client_settings
class MpClientSettings(CommonBase):
	__tablename__ = 'mp_client_settings'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id    = Column(String(50), index=True, nullable=False)
	key         = Column(String(255), index=True, nullable=False)
	value       = Column(String(255), nullable=False)

# ------------------------------------------
## Patches Needed

# mp_client_patches
class MpClientPatches(CommonBase):
	__tablename__ = 'mp_client_patches'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid       = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, info="Client ID")
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00', info="Mod Date")
	type        = Column(String(10), nullable=False, info="Type")
	type_int    = Column(INTEGER(unsigned=True), nullable=False, info="Type Int")
	patch       = Column(String(255), nullable=False, info="Patch")
	patch_id    = Column(String(255), nullable=True, info="Patch ID")
	bundle_id   = Column(String(255), nullable=True, info="Bundle ID")
	version     = Column(String(255), nullable=False, info="Version")
	description = Column(Text, nullable=True, info="Description")
	restart     = Column(String(255), nullable=False, info="Reboot")

# mp_client_patches_apple
class MpClientPatchesApple(CommonBase):
	__tablename__ = 'mp_client_patches_apple'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid       = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True)
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00')
	patch       = Column(String(255), nullable=False)
	type        = Column(String(255), nullable=False)
	description = Column(String(255), nullable=False)
	size        = Column(String(255), nullable=False)
	recommended = Column(String(255), nullable=False)
	restart     = Column(String(255), nullable=False)
	version     = Column(String(255))

# mp_client_patches_third
class MpClientPatchesThird(CommonBase):
	__tablename__ = 'mp_client_patches_third'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid       = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True)
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00')
	patch       = Column(String(255), nullable=False)
	type        = Column(String(255), nullable=False)
	description = Column(String(255), nullable=False)
	size        = Column(String(255), nullable=False)
	recommended = Column(String(255), nullable=False)
	restart     = Column(String(255), nullable=False)
	patch_id    = Column(String(255), nullable=False)
	version     = Column(String(255))
	bundleID    = Column(String(255))

# ------------------------------------------
## Patch Content

# apple_patches
class ApplePatch(CommonBase):
	__tablename__ = 'apple_patches'

	rid              = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	akey             = Column(String(50), nullable=False, info="AKEY")
	description      = Column(Text, info="Description")
	description64    = Column(LONGTEXT)
	osver_support    = Column(String(20), nullable=False, server_default="NA", info="OS Version")
	patch_state      = Column(String(10), server_default="Create", info="Patch State")
	patchname        = Column(String(255), nullable=False, server_default="NA", info="Patch Name")
	postdate         = Column(DateTime, server_default='1970-01-01 00:00:00', info="Post Date")
	restartaction    = Column(String(20), nullable=False, info="Reboot")
	severity         = Column(String(10), nullable=False,  server_default='High', info="Severity")
	severity_int     = Column(Integer, server_default="3")
	supatchname      = Column(String(255), nullable=False, info="Patch Name Alt")
	title            = Column(String(255), nullable=False, info="Title")
	version          = Column(String(20), nullable=False, info="Version")

# apple_patches_additions
class ApplePatchAdditions(CommonBase):
	__tablename__ = 'apple_patches_mp_additions'

	rid                     = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	version                 = Column(String(20), nullable=False)
	supatchname             = Column(String(100))
	severity                = Column(String(10), nullable=False,  server_default='High')
	severity_int            = Column(INTEGER(unsigned=True), server_default="3")
	patch_state             = Column(String(100), nullable=False, server_default="Create")
	patch_install_weight    = Column(INTEGER(unsigned=True), server_default="60")
	patch_reboot            = Column(INTEGER(unsigned=True), server_default="0")
	osver_support           = Column(String(10), nullable=False, server_default="NA")
	user_install            = Column(INTEGER(1), server_default="0")

# mp_apple_patch_criteria
class ApplePatchCriteria(CommonBase):
	__tablename__ = 'mp_apple_patch_criteria'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	puuid       = Column(String(50), nullable=False, server_default='1')
	supatchname = Column(String(255), nullable=True)
	type        = Column(String(25))
	type_data   = Column(MEDIUMTEXT())
	type_action = Column(INTEGER(1, unsigned=True), server_default='0')
	type_order  = Column(INTEGER(2, unsigned=True), server_default='0')
	cdate       = Column(DateTime, server_default='1970-01-01 00:00:00')
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00')

# mp_patches
class MpPatch(CommonBase):
	__tablename__ = 'mp_patches'

	rid                     = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	puuid                   = Column(String(50), primary_key=True, nullable=False, info="Patch ID")
	patch_name              = Column(String(100), nullable=False, info="Patch Name")
	patch_ver               = Column(String(20), nullable=False, info="Patch Version")
	patch_vendor            = Column(String(255), server_default="NA", info="Patch Vendor")
	description             = Column(String(255), info="Description")
	description_url         = Column(String(255), info="Description URL")
	bundle_id               = Column(String(50), nullable=False, server_default="gov.llnl.Default", info="Bundle ID")
	patch_install_weight    = Column(Integer, server_default="30", info="Patch Install Weight")
	patch_severity          = Column(String(10), nullable=False, info="Severity")
	patch_reboot            = Column(String(3), nullable=False, info="Reboot")
	patch_state             = Column(String(10), nullable=False, info="State")
	cve_id                  = Column(String(255), info="CVE")
	active                  = Column(INTEGER(1, unsigned=True), server_default="0", info="Active")
	pkg_preinstall          = Column(Text, info="Preinstall Script")
	pkg_postinstall         = Column(Text, info="Postinstall Script")
	pkg_name                = Column(String(100), info="Package")
	pkg_size                = Column(String(100), server_default="0", info="Package Size")
	pkg_hash                = Column(String(100), info="Package Hash")
	pkg_path                = Column(String(255), info="Package Path")
	pkg_url                 = Column(String(255), info="Package URL")
	pkg_env_var             = Column(String(255), info="Package Env")
	pkg_useS3 				= Column(INTEGER(1, unsigned=True), server_default="0", info="Active")
	pkg_S3path 				= Column(String(255), info="S3 Path")
	cdate                   = Column(DateTime, server_default='1970-01-01 00:00:00', info="Create Date")
	mdate                   = Column(DateTime, server_default='1970-01-01 00:00:00', info="Modify Date")

# mp_patches_criteria
class MpPatchesCriteria(CommonBase):
	__tablename__ = 'mp_patches_criteria'

	rid                 = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	puuid               = Column(String(50), primary_key=True, nullable=False)
	type                = Column(String(50), nullable=False)
	type_data           = Column(Text, nullable=False)
	type_order          = Column(Integer, nullable=False)
	type_required_order = Column(Integer, nullable=False, server_default="0")

# mp_patches_requisits
class MpPatchesRequisits(CommonBase):
	__tablename__ = 'mp_patches_requisits'

	rid           = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	puuid         = Column(String(50))
	type          = Column(Integer, server_default='0')
	type_txt      = Column(String(255))
	type_order    = Column(Integer, server_default='0')
	puuid_ref     = Column(String(50))

# mp_installed_patches
class MpInstalledPatch(CommonBase):
	__tablename__ = 'mp_installed_patches'

	rid         = Column(BigInteger, primary_key=True, info='rid', autoincrement=True)
	cuuid       = Column(String(50), nullable=False, info='ClientID')
	mdate       = Column(DateTime, nullable=False, server_default='1970-01-01 00:00:00', info='Install Date', doc=99)
	patch       = Column(String(255), nullable=False, info='Patch')
	patch_name  = Column(String(255), server_default="NA", info='Patch Name')
	type        = Column(String(255), nullable=False, info='Patch Type')
	type_int    = Column(Integer)
	server_name = Column(String(255), server_default="NA", info='Server Name')

# ------------------------------------------
## Patch Groups and Content

# mp_patch_group
class MpPatchGroup(CommonBase):
	__tablename__ = 'mp_patch_group'

	rid     = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	name    = Column(String(255), nullable=False, index=True, unique=True, info="Name")
	id      = Column(String(50), nullable=False, info="Group ID")
	type    = Column(Integer, nullable=False, server_default="0", info="Type")
	hash    = Column(String(50), server_default="0")
	mdate   = Column(DateTime, server_default='1970-01-01 00:00:00', info="Updated Last")

# mp_patch_group_members
class PatchGroupMembers(CommonBase):
	__tablename__ = 'mp_patch_group_members'

	rid             = Column(BigInteger, primary_key=True, autoincrement=True)
	user_id         = Column(String(255), nullable=False, info="User ID")
	patch_group_id  = Column(String(50), nullable=False, info="Patch Group ID")
	is_owner        = Column(INTEGER(1, unsigned=True), server_default='0', info="Owner")

# mp_patch_group_data
class MpPatchGroupData(CommonBase):
	__tablename__ = 'mp_patch_group_data'

	rid         = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	pid         = Column(String(50), primary_key=True, nullable=False)
	hash        = Column(String(50), nullable=False)
	rev         = Column(BigInteger, server_default="-1")
	data        = Column(LONGTEXT(), nullable=False)
	data_type   = Column(String(4), server_default="")
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00')

# mp_patch_group_patches
class MpPatchGroupPatches(CommonBase):
	__tablename__ = 'mp_patch_group_patches'

	rid             = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	patch_id        = Column(String(50), nullable=False, index=True)
	patch_group_id  = Column(String(50), nullable=False, index=True)

# ------------------------------------------
## Client Agent

# mp_client_agents
class MpClientAgent(CommonBase):
	__tablename__ = 'mp_client_agents'

	rid 		= Column(BigInteger, primary_key=True, autoincrement=True)
	puuid 		= Column(String(50), nullable=False)
	type 		= Column(String(10), nullable=False, info="Type")
	osver 		= Column(String(255), nullable=False, server_default="*", info="OS Ver")
	agent_ver 	= Column(String(10), nullable=False, info="Agent Ver")
	version 	= Column(String(10), info="Version")
	build 		= Column(String(10), info="Build")
	pkg_name 	= Column(String(100), nullable=False, info="Package")
	pkg_url 	= Column(String(255), info="Package URL")
	pkg_hash 	= Column(String(50), info="Package Hash")
	active 		= Column(Integer, nullable=False, server_default="0", info="Active")
	state 		= Column(Integer, nullable=False, server_default="0", info="State")
	cdate 		= Column(DateTime, server_default='1970-01-01 00:00:00', info="Create Date")
	mdate 		= Column(DateTime, server_default='1970-01-01 00:00:00', info="Mod Date")

# mp_client_agents_filters
class MpClientAgentsFilter(CommonBase):
	__tablename__ = 'mp_client_agents_filters'

	rid 				= Column(BigInteger, primary_key=True, autoincrement=True)
	type 				= Column(String(255), nullable=False, info="Type")
	attribute 			= Column(String(255), nullable=False, info="Attribute")
	attribute_oper 		= Column(String(10), nullable=False, info="Operator")
	attribute_filter 	= Column(String(255), nullable=False, info="Filter")
	attribute_condition = Column(String(10), nullable=False, info="Condition")

# mp_client_agent_plugins
class MpClientAgentPlugins(CommonBase):
	__tablename__ = 'mp_client_agent_plugins'

	rid 				= Column(BigInteger, primary_key=True, autoincrement=True)
	puuid 				= Column(String(50), nullable=False)
	plugin				= Column(String(255), info="Plugin")
	bundleIdentifier	= Column(String(255), info="Bundle Identifier")
	version				= Column(String(10), info="Version")

# mp_client_agent_profiles
class MpClientAgentProfiles(CommonBase):
	__tablename__ = 'mp_client_agent_profiles'

	rid 			= Column(BigInteger, primary_key=True, autoincrement=True)
	puuid 			= Column(String(50), nullable=False)
	displayName		= Column(String(255), info="Display Name")
	identifier		= Column(String(255), info="Identifier")
	organization	= Column(String(255), info="Organization")
	version			= Column(String(10), info="Version")
	fileName		= Column(String(255), info="File Name")


# ------------------------------------------
## AntiVirus

# av_info
class AvInfo(CommonBase):
	__tablename__ = 'av_info'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid       = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=True)
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00')
	av_type     = Column(String(255), server_default="NA")
	app_name    = Column(String(255), server_default="NA")
	app_path    = Column(String(255), server_default="NA")
	app_version = Column(String(255), server_default="NA")
	eng_version = Column(String(255), server_default="NA")
	defs_date   = Column(String(50), server_default="NA")
	last_scan   = Column(DateTime, server_default='1970-01-01 00:00:00')

# av_defs
class AvDefs(CommonBase):
	__tablename__ = 'av_defs'

	rid             = Column(BigInteger, primary_key=True, autoincrement=True)
	mdate           = Column(DateTime, server_default='1970-01-01 00:00:00')
	engine          = Column(String(255), nullable=False)
	current         = Column(String(3), nullable=False)
	defs_date       = Column(DateTime, server_default='1970-01-01 00:00:00')
	defs_date_str   = Column(String(20), nullable=False)
	file            = Column(Text(), nullable=False)

# ------------------------------------------
## Inventory

# mp_inv_state
class MpInvState(CommonBase):
	__tablename__ = 'mp_inv_state'
	rid 	= Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid 	= Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=True)
	mdate 	= Column(DateTime, server_default='1970-01-01 00:00:00')

# rev 100005
# mp_inv_errors
class MpInvErrors(CommonBase):
	__tablename__ = 'mp_inv_errors'
	rid 	= Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid 	= Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=False)
	inv_table = Column(String(255), nullable=False)
	error_msg = Column(TEXT(), nullable=False)
	json_data = Column(LONGTEXT(), nullable=False)
	mdate 	= Column(DateTime, server_default='1970-01-01 00:00:00')

# rev 100005
# mp_inv_log
class MpInvLog(CommonBase):
	__tablename__ = 'mp_inv_log'
	rid 	= Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid 	= Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=False)
	mp_server = Column(String(255), nullable=False)
	inv_table = Column(String(255), nullable=False)
	error_no = Column(String(10), nullable=True)
	error_msg = Column(TEXT(), nullable=True)
	json_data = Column(LONGTEXT(), nullable=False)
	mdate 	= Column(DateTime, server_default='1970-01-01 00:00:00')

# ------------------------------------------
## Servers

# mp_asus_catalogs
class MpAsusCatalog(CommonBase):
	__tablename__ = 'mp_asus_catalogs'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	listid              = Column(Integer, nullable=False, server_default="1")
	catalog_url         = Column(String(255), nullable=False)
	os_minor            = Column(Integer, nullable=False)
	os_major            = Column(Integer, nullable=False)
	c_order             = Column(Integer)
	proxy               = Column(Integer, nullable=False, server_default="0")
	active              = Column(Integer, nullable=False, server_default="0")
	catalog_group_name  = Column(String(255), nullable=False)

# mp_asus_catalog_list
class MpAsusCatalogList(CommonBase):
	__tablename__ = 'mp_asus_catalog_list'

	rid     = Column(BigInteger, primary_key=True, autoincrement=True)
	listid  = Column(Integer, nullable=False)
	name    = Column(String(255), nullable=False)
	version = Column(Integer, nullable=False)

# mp_server_list
class MpServerList(CommonBase):
	__tablename__ = 'mp_server_list'

	rid     = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	listid  = Column(String(50), primary_key=True, nullable=False)
	name    = Column(String(255), nullable=False)
	version = Column(Integer, nullable=False, server_default="0")

# mp_servers
class MpServer(CommonBase):
	__tablename__ = 'mp_servers'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	listid              = Column(String(50), nullable=False)
	server              = Column(String(255), nullable=False)
	port                = Column(Integer, nullable=False, server_default="2600")
	useSSL              = Column(Integer, nullable=False, server_default="1")
	useSSLAuth          = Column(Integer, nullable=False, server_default="0")
	allowSelfSignedCert = Column(Integer, nullable=False, server_default="1")
	isMaster            = Column(Integer, nullable=False, server_default="0")
	isProxy             = Column(Integer, nullable=False, server_default="0")
	active              = Column(Integer, nullable=False, server_default="1")

# ------------------------------------------
## Profiles

# mp_os_config_profiles
class MpOsConfigProfiles(CommonBase):
	__tablename__ = 'mp_os_config_profiles'

	rid                 = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	profileID           = Column(String(50), primary_key=True, nullable=False)
	profileIdentifier   = Column(String(255))
	profileData         = Column(LargeBinary)
	profileName         = Column(String(255))
	profileDescription  = Column(Text)
	profileHash         = Column(String(50))
	profileRev          = Column(Integer)
	enabled             = Column(Integer, server_default='0')
	isglobal              = Column(INTEGER(1), server_default='0')
	uninstallOnRemove   = Column(Integer, server_default='1')
	cdate               = Column(DateTime, server_default='1970-01-01 00:00:00')
	mdate               = Column(DateTime, server_default='1970-01-01 00:00:00')

# mp_os_config_profiles_assigned
class MpOsConfigProfilesAssigned(CommonBase):
	__tablename__ = 'mp_os_config_profiles_assigned'

	rid         = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	profileID   = Column(String(50), primary_key=True, nullable=False)
	groupID     = Column(String(50), primary_key=True, nullable=False)

# mp_os_config_profiles_group_policy
class MpOsProfilesGroupAssigned(CommonBase):
	__tablename__ = 'mp_os_config_profiles_group_policy'

	rid 		= Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	gPolicyID 	= Column(String(50), nullable=False, info="Policy ID")
	profileID 	= Column(String(50), nullable=False, info="Profile ID")
	groupID 	= Column(String(50), nullable=False, info="Group ID")
	title 		= Column(String(255), info="Name")
	description = Column(Text,  info="Description")
	enabled 	= Column(INTEGER(1, unsigned=True), server_default='1', info="Enabled")

# mp_os_config_profiles_criteria
class MpOsProfilesCriteria(CommonBase):
	__tablename__ = 'mp_os_config_profiles_criteria'

	rid 		= Column(BigInteger, primary_key=True, autoincrement=True)
	gPolicyID 	= Column(String(50), nullable=False)
	type 		= Column(String(25))
	type_data 	= Column(MEDIUMTEXT())
	type_action = Column(INTEGER(1, unsigned=True), server_default='0')
	type_order 	= Column(INTEGER(2, unsigned=True), server_default='0')

# ------------------------------------------
## Software Restrictions

# mp_software_restrictions
class MpSoftwareRestrictions(CommonBase):
	__tablename__ = 'mp_software_restrictions'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	appID       = Column(String(50), nullable=False, index=True, unique=False)
	bundleID	= Column(String(50), nullable=True, unique=False)
	displayName = Column(String(255))
	processName = Column(String(255))
	message		= Column(Text)
	killProc 	= Column(INTEGER(1, unsigned=True), server_default='1')
	sendEmail 	= Column(INTEGER(1, unsigned=True), server_default='0')
	enabled 	= Column(INTEGER(1, unsigned=True), server_default='0')
	isglobal	= Column(INTEGER(1, unsigned=True), server_default='0')
	mdate 		= Column(DateTime, server_default='1970-01-01 00:00:00')


# ------------------------------------------
## Software

# mp_software
class MpSoftware(CommonBase):
	__tablename__ = 'mp_software'

	rid                 	= Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	suuid               	= Column(String(50), primary_key=True, nullable=False, info="Software ID")
	patch_bundle_id     	= Column(String(100), info="Patch Bundle ID")
	auto_patch          	= Column(Integer, nullable=False, server_default='0', info="Auto Patch")
	sState              	= Column(Integer, server_default='0', info="State", doc=70)
	sName              		= Column(String(255), nullable=False, info="Name")
	sVendor             	= Column(String(255), info="Vendor")
	sVersion            	= Column(String(40), nullable=False, info="Version")
	sDescription        	= Column(String(255), info="Description")
	sVendorURL          	= Column(String(255), info="Vendor URL")
	sReboot             	= Column(Integer, server_default='1', info="Reboot")
	sw_app_path 			= Column(TEXT(), info="SW App Path")
	sw_type             	= Column(String(10), info="SW Type")
	sw_path             	= Column(String(255), info="Patch")
	sw_url              	= Column(String(255), info="URL")
	sw_size             	= Column(BigInteger, server_default='0', info="Size")
	sw_hash             	= Column(String(50), info="Hash")
	sw_pre_install_script   = Column(LONGTEXT(), info="Preinstall Script")
	sw_post_install_script  = Column(LONGTEXT(), info="Postinstall Script")
	sw_uninstall_script     = Column(LONGTEXT(), info="Uninstall Script")
	sw_env_var              = Column(String(255), info="Install ENV")
	cdate                   = Column(DateTime, server_default='1970-01-01 00:00:00', info="Create Date", doc=99)
	mdate                   = Column(DateTime, server_default='1970-01-01 00:00:00', info="Mod Date", doc=98)
	sw_img_path 			= Column(TEXT(), info="SW Icon")

# mp_software_criteria
class MpSoftwareCriteria(CommonBase):
	__tablename__ = 'mp_software_criteria'

	rid                 = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	suuid               = Column(String(50), primary_key=True, nullable=False)
	type                = Column(String(50), nullable=False)
	type_data           = Column(Text, nullable=False)
	type_order          = Column(Integer, nullable=False)
	type_required_order = Column(Integer, nullable=False, server_default='0')

# mp_software_group_tasks
class MpSoftwareGroupTasks(CommonBase):
	__tablename__ = 'mp_software_group_tasks'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	sw_group_id         = Column(String(50), nullable=False)
	sw_task_id          = Column(String(50), nullable=False)
	selected            = Column(Integer, server_default='0')

# mp_software_groups
class MpSoftwareGroup(CommonBase):
	__tablename__ = 'mp_software_groups'

	rid             = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	gid             = Column(String(50), primary_key=True, nullable=False, info="Group ID")
	gName           = Column(String(255), nullable=False, info="Name")
	gDescription    = Column(String(255), info="Description")
	gType           = Column(Integer, nullable=False, server_default='0', info="Type")
	gHash           = Column(String(50), server_default='0', info="Group Hash")
	state           = Column(Integer, server_default='1', info="State")
	cdate           = Column(DateTime, server_default='1970-01-01 00:00:00', info="Create Date")
	mdate           = Column(DateTime, server_default='1970-01-01 00:00:00', info="Mod Date")

# mp_software_groups_filters
class MpSoftwareGroupFilters(CommonBase):
	__tablename__ = 'mp_software_groups_filters'

	rid                 = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	gid                 = Column(String(50), nullable=False)
	attribute           = Column(String(255))
	attribute_oper      = Column(String(255))
	attribute_filter    = Column(String(255))
	attribute_condition = Column(String(255))
	datasource          = Column(String(255))

# mp_software_groups_privs
class MpSoftwareGroupPrivs(CommonBase):
	__tablename__ = 'mp_software_groups_privs'

	rid     = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	gid     = Column(String(50), nullable=False)
	uid     = Column(String(255), nullable=False)
	isowner = Column(Integer, nullable=False, server_default='0')

# mp_software_installs
class MpSoftwareInstall(CommonBase):
	__tablename__ = 'mp_software_installs'

	rid             = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	cuuid           = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=False)
	tuuid           = Column(String(50))
	suuid           = Column(String(50))
	action          = Column(String(1), server_default='i')
	result          = Column(Integer)
	resultString    = Column(Text)
	cdate           = Column(DateTime, server_default='1970-01-01 00:00:00')

# mp_software_requisits
class MpSoftwareRequisits(CommonBase):
	__tablename__ = 'mp_software_requisits'

	rid           = Column(BigInteger, primary_key=True, nullable=False, autoincrement=True)
	suuid         = Column(String(50))
	type          = Column(Integer, server_default='0')
	type_txt      = Column(String(255))
	type_order    = Column(Integer, server_default='0')
	suuid_ref     = Column(String(50))

# mp_software_task
class MpSoftwareTask(CommonBase):
	__tablename__ = 'mp_software_task'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	tuuid               = Column(String(50), nullable=False)
	name                = Column(String(255), nullable=False)
	primary_suuid       = Column(String(50))
	active              = Column(Integer, server_default='0')
	sw_task_type        = Column(String(2), server_default='o')
	sw_task_privs       = Column(String(255), server_default='Global')
	sw_start_datetime   = Column(DateTime, server_default='1970-01-01 00:00:00')
	sw_end_datetime     = Column(DateTime, server_default='1970-01-01 00:00:00')
	mdate               = Column(DateTime, server_default='1970-01-01 00:00:00')
	cdate               = Column(DateTime, server_default='1970-01-01 00:00:00')

# mp_software_tasks_data
class MpSoftwareTasksData(CommonBase):
	__tablename__ = 'mp_software_tasks_data'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	gid         = Column(String(50), nullable=False)
	gDataHash   = Column(String(50), nullable=False)
	gData       = Column(LONGTEXT(), nullable=False)
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00')

# mp_software_tasks_data
class MpUploadRequest(CommonBase):
	__tablename__ = 'mp_upload_request'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	uid         = Column(String(255), nullable=False)
	requestid   = Column(String(50), nullable=False)
	enabled     = Column(Integer, server_default='1')
	cdate       = Column(DateTime, server_default='1970-01-01 00:00:00')

# ------------------------------------------
## Plugins

# mp_agent_plugins
class MPPluginHash(CommonBase):
	__tablename__ = 'mp_agent_plugins'

	rid 			= Column(BigInteger, primary_key=True, autoincrement=True)
	pluginName 		= Column(String(255), nullable=False, info="Name")
	pluginBundleID 	= Column(String(100), nullable=False, info="Bundle ID")
	pluginVersion 	= Column(String(20), nullable=False, info="Version")
	hash 			= Column(String(100), nullable=False, info="Hash")
	active 			= Column(Integer, server_default='0', info="Enabled")

# ------------------------------------------
## OS Migration

class OSMigrationStatus(CommonBase):
	__tablename__ = 'mp_os_migration_status'

	rid             = Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid           = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=True)
	startDateTime   = Column(DateTime, server_default='1970-01-01 00:00:00')
	stopDateTime    = Column(DateTime, server_default='1970-01-01 00:00:00')
	preOSVer        = Column(String(255), nullable=False)
	postOSVer       = Column(String(255))
	label           = Column(MEDIUMTEXT())
	migrationID     = Column(String(100), nullable=False)

''' STOP - Tables for Web Services'''
# ------------------------------------------

# ------------------------------------------
## Console

class AdmUsers(CommonBase, UserMixin):
	__tablename__ = 'mp_adm_users'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	user_id             = Column(String(255), nullable=False)
	user_pass           = Column(String(255), nullable=False)
	user_RealName       = Column(String(255))
	enabled             = Column(INTEGER(1, unsigned=True), server_default='1')

	def get_id(self):
		return str(self.rid)

	@property
	def password(self):
		raise AttributeError('password: write-only field')

	@password.setter
	def password(self, password):
		self.user_pass = generate_password_hash(password)

	def check_password(self, password):
		return check_password_hash(self.user_pass, password)

	@staticmethod
	def get_by_username(username):
		return MPUser.query.filter_by(user_id=username).first()

class AdmGroups(CommonBase):
	__tablename__ = 'mp_adm_groups'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id            = Column(String(255), nullable=False)
	group_name          = Column(String(255), nullable=False)
	enabled             = Column(INTEGER(1, unsigned=True), server_default='1')

class AdmUsersInfo(CommonBase):
	__tablename__ = 'mp_adm_users_info'
	# This table will replace mp_adm_group_users

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	user_id             = Column(String(255), nullable=False)
	user_type           = Column(INTEGER(1, unsigned=True), server_default='0')
	last_login          = Column(DateTime, server_default='1970-01-01 00:00:00')
	number_of_logins    = Column(INTEGER, server_default='0')
	enabled             = Column(INTEGER(1, unsigned=True), server_default='0')
	user_email          = Column(String(255))
	email_notification  = Column(INTEGER(1, unsigned=True), server_default='0')

	# Set Rights
	admin              = Column(INTEGER(1, unsigned=True), server_default='0')
	autopkg            = Column(INTEGER(1, unsigned=True), server_default='0')
	agentUpload        = Column(INTEGER(1, unsigned=True), server_default='0')
	apiAccess          = Column(INTEGER(1, unsigned=True), server_default='0')

class AdmGroupUsers(CommonBase):
	__tablename__ = 'mp_adm_group_users'

	rid                 = Column(BigInteger, primary_key=True, autoincrement=True)
	group_id            = Column(String(50), nullable=False, server_default='1')
	user_id             = Column(String(255), nullable=False)
	user_type           = Column(INTEGER(1, unsigned=True), server_default='0')
	last_login          = Column(DateTime, server_default='1970-01-01 00:00:00')
	number_of_logins    = Column(INTEGER, server_default='0')
	enabled             = Column(INTEGER(1, unsigned=True), server_default='0')
	authToken1          = Column(String(50))
	authToken2          = Column(String(50))
	user_email          = Column(String(255))
	email_notification  = Column(INTEGER(1, unsigned=True), server_default='0')

# ------------------------------------------
## Agent

# mp_agent_config
class AgentConfig(CommonBase):
	__tablename__ = 'mp_agent_config'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	aid         = Column(String(50), nullable=False)
	name        = Column(String(255), nullable=False)
	isDefault   = Column(INTEGER(1, unsigned=True))
	revision    = Column(String(50))

# mp_agent_config_data
class AgentConfigData(CommonBase):
	__tablename__ = 'mp_agent_config_data'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	aid         = Column(String(50), nullable=False)
	akey        = Column(String(255), nullable=False)
	akeyValue   = Column(String(255), nullable=False)
	enforced    = Column(INTEGER(1, unsigned=True), nullable=False, server_default='0')

# mp_agent_installs
class AgentInstall(CommonBase):
	__tablename__ = 'mp_agent_installs'

	rid 			= Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid 			= Column(String(50), nullable=False)
	agent_ver 		= Column(String(255), nullable=False)
	install_date 	= Column(DateTime, server_default='1970-01-01 00:00:00')

# ------------------------------------------
## Inventory

# mp_adhoc_reports
class AdHocReports(CommonBase):
	__tablename__ = 'mp_adhoc_reports'

	rid             = Column(BigInteger, primary_key=True, autoincrement=True)
	name            = Column(String(255), nullable=False)
	reportData      = Column(MEDIUMTEXT())
	owner           = Column(String(255), nullable=False)
	rights          = Column(INTEGER(1, unsigned=True), server_default='0')
	disabled        = Column(INTEGER(1, unsigned=True), server_default='0')
	disabledDate    = Column(DateTime, server_default='1970-01-01 00:00:00')

# mp_adhoc_reports
class InvReports(CommonBase):
	__tablename__ = 'mp_inv_reports'

	rid 		= Column(BigInteger, primary_key=True, autoincrement=True)
	name 		= Column(String(255), nullable=False)
	owner 		= Column(String(255), nullable=False)
	scope 		= Column(INTEGER(1, unsigned=True), server_default='0')
	rtable 		= Column(String(255), nullable=False)
	rcolumns 	= Column(LONGTEXT())
	rquery 		= Column(LONGTEXT())
	cdate 		= Column(DateTime, server_default='1970-01-01 00:00:00')
	mdate 		= Column(DateTime, server_default='1970-01-01 00:00:00')

# Required Inventory Tables
# mpi_DirectoryServices
class MPIDirectoryServices(CommonBase):
	__tablename__ = 'mpi_DirectoryServices'

	rid         = Column(BigInteger, primary_key=True, autoincrement=True)
	cuuid       = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=True)
	mdate       = Column(DateTime, server_default='1970-01-01 00:00:00')
	mpa_cn                  = Column(String(255))
	mpa_AD_Kerberos_ID      = Column(String(255))
	mpa_HasSLAM             = Column(String(255))
	mpa_distinguishedName   = Column(String(255), index=True)
	mpa_AD_Computer_ID      = Column(String(255))
	mpa_DNSName             = Column(String(255))
	mpa_Bound_To_Domain     = Column(String(255))
	mpa_ADDomain            = Column(String(255))

# mpi_SPHardwareOverview
class MPISPHardwareOverview(CommonBase):
	__tablename__ = 'mpi_SPHardwareOverview'

	rid = Column(BigInteger, nullable=False, primary_key=True, autoincrement=True)
	cuuid = Column(String(50), ForeignKey('mp_clients.cuuid', ondelete='CASCADE', onupdate='NO ACTION'), nullable=False, index=True, unique=True)
	mdate = Column(DateTime, server_default='1970-01-01 00:00:00')
	mpa_Model_Name = Column(String(255))
	mpa_Model_Identifier = Column(String(255))
	mpa_Processor_Name = Column(String(255))
	mpa_Processor_Speed = Column(String(255))
	mpa_Number_of_Processors = Column(String(255))
	mpa_Total_Number_of_Cores = Column(String(255))
	mpa_L2_Cache = Column(String(255))
	mpa_Memory = Column(String(255))
	mpa_Bus_Speed = Column(String(255))
	mpa_Boot_ROM_Version = Column(String(255))
	mpa_SMC_Version = Column(String(255))
	mpa_Serial_Number = Column(String(255))
	mpa_Hardware_UUID = Column(String(255))
	mpa_Sudden_Motion_Sensor = Column(String(255))
	mpa_State = Column(String(255))
	mpa_L3_Cache = Column(String(255))
	mpa_Processor_Interconnect_Speed = Column(String(255))
	mpa_Sales_Order_Number = Column(String(255))
	mpa_Version = Column(String(255))
	mpa_LOM_Revision = Column(String(255))
	mpa_Machine_Name = Column(String(255))
	mpa_Machine_Model = Column(String(255))
	mpa_CPU_Type = Column(String(255))
	mpa_CPU_Speed = Column(String(255))
	mpa_L3_Cache_per_CPU = Column(String(255))
	mpa_serial_number_processor_tray = Column(String(255))
	mpa_l3_cache_per_processor = Column(String(255))
	mpa_smc_version_processor_tray = Column(String(255))
	mpa_illumination_version = Column(String(255))

# ------------------------------------------
## MDM

class MDMIntuneDevices():
	__tablename__ = 'mdm_intune_devices'

	rid = Column(BigInteger, nullable=False, primary_key=True, autoincrement=True)
	id = Column(String(255))
	userId = Column(String(255))
	deviceName = Column(String(255))
	managedDeviceOwnerType = Column(String(255))
	enrolledDateTime = Column(DateTime, server_default='1970-01-01 00:00:00')
	lastSyncDateTime = Column(DateTime, server_default='1970-01-01 00:00:00')
	operatingSystem = Column(String(255))
	complianceState = Column(String(255))
	jailBroken = Column(String(255))
	managementAgent = Column(String(255))
	osVersion = Column(String(255))
	easActivated = Column(Boolean(), server_default='0')
	easDeviceId = Column(String(255))
	easActivationDateTime = Column(DateTime, server_default='1970-01-01 00:00:00')
	azureADRegistered = Column(String(255))
	deviceEnrollmentType = Column(String(255))
	activationLockBypassCode = Column(String(255))
	emailAddress = Column(String(255))
	azureADDeviceId = Column(String(255))
	deviceRegistrationState = Column(String(255))
	deviceCategoryDisplayName = Column(String(255))
	isSupervised = Column(Boolean(), server_default='0')
	exchangeLastSuccessfulSyncDateTime = Column(DateTime, server_default='1970-01-01 00:00:00')
	exchangeAccessState = Column(String(255))
	exchangeAccessStateReason = Column(String(255))
	remoteAssistanceSessionUrl = Column(String(255))
	remoteAssistanceSessionErrorDetails = Column(String(255))
	isEncrypted = Column(Boolean(), server_default='0')
	userPrincipalName = Column(String(255))
	model = Column(String(255))
	manufacturer = Column(String(255))
	imei = Column(String(255))
	complianceGracePeriodExpirationDateTime = Column(DateTime, server_default='1970-01-01 00:00:00')
	serialNumber = Column(String(255))
	phoneNumber = Column(String(255))
	androidSecurityPatchLevel = Column(String(255))
	userDisplayName = Column(String(255))
	configurationManagerClientEnabledFeatures = Column(String(255))
	wiFiMacAddress = Column(String(255))
	deviceHealthAttestationState = Column(String(255))
	subscriberCarrier = Column(String(255))
	meid = Column(String(255))
	totalStorageSpaceInBytes = Column(BigInteger(), server_default='0')
	freeStorageSpaceInBytes = Column(BigInteger(), server_default='0')
	managedDeviceName = Column(String(255))
	partnerReportedThreatState = Column(String(255))


# ------------------------------------------
## Misc
class TestTable(CommonBase):
	__tablename__ = 'test_table'

	rid             = Column(BigInteger, primary_key=True)
	name            = Column(String(255), nullable=False)
