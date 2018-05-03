import pip
import os
import argparse
from sys import platform

_all_ = [
	"pycrypto>=2.6.1",
	"alembic>=0.8.7",
	"aniso8601>=1.1.0",
	"blinker>=1.4",
	"click>=6.6",
	"enum34>=1.1.6",
	"Flask>=0.11.1",
	"Flask-DebugToolbar==0.10.0",
	"Flask-Cache>=0.13.1",
	"flask-ldap3-login>=0.9.12",
	"Flask-Login>=0.3.2",
	"Flask-Migrate>=1.8.1",
	"Flask-RESTful>=0.3.5",
	"flask-restful-swagger==0.19",
	"Flask-Script>=2.0.5",
	"Flask-SQLAlchemy>=2.1",
	"Flask-WTF>=0.13.1",
	"gevent>=1.1.2",
	"greenlet>=0.4.10",
	"gunicorn>=19.6.0",
	"healthcheck>=1.3.1",
	"itsdangerous>=0.24",
	"Jinja2>=2.8",
	"ldap3>=2.1.0",
	"Mako>=1.0.4",
	"MarkupSafe>=0.23",
	"pyasn1>=0.1.9",
	"python-dateutil>=2.5.3",
	"python-editor>=1.0.1",
	"pytz>=2016.6.1",
	"six>=1.10.0",
	"Werkzeug>=0.11.11",
	"WTForms>=2.1",
	"Flask-APScheduler>=1.7.0",
	"flask-cors>=2.0.0",
	"flask-security>=1.7.0",
	"yattag>=1.8.0",
	"requests>=2.18.4",
	"mysql-connector-python",
	"uWSGI>=2.0.14"
]

_failed_ = []

MP_HOME     = "/opt/MacPatch"
MP_SRV_BASE = MP_HOME+"/Server"
CA_CERT     = None

# Platform Specific Packages
linux = ["M2Crypto==0.24.0"]
darwin = []

def easyInstall(package):
	print "Running Easy Install"
	print package
	if os.path.exists(package):
		print("Easy Install Python Module: " + package)
		os.system("easy_install --quiet " + package)

def upgrade(packages, platformStr="linux"):
	import pip

	for package in packages:
		if platformStr == 'linux':
			if CA_CERT is not None:
				res = pip.main(['install', "--quiet", "--egg", "--no-cache-dir", "--upgrade", "--cert", CA_CERT, package])
			else:
				res = pip.main(['install', "--quiet", "--egg", "--no-cache-dir", "--upgrade", package])
		else:
			res = pip.main(['install', "--quiet", "--egg", "--no-cache-dir", "--upgrade", package])

		if res != 0:
			_failed_.append(package)
			print("Error installing " + package + ". Please verify env.")

def install(packages, platformStr="linux"):
	for package in packages:
		import pip

		print("Installing Python Module: " + package)
		if platformStr == 'linux':
			if CA_CERT is not None:
				res = pip.main(['install', "--quiet", "--egg", "--no-cache-dir", "--cert", CA_CERT, package])
			else:
				res = pip.main(['install', "--quiet", "--egg", "--no-cache-dir", package])
		else:
			res = pip.main(['install', "--quiet", "--egg", "--no-cache-dir", package])

		if res != 0:
			_failed_.append(package)
			print("Error installing " + package + ". Please verify env.")

if __name__ == '__main__':

	'''Main command processing'''
	parser = argparse.ArgumentParser(description='Process some args.')
	parser.add_argument('--ca', help="SSL Inspection CA certificate file", required=False, default=None)
	args = parser.parse_args()

	if args.ca:
		CA_CERT = args.ca

	isMac = platform.startswith('darwin')
	isLinux = platform.startswith('linux')

	osType = 'NA'
	if isMac:
		osType = 'darwin'
	elif isLinux:
		osType = 'linux'

	print "Running python package installs for operating system type " + osType

	install(_all_, osType)

	if len(_failed_) > 0:
		print "Retrying failed packages"
		install(_failed_, osType)

	if platform.startswith('linux'):
		print "Install Linux Packages"
		install(linux, osType)

	if platform.startswith('darwin'):
		print "Install Darwin Packages"
		install(darwin, osType)
