from datetime import datetime
import syslog

from flask import request, current_app
from flask_restful import reqparse

from mpapi.app import db
from mpapi.mputil import MPResource
from mpapi.model import (MpClient, MpClientGroupSoftware, MPGroupConfig, MpServerList, MpAsusCatalogList)
from mpapi.mplogger import log_Info, log_Error, log_Debug
from mpapi.shared.rest import client_endpoint, ok, fail
from mpapi.shared.groups import groupIDForClient, addClientToDefaultGroup

from . import checkin_5_api

# One optional JSON string argument per mp_clients column
parser = reqparse.RequestParser()
for column in MpClient().columns:
	parser.add_argument(column, type=str, required=False, location='json')


def postClientDataToSysLog(client):
	"""Post client info to syslog, for Splunk."""
	data = "client_id: {}, hostname: {}, ip: {}, mac_address: {}, fileVault_status: {}, os_ver: {}, loggedin_user: {}".format(
		client.cuuid, client.hostname, client.ipaddr, client.macaddr, client.fileVaultStatus, client.osver, client.consoleuser)
	syslog.openlog(facility=syslog.LOG_DAEMON)
	syslog.syslog(data)
	syslog.closelog()
	log_Info("Wrote to syslog: " + data)


def clientRevisions(client_id):
	"""Config revisions and software task IDs for the client's group (the checkin response)."""
	group_id = groupIDForClient(client_id)
	if group_id == 0:
		log_Error('No group assignment for client (%s)' % client_id)
		group_id = addClientToDefaultGroup(client_id)

	revs = {'agent': 0, 'tasks': 0, 'servers': 0, 'suservers': 0, 'swrestrictions': 0}

	config = MPGroupConfig.query.filter(MPGroupConfig.group_id == group_id).first()
	if config is not None:
		revs['agent'] = config.rev_settings
		revs['tasks'] = config.rev_tasks
		revs['swrestrictions'] = config.restrictions_version

	servers = MpServerList.query.filter(MpServerList.listid == 1).first()
	if servers is not None:
		revs['servers'] = servers.version

	catalogs = MpAsusCatalogList.query.filter(MpAsusCatalogList.listid == 1).first()
	if catalogs is not None:
		revs['suservers'] = catalogs.version

	software = MpClientGroupSoftware.query.filter(MpClientGroupSoftware.group_id == group_id).all()
	return {'revs': revs, 'swTasks': [{'tuuid': s.tuuid} for s in software]}


class AgentBase(MPResource):
	"""Client checkin: add or update the client's record, return config revisions."""

	# The client ID isn't verified, a first checkin comes from a client with no record yet.
	@client_endpoint(verify_id=False)
	def post(self, client_id):
		args = parser.parse_args()
		body = request.get_json(silent=True) or {}
		log_Debug('[AgentBase][POST] Client (%s) Data %s' % (client_id, body))

		client = MpClient.query.filter_by(cuuid=client_id).first()
		if client is None:
			log_Info('[AgentBase][POST] Adding client (%s) record.' % client_id)
			client = MpClient(cuuid=client_id)
			db.session.add(client)
		else:
			log_Info('[AgentBase][POST] Updating client (%s) record.' % client_id)

		for col in client.columns:
			if col == 'mdate':
				continue

			if col == 'fileVaultStatus':
				client.fileVaultStatus = args['fileVaultStatus'] or body.get('fileVault') or 'NA'
			elif args[col] is not None:
				# Remove any new line chars before adding to DB
				setattr(client, col, args[col].replace('\n', ''))

		client.mdate = datetime.now()
		if current_app.config.get('POST_CHECKIN_TO_SYSLOG'):
			postClientDataToSysLog(client)
		db.session.commit()

		return ok(clientRevisions(client_id), code=201)


class AgentStatus(MPResource):
	"""When the client last checked in."""

	@client_endpoint()
	def get(self, client_id):
		client = MpClient.query.filter_by(cuuid=client_id).first()
		if client is None:
			log_Error('[AgentStatus][GET] Client (%s) not found' % client_id)
			return fail(404, 'Client not found.', result={'type': 'AgentStatus', 'data': {}})

		if current_app.config.get('POST_CHECKIN_TO_SYSLOG'):
			postClientDataToSysLog(client)

		data = {'mdate1': "{:%B %d, %Y %H:%M:%S}".format(client.mdate),
				'mdate2': "{:%m/%d/%Y %H:%M:%S}".format(client.mdate)}
		return ok({'type': 'AgentStatus', 'data': data})


# Add Routes Resources
checkin_5_api.add_resource(AgentBase,   '/client/checkin/<string:client_id>')
checkin_5_api.add_resource(AgentStatus, '/client/checkin/info/<string:client_id>')
