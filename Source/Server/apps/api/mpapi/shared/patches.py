from mpapi.model import *
from mpapi.mplogger import *
from .. extensions import cache
from . client import *

# Old Class, with 3.1 agent and higher start using the V2 class
class PatchScan():

	def __init__(self, patch_state='All'):
		self.patch_state = patch_state

	def bundleIDList(self, severity=None):
		'''
			Return a tuple of bundle_id set and ordered list based on version number
			descending.
		'''

		patch_state = self.patch_state

		if patch_state.lower() == "all":
			_state = ["Production","QA"]
		elif patch_state.lower() == "create":
			_state = ["Create"]
		elif patch_state.lower() == "qa":
			_state = ["QA"]
		else:
			_state = ["Production"]

		# Query DataBase get all Custom Patches based on bundle and version
		if severity is None or severity.lower() == 'all':
			q = MpPatch.query.with_entities(MpPatch.puuid, MpPatch.patch_name, MpPatch.patch_ver, MpPatch.bundle_id,
									MpPatch.patch_reboot, MpPatch.patch_state, MpPatch.active, MpPatch.rid, MpPatch.patch_severity
									).filter(MpPatch.active == 1, MpPatch.patch_state.in_(_state)).order_by(MpPatch.bundle_id.desc()).all()

		else:
			q = MpPatch.query.with_entities(MpPatch.puuid, MpPatch.patch_name, MpPatch.patch_ver, MpPatch.bundle_id,
										MpPatch.patch_reboot, MpPatch.patch_state, MpPatch.active, MpPatch.rid, MpPatch.patch_severity
										).filter(MpPatch.active == 1, MpPatch.patch_state.in_(["Production","QA"]), MpPatch.patch_severity == severity).order_by(
			MpPatch.bundle_id.desc()).all()

		bundleList = []
		results = []
		if q is not None:
			for row in q:
				bundleList.append(row[3])
				results.append({"puuid": row[0], "patch_name": row[1], "patch_ver": row[2], "bundle_id": row[3],
								"patch_reboot": row[4], "patch_state": row[5], "active": row[6], "rid": row[7],
								"severity": row[8]})

			# Create Unique List of Bundle ID's
			bundleList = set(bundleList)
			# Sort the list of patches by bundle_id and then by version number
			sortedlist = sorted(results, key=lambda elem: "%s %s" % (elem['bundle_id'], (".".join([i.zfill(5) for i in elem['patch_ver'].split(".")]))), reverse=True)
			# Return the result as a tuple
			return bundleList, sortedlist
		else:
			return None, None

	def scanCriteriaForPatch(self, puuid):
		'''
			Get Patch Scab Query Data for patch id (puuid)
			returns a list of dictionaries
		'''

		results = []
		q = MpPatchesCriteria.query.with_entities(MpPatchesCriteria.type, MpPatchesCriteria.type_order, MpPatchesCriteria.type_data).filter(MpPatchesCriteria.puuid == puuid).order_by(MpPatchesCriteria.type_order).all()
		if q is not None:
			for row in q:
				query_ = row.type.strip() + "@" + row.type_data.strip()
				results.append({'id': str(row.type_order), 'qStr': query_})

		return results

	def osCheckForPatch(self, puuid, os='*'):
		'''
			Get Patch Scab Query Data for patch id (puuid)
			returns a list of dictionaries
		'''

		result = False
		q = MpPatchesCriteria.query.with_entities(MpPatchesCriteria.type_data).filter(MpPatchesCriteria.puuid == puuid, MpPatchesCriteria.type == "OSVersion").first()
		if q is not None:
			if q[0] == "*":
				return True
			if os in q[0]:
				return True
			if "*" in q[0]:
				for i in q[0].split(','):
					_i = i.split('.')
					qOS = _i[0]+"."+_i[1]

					cOS = '0.0'
					_o = os.split('.')
					if len(_o) >= 2:
						cOS = _o[0]+"."+_o[1]

					if qOS.strip() == cOS.strip():
						return True

		return result

	# Really the only public method to be used
	def getScanList(self, os=None, severity=None):
		results = []
		b = self.bundleIDList(severity)
		for name in b[0]:
			for x in b[1]:
				if name == x["bundle_id"]:
					if os:
						if self.osCheckForPatch(x["puuid"], os):
							x['query'] = self.scanCriteriaForPatch(x["puuid"])
							x.pop("rid", None)
							results.append(x)
							break
					else:
						x['query'] = self.scanCriteriaForPatch(x["puuid"])
						x.pop("rid", None)
						results.append(x)
						break

		return results

