from mpapi.extensions import aws
from mpapi.mputil import MPResource
from mpapi.shared.rest import client_endpoint, ok, fail

from . import aws_5_api


class GetAWSUrl(MPResource):
	"""Pre-signed S3 URL for a software ('sw') or patch ('patch') package."""

	@client_endpoint()
	def get(self, type, id, client_id):
		if type == 'patch':
			url, what = aws.getS3UrlForPatch(id), 'Patch'
		elif type == 'sw':
			url, what = aws.getS3UrlForSoftware(id), 'Software'
		else:
			return fail(404, 'Unknown type (%s).' % type, errorno=1, result={'url': 'none', 'type': type})

		if url is None:
			return fail(404, '%s data for %s not found.' % (what, id), errorno=1,
						result={'url': 'none', 'type': type})
		return ok({'url': url, 'type': type})


# Add Routes Resources
aws_5_api.add_resource(GetAWSUrl, '/aws/url/<string:type>/<string:id>/<string:client_id>')
