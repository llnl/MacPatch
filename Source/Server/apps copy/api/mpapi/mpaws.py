import boto3
from botocore.config import Config
from botocore.errorfactory import ClientError

class MPaws:

	def __init__(self, app):
		self.config = app['config']
		self.client = None
		self.resource = None

	def __init__(self):
		self.config = None
		self.client = None
		self.resource = None

	def init_app(self, app):
		self.app = app
		self.config = self.app.config
		self.client = self.getS3Client()
		self.resource = self.getS3Resource()

	# ------------------------------------------------------
	# S3 Patch data
	# ------------------------------------------------------

	def getS3UrlForPatch(self, pkg_url):
		result = "None"
		_fP = pkg_url[1:]
		if self.fileExistsInS3(_fP):
			result = self.urlForS3FilePath(_fP)

		return result

	def deleteS3PatchFile(self, patch_id):
		return self.deleteS3File(filePath=patch_id)

	# ------------------------------------------------------
	# S3 Software data
	# ------------------------------------------------------

	def getS3UrlForSoftware(self, sw_url):
		result = "None"
		_fP = sw_url[1:]
		if self.fileExistsInS3(_fP):
			result = self.urlForS3FilePath(_fP)

		return result

	# ------------------------------------------------------
	# AWS S3 Universal Functions
	# ------------------------------------------------------

	def uploadFileToS3(self, file, filePath):
		try:
			_key = filePath[1:]
			if self.client is None:
				self.client = self.getS3Client()
			response = self.client.upload_file(file, self.config['AWS_S3_BUCKET'], _key)
		except ClientError as e:
			self.app.logger.error("Error: {}".format(e))
			return False

		return True

	def uploadFileObjToS3(self,fileObj,filePath,contentType):
		try:
			_key = filePath[1:]
			if self.client is None:
				self.client = self.getS3Client()
			response = self.client.put_object(Body=fileObj, Bucket=self.config['AWS_S3_BUCKET'], Key=_key, ContentType=contentType)

		except ClientError as e:
			self.app.logger.error("Error: {}".format(e))
			return False

		return True

	def downloadFileFromS3(self, patch):
		"""
			Need to get a boto3 resource, then download the file locally.
			Return the locally downloaded file path
		"""
		_fileName = patch.pkg_url.split("/")[-1]
		_download_file = f"/tmp/{_fileName}"
		_pkg_url = patch.pkg_url[1:]
		if self.resource is None:
				self.resource = self.getS3Resource()
		self.resource.Bucket(self.config['AWS_S3_BUCKET']).download_file(_pkg_url, _download_file)
		return _download_file

	def deleteS3File(self, filePath):
		try:
			_fP = filePath[1:] # removes first char which is a / in the MP path
			if self.resource is None:
				self.resource = self.getS3Resource()
			self.resource.Object(self.config['AWS_S3_BUCKET'], _fP).delete()

		except ClientError as e:
			self.app.logger.error("Error: {}".format(e))
			return False

		return True
	# ------------------------------------------------------
	# AWS S3 Helper Functions
	# ------------------------------------------------------
	def getS3Client(self):
		s3Client = None
		self.app.logger.info(f"[MPaws][getS3Client]: USE_AWS_S3 = {self.config['USE_AWS_S3']}")
		if self.config['USE_AWS_S3']:
			self.app.logger.info('Initializing S3 Client Object')
			self.app.logger.debug('key: ....' + self.config['AWS_S3_KEY'][-4:])
			self.app.logger.debug('secret: ....' + self.app.config['AWS_S3_SECRET'][-4:])

			config = Config(connect_timeout=5, retries={'max_attempts': 0})

			if self.config['AWS_S3_REGION'] is not None:
				s3Client = boto3.client('s3',
									 aws_access_key_id=self.config['AWS_S3_KEY'],
									 aws_secret_access_key=self.config['AWS_S3_SECRET'],
									 region_name=self.config['AWS_S3_REGION'],
									 config=config)
			else:
				s3Client = boto3.client('s3',
									 aws_access_key_id=self.config['AWS_S3_KEY'],
									 aws_secret_access_key=self.config['AWS_S3_SECRET'],
									 config=config)

		return s3Client
	
	def getS3Resource(self):
		s3Client = None
		self.app.logger.info(f"[MPaws][getS3Resource]: USE_AWS_S3 = {self.config['USE_AWS_S3']}")
		if self.config['USE_AWS_S3']:
			self.app.logger.info('Initializing S3 Resource Object')
			self.app.logger.info('key: ....'+self.config['AWS_S3_KEY'][-4:])
			self.app.logger.info('secret: ....'+self.config['AWS_S3_SECRET'][-4:])

			config = Config(connect_timeout=5, retries={'max_attempts': 0})

			if self.config['AWS_S3_REGION'] is not None:
				s3Client = boto3.resource('s3',
									 aws_access_key_id=self.config['AWS_S3_KEY'],
									 aws_secret_access_key=self.config['AWS_S3_SECRET'],
									 region_name=self.config['AWS_S3_REGION'],
									 config=config)
			else:
				s3Client = boto3.resource('s3',
									 aws_access_key_id=self.config['AWS_S3_KEY'],
									 aws_secret_access_key=self.config['AWS_S3_SECRET'],
									 config=config)

		return s3Client

	def fileExistsInS3(self, filePath):
		try:
			if self.client is None:
				self.client = self.getS3Client()
			self.client.head_object(Bucket=self.config['AWS_S3_BUCKET'], Key=filePath)
			return True
		except ClientError:
			# Not found
			self.app.logger.error("File Not Exists {}".format(filePath))
			return False

	def urlForS3FilePath(self, filePath):
		if self.client is None:
			self.client = self.getS3Client()
		params = {'Bucket': self.config['AWS_S3_BUCKET'], 'Key': filePath}
		sw_url = self.client.generate_presigned_url('get_object', Params=params)
		self.app.logger.info(sw_url)
		return sw_url

