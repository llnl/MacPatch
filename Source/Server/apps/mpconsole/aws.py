from flask import session, current_app

import boto3
from boto3.session import Session
from botocore.errorfactory import ClientError


from . import db
from . model import *
from . modes import *
from . mplogger import *
from . mputil import *

class MPaws:

	def __init__(self):
		self.s3Client = self.getS3Client()

	# ------------------------------------------------------
	# S3 Patch data
	# ------------------------------------------------------

	def getS3UrlForPatch(self, patch_id):
		result = "None"
		patch = MpPatch.query.filter(MpPatch.puuid == patch_id).first()
		if patch is not None:
			_fP = patch.pkg_url[1:]
			if self.fileExistsInS3(_fP):
				result = self.urlForS3FilePath(_fP)

		return result

	def deleteS3PatchFile(self, patch_id):
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

	def uploadFileToS3(self, file, swFilePath):
		try:
			_key = swFilePath[1:]
			response = self.s3Client.upload_file(file, current_app.config['AWS_S3_BUCKET'], _key)
		except ClientError as e:
			print("Error: {}".format(e))
			return False

		return True

	def uploadFileObjToS3(self,fileObj,swFilePath,contentType):
		try:
			_key = swFilePath[1:]
			response = self.s3Client.put_object(Body=fileObj, Bucket=current_app.config['AWS_S3_BUCKET'], Key=_key, ContentType=contentType)

		except ClientError as e:
			print("Error: {}".format(e))
			return False

		return True
	# ------------------------------------------------------
	# AWS S3 Helper Functions
	# ------------------------------------------------------
	def getS3Client(self):
		s3Client = None
		if current_app.config['USE_AWS_S3']:
			log_Error('current_app.config[USE_AWS_S3]')
			log_Error('key: '+current_app.config['AWS_S3_KEY'])
			log_Error('secret: '+current_app.config['AWS_S3_SECRET'])
			log_Error('current_app.config[USE_AWS_S3]')

			config = Config(connect_timeout=5, retries={'max_attempts': 0})

			if current_app.config['AWS_S3_REGION'] is not None:
				s3Client = boto3.client('s3',
									 aws_access_key_id=current_app.config['AWS_S3_KEY'],
									 aws_secret_access_key=current_app.config['AWS_S3_SECRET'],
									 region_name=current_app.config['AWS_S3_REGION'],
									 config=config)
			else:
				s3Client = boto3.client('s3',
									 aws_access_key_id=current_app.config['AWS_S3_KEY'],
									 aws_secret_access_key=current_app.config['AWS_S3_SECRET'],
									 config=config)

		return s3Client

	def fileExistsInS3(self, filePath):
		try:
			self.s3Client.head_object(Bucket=current_app.config['AWS_S3_BUCKET'], Key=filePath)
			log_Error("File Exists")
			return True
		except ClientError:
			# Not found
			log_Error("File Not Exists {}".format(filePath))
			return False

	def urlForS3FilePath(self, filePath):
		params = {'Bucket': current_app.config['AWS_S3_BUCKET'], 'Key': filePath}
		sw_url = self.s3Client.generate_presigned_url('get_object', Params=params)
		log_Error(sw_url)
		return sw_url

