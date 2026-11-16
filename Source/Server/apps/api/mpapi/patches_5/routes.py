from datetime import datetime

from flask import request
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from mpapi.app import db
from mpapi.extensions import cache
from mpapi.mputil import MPResource
from mpapi.model import (MpClientGroupMembers, MpClientSettings, MpClientPatches, MpClientPatchesApple,
						 MpClientPatchesThird, MpInstalledPatch, MpPatch, MpPatchGroupPatches)
from mpapi.mplogger import log_Info, log_Error, log_Debug
from mpapi.shared.rest import client_endpoint, ok, fail
from mpapi.shared.client import Client
from mpapi.shared.patches import PatchScanV3

from . import patches_5_api

# Patch types in the URL: 1 = Apple, 2 = Custom (third party). 'apple' / 'third' are also accepted for installs.
APPLE, CUSTOM = '1', '2'

# Custom patch fields the client doesn't need
CUSTOM_PATCH_HIDDEN_FIELDS = ('pkg_path', 'cve_id', 'patch_severity', 'cdate')


# Patch content changes rarely, so it is cached
@cache.cached(timeout=300, key_prefix='v5_AppleCachedList')
def appleContent():
	"""All Apple patches with MacPatch's additions (severity, state, weight, reboot override)."""
	sql = text("""select ap.akey, ap.title, ap.postdate, ap.restartaction, ap.supatchname, ap.version,
				  mpa.severity, mpa.severity_int, mpa.patch_state, mpa.patch_install_weight, mpa.patch_reboot
				  from apple_patches ap
				  LEFT JOIN apple_patches_mp_additions mpa ON ap.supatchname = mpa.supatchname""")
	with db.engine.connect() as con:
		rows = [dict(row) for row in con.execute(sql).mappings().all()]

	for row in rows:
		if row['restartaction'] == 'NoRestart' and row['patch_reboot'] == 1:
			row['restartaction'] = 'RequireRestart'
		elif row['restartaction'] == 'RequireRestart' and row['patch_reboot'] == 0:
			row['restartaction'] = 'NoRestart'
	return rows


@cache.cached(timeout=300, key_prefix='v5_CustomCachedList')
def customContent():
	"""All active custom patches, as dicts the client can use."""
	patches = []
	for patch in MpPatch.query.filter(MpPatch.active == 1).all():
		data = patch.asDict
		for field in CUSTOM_PATCH_HIDDEN_FIELDS:
			data.pop(field, None)
		patches.append(data)
	return patches


@cache.memoize(timeout=300)
def patchStateForClient(client_id):
	"""The patch_state setting of the client's group, 'All' if none is configured."""
	state = (db.session.query(MpClientSettings.value)
			 .join(MpClientGroupMembers, MpClientSettings.group_id == MpClientGroupMembers.group_id)
			 .filter(MpClientGroupMembers.cuuid == client_id, MpClientSettings.key == 'patch_state')
			 .first())
	return state[0] if state else 'All'


class PatchGroupPatches(MPResource):
	"""Patches for the client's patch group, or every active patch when all == 'all'."""

	@client_endpoint()
	def get(self, client_id, all=None):
		group_id = Client(client_id).getPatchGroupForClient(client_id)
		if group_id is None or group_id == 'NA':
			log_Error('[PatchGroupPatches][GET][%s] No patch group (%s) found.' % (client_id, group_id))
			return fail(404, 'Not Found', result={'type': 'PatchGroupPatches', 'data': {}})

		apple, custom = appleContent(), customContent()

		if all == 'all':
			apple_patches, custom_patches = list(apple), list(custom)
		else:
			apple_by_key = {p['akey']: p for p in apple}
			custom_by_id = {p['puuid']: p for p in custom}
			apple_patches, custom_patches = [], []
			for row in MpPatchGroupPatches.query.filter(MpPatchGroupPatches.patch_group_id == group_id).all():
				if row.patch_id in apple_by_key:
					apple_patches.append(apple_by_key[row.patch_id])
				elif row.patch_id in custom_by_id:
					custom_patches.append(custom_by_id[row.patch_id])

		return ok({'type': 'PatchGroupPatches', 'data': {'Apple': apple_patches, 'Custom': custom_patches}})


class PatchScanList(MPResource):
	"""The patches a client should scan for, optionally limited to a severity."""

	@client_endpoint()
	def get(self, client_id, severity='all'):
		scan_list = PatchScanV3(patchStateForClient(client_id)).getScanList('*', severity)
		if scan_list is None:
			log_Error('[PatchScanList][GET] Failed to get a scan list for client %s' % client_id)
			return fail(404, 'none', errorno=0)

		return ok({'data': scan_list})