# New Class, The new class is much faster and fully dynamic
class PatchScanV2():

	def __init__(self, patch_state='All'):
		self.patch_state = patch_state

	def custPatchList(self, severity=None):
		patch_state = self.patch_state

		if patch_state.lower() == "all":
			_state = ["production", "qa"]
		elif patch_state.lower() == "create":
			_state = ["create"]
		elif patch_state.lower() == "qa":
			_state = ["qa"]
		else:
			_state = ["production"]

		_bundleid = []
		_filtered = []
		_sorted = []
		_all = MpPatch.query.filter(MpPatch.active == 1).all()

		if _all is not None:
			if len(_all) >= 1:
				for row in _all:
					if row.patch_state.lower() in _state:
						_bundleid.append(row.bundle_id)  # Add All BundleID's to list, then make a unique set
						patch = {}
						patch['bundle_id'] = row.bundle_id
						patch['patch_id'] = row.puuid
						patch['patch_reboot'] = row.patch_reboot
						patch['patch_version'] = row.patch_ver
						patch['query'] = []
						_filtered.append(patch)

				_bundleid = set(_bundleid)  # unique set
				_sorted = sorted(_filtered, key=lambda elem: "%s %s" % (
				elem['bundle_id'], (".".join([i.zfill(5) for i in elem['patch_version'].split(".")]))),
								 reverse=True)

				return _bundleid, _sorted

		return None, None

	def criteriaForPatch(self, criteria_list, patch_id):
		results = []
		criteria_list_new = []
		for row in criteria_list:
			if row['puuid'] == patch_id:
				query_ = row['type'].strip() + "@" + row['type_data'].strip()
				results.append({'id': str(row['type_order']), 'qStr': query_})
			else:
				criteria_list_new.append(row)

		results = sorted(results, key=lambda k: k['id'])
		return results, criteria_list_new

	def osCheckForPatch(self, puuid, os='*'):
		'''
			Get Patch Scab Query Data for patch id (puuid)
			returns a list of dictionaries
		'''

		result = False
		q = MpPatchesCriteria.query.with_entities(MpPatchesCriteria.type_data).filter(MpPatchesCriteria.puuid == puuid, MpPatchesCriteria.type == "OSVersion").first()
		if q is not None:
			if q[0] == "*":
				return True
			if os in q[0]:
				return True
			if "*" in q[0]:
				for i in q[0].split(','):
					_i = i.split('.')
					qOS = _i[0]+"."+_i[1]

					cOS = '0.0'
					_o = os.split('.')
					if len(_o) >= 2:
						cOS = _o[0]+"."+_o[1]

					if qOS.strip() == cOS.strip():
						return True

		return result

	# Really the only public method to be used
	@cache.cached(timeout=300)
	def getScanList(self, os=None, severity=None):

		_patch_criteria = [u.__dict__ for u in MpPatchesCriteria.query.all()]
		_patch_criteria_o =  _patch_criteria
		_patch_criteria_n = []
		results = []
		res = self.custPatchList(severity)
		for bundle in res[0]:
			for patch in res[1]:
				if bundle == patch["bundle_id"]:
					if os and os != "*":
						if self.osCheckForPatch(patch["patch_id"], os):
							patch['query'], _patch_criteria_n = self.criteriaForPatch(_patch_criteria_o, patch["patch_id"])
							_patch_criteria_o = _patch_criteria_n
							results.append(patch)
							break
					else:
						patch['query'], _patch_criteria_n = self.criteriaForPatch(_patch_criteria_o, patch["patch_id"])
						_patch_criteria_o = _patch_criteria_n
						results.append(patch)
						break

		return results
