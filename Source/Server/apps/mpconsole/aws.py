from flask import session, current_app

import boto3
from boto3.session import Session
from botocore.errorfactory import ClientError


from . import db
from . model import *
from . modes import *
from . mplogger import *
from . mputil import *

# ------------------------------------------------------
# S3 Patch data
# ------------------------------------------------------

def getS3UrlForPatch(patch_id):
	result = "None"
	patch = MpPatch.query.filter(MpPatch.puuid == patch_id).first()
	if patch is not None:
		_s3 = getS3Client()
		_fP = patch.pkg_url[1:]
		if fileExistsInS3(_s3,_fP):
			result = urlForS3FilePath(_s3,_fP)

	return result

def deleteS3PatchFile(patch_id):
	try:
		#_s3 = getS3Client()
		#_fP = os.path.join('/patches', patch_id)[1:]
		_fP = patch_id[1:]
		session = Session(aws_access_key_id=current_app.config['AWS_S3_KEY'],
						  aws_secret_access_key=current_app.config['AWS_S3_SECRET'])

		# s3_client = session.client('s3')
		s3_resource = session.resource('s3')
		my_bucket = s3_resource.Bucket(current_app.config['AWS_S3_BUCKET'])

		response = my_bucket.delete_objects(
			Delete={
				'Objects': [
					{
						'Key': _fP  # the_name of_your_file
					}
				]
			}
		)

	except ClientError as e:
		print("Error: {}".format(e))
		return False

	return True

def uploadFileToS3(file,swFilePath):
	try:
		_s3 = getS3Client()
		_key = swFilePath[1:]
		response = _s3.upload_file(file, current_app.config['AWS_S3_BUCKET'], _key)
	except ClientError as e:
		print("Error: {}".format(e))
		return False

	return True

def uploadFileObjToS3(fileObj,swFilePath,contentType):
	try:
		_s3 = getS3Client()
		_key = swFilePath[1:]
		response = _s3.put_object(Body=fileObj, Bucket=current_app.config['AWS_S3_BUCKET'], Key=_key, ContentType=contentType)

	except ClientError as e:
		print("Error: {}".format(e))
		return False

	return True
# ------------------------------------------------------
# AWS S3 Helper Functions
# ------------------------------------------------------
def getS3Client():
	s3Client = None
	if current_app.config['USE_AWS_S3']:
		s3Client = boto3.client('s3',
							 aws_access_key_id=current_app.config['AWS_S3_KEY'],
							 aws_secret_access_key=current_app.config['AWS_S3_SECRET'],
							 region_name=current_app.config['AWS_S3_REGION'] )

	return s3Client

def fileExistsInS3(s3Client, filePath):
	try:
		s3Client.head_object(Bucket=current_app.config['AWS_S3_BUCKET'], Key=filePath)
		print("File Exists")
		return True
	except ClientError:
		# Not found
		print("File Not Exists {}".format(filePath))
		return False

def urlForS3FilePath(s3Client, filePath):
	params = {'Bucket': current_app.config['AWS_S3_BUCKET'], 'Key': filePath}
	sw_url = s3Client.generate_presigned_url('get_object', Params=params)
	#print("sw_url: {}".format(sw_url))
	return sw_url