class PatchScanData(MPResource):
	"""Replace the client's needed-patch records with the results of a scan."""

	@client_endpoint()
	def post(self, client_id, patch_type):
		if patch_type == APPLE:
			scanned, patch_type_name = MpClientPatchesApple, 'Apple'
		elif patch_type == CUSTOM:
			scanned, patch_type_name = MpClientPatchesThird, 'Third'
		else:
			log_Error('[PatchScanData][POST][%s] Type (%s) not accepted' % (client_id, patch_type))
			return fail(404, 'Type not accepted' if patch_type == '0' else 'Type not found')

		rows = (request.get_json(silent=True) or {}).get('rows')

		scanned.query.filter(scanned.cuuid == client_id).delete()
		db.session.commit()
		if rows is None:
			return ok(code=201)

		now = datetime.now()
		try:
			# Per type table, plus the combined needed-patches table
			MpClientPatches.query.filter(MpClientPatches.cuuid == client_id,
										 MpClientPatches.type_int == int(patch_type)).delete()
			for row in rows:
				for model in (scanned, MpClientPatches):
					record = model()
					for col in record.columns:
						if col in row:
							setattr(record, col, row[col])
					record.cuuid = client_id
					record.mdate = now
					if model is MpClientPatches:
						record.type, record.type_int = patch_type_name, int(patch_type)
					db.session.add(record)
			db.session.commit()
		except IntegrityError as e:
			db.session.rollback()
			log_Error('[PatchScanData][POST][%s] Error adding %s record. %s' % (client_id, patch_type_name, e))
			return fail(406, str(e))

		return ok(code=201)


class PatchInstallData(MPResource):
	"""Record an installed patch and remove it from the client's needed patches."""

	@client_endpoint()
	def post(self, client_id, patch_type, patch):
		kind = patch_type.lower()
		if kind in ('apple', APPLE):
			type_name, type_int, patch_name = 'apple', 0, patch
		elif kind in ('third', CUSTOM):
			type_name, type_int = 'third', 1
			custom = MpPatch.query.filter(MpPatch.puuid == patch).first()
			if custom is None:
				log_Error('[PatchInstallData][POST] Unable to get patch info for %s' % patch)
				return fail(404, 'Patch not found.')
			patch_name = '%s-%s' % (custom.patch_name, custom.patch_ver)
		else:
			log_Error('[PatchInstallData][POST][%s] Type (%s) not found' % (client_id, patch_type))
			return fail(404, 'Type not found')

		log_Debug('[PatchInstallData][POST][%s] Adding %s patch: %s' % (client_id, type_name, patch_name))
		db.session.add(MpInstalledPatch(cuuid=client_id, mdate=datetime.now(), patch=patch,
										patch_name=patch_name, type=type_name, type_int=type_int))

		# Not needed any more
		if type_int == 0:
			MpClientPatches.query.filter(MpClientPatches.patch == patch, MpClientPatches.type_int == 1,
										 MpClientPatches.cuuid == client_id).delete()
			MpClientPatchesApple.query.filter(MpClientPatchesApple.patch == patch,
											  MpClientPatchesApple.cuuid == client_id).delete()
		else:
			MpClientPatches.query.filter(MpClientPatches.patch_id == patch, MpClientPatches.type_int == 2,
										 MpClientPatches.cuuid == client_id).delete()
			MpClientPatchesThird.query.filter(MpClientPatchesThird.patch_id == patch,
											  MpClientPatchesThird.cuuid == client_id).delete()
		db.session.commit()

		return ok(code=202, errormsg='')


# Add Routes Resources
patches_5_api.add_resource(PatchGroupPatches, '/client/patch/group/<string:client_id>', endpoint='patchGroup')
patches_5_api.add_resource(PatchGroupPatches, '/client/patch/all/<string:client_id>', endpoint='patchAll', defaults={'all': 'all'})
patches_5_api.add_resource(PatchScanList,     '/client/patch/scan/list/all/<string:client_id>', endpoint='scanListAll')
patches_5_api.add_resource(PatchScanList,     '/client/patch/scan/list/<string:severity>/<string:client_id>', endpoint='scanListSeverity')
patches_5_api.add_resource(PatchScanData,     '/client/patch/scan/<string:patch_type>/<string:client_id>')
patches_5_api.add_resource(PatchInstallData,  '/client/patch/install/<string:patch>/<string:patch_type>/<string:client_id>')
