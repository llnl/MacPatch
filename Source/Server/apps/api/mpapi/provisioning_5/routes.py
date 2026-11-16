import base64
from datetime import datetime

from flask import request

from mpapi.app import db
from mpapi.mputil import MPResource
from mpapi.model import (MpProvisionTask, MpProvisionScript, MpProvisionConfig, MpProvisionCriteria,
						 OSMigrationStatus)
from mpapi.mplogger import log_Error
from mpapi.shared.rest import client_endpoint, ok, fail, signed
from mpapi.shared.client import AgentSettings

from . import provisioning_5_api

# Script type column of mp_provision_script
SCRIPT_TYPES = {'scriptsPre': 0, 'scriptsPost': 1, 'scriptsFinish': 2}


class ProvisionData(MPResource):
	"""Provisioning software tasks and pre/post/finish scripts for a client."""

	@client_endpoint(allow_iload=True)
	def get(self, client_id):
		settings = AgentSettings()
		settings.populateSettings(client_id)
		scope = 0 if settings.patch_state == 'QA' else 1  # QA or production

		tasks = (MpProvisionTask.query.filter(MpProvisionTask.active == 1, MpProvisionTask.scope == scope)
				 .order_by(MpProvisionTask.order.asc()).all())
		data = {'tasks': [t.asDict for t in tasks]}
		for key, script_type in SCRIPT_TYPES.items():
			scripts = (MpProvisionScript.query
					   .filter(MpProvisionScript.active == 1, MpProvisionScript.scope == scope,
							   MpProvisionScript.type == script_type)
					   .order_by(MpProvisionScript.order.asc()).all())
			data[key] = [s.asDict for s in scripts]

		return signed('MpProvisionTask', data)


class ProvisionConfig(MPResource):
	"""Active provisioning configuration."""

	# Unauthenticated, as in the older API versions. Drop both flags to require auth.
	@client_endpoint(verify_id=False, verify_signature=False)
	def get(self, client_id):
		config = MpProvisionConfig.query.filter(MpProvisionConfig.active == 1).first()
		return signed('MpProvisionConfig', config.config if config is not None else '')


class ProvisionCriteria(MPResource):
	"""Ordered provisioning criteria for a scope (default 'prod')."""

	# Unauthenticated, as in the older API versions. Drop both flags to require auth.
	@client_endpoint(verify_id=False, verify_signature=False)
	def get(self, client_id, scope='prod'):
		rows = (MpProvisionCriteria.query
				.filter(MpProvisionCriteria.active == 1, MpProvisionCriteria.scope == scope)
				.order_by(MpProvisionCriteria.order.asc()).all())

		query = []
		for c in rows:
			value = c.type_data
			if c.type.lower() == 'script':
				value = base64.b64encode(c.type_data.encode('utf-8')).decode('utf-8')
			query.append({'id': c.order, 'qstr': '%s@%s' % (c.type, value)})

		return signed('MpProvisionCriteria', {'query': query})


class OSMigration(MPResource):
	"""Record the start or stop of an OS migration (body action: start | stop)."""

	@client_endpoint()
	def post(self, client_id):
		body = request.get_json(silent=True) or {}
		action = body.get('action')

		if action == 'start':
			db.session.add(OSMigrationStatus(
				startDateTime=datetime.now(), cuuid=client_id, preOSVer=body['os'],
				label=body['label'], migrationID=body['migrationID']))

		elif action == 'stop':
			migration = OSMigrationStatus.query.filter_by(cuuid=client_id, migrationID=body['migrationID']).first()
			if migration is None:
				log_Error('[OSMigration][POST] Migration not found for client (%s)' % client_id)
				return fail(424, 'Migration not found.', errorno=2)
			migration.stopDateTime = datetime.now()
			migration.postOSVer = body['os']

		else:
			log_Error('[OSMigration][POST] Action (%s) is not valid. Client (%s)' % (action, client_id))
			return fail(424, 'Failed to run action type.')

		db.session.commit()
		return ok(code=201)


# Add Routes Resources
provisioning_5_api.add_resource(ProvisionData,     '/provisioning/data/<string:client_id>')
provisioning_5_api.add_resource(ProvisionConfig,   '/provisioning/config/<string:client_id>')
provisioning_5_api.add_resource(ProvisionCriteria, '/provisioning/criteria/<string:client_id>', endpoint='criteria')
provisioning_5_api.add_resource(ProvisionCriteria, '/provisioning/criteria/<string:client_id>/<string:scope>', endpoint='criteriaScope')
provisioning_5_api.add_resource(OSMigration,       '/provisioning/migration/<string:client_id>')
