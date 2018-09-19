#!/opt/MacPatch/Server/venv/bin/python

'''
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.

 This file is part of MacPatch, a program for installing and patching
 software.

 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.

 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.

 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
'''

import sys, getopt
import os
import commands
import platform

Version="2.0.2"
MP_SRV_BASE="/opt/MacPatch/Server"
MP_SRV_ETC=MP_SRV_BASE+"/etc"

if sys.platform.startswith('linux'):
	dist_type 	 = platform.dist()[0]
else:
	dist_type 	 = "Mac"


def main(argv):

	try:
		opts, args = getopt.getopt(argv,"hc:b:v")
	except getopt.GetoptError:
		usage()
		sys.exit(2)
	for opt, arg in opts:
		if opt == '-h':
			usage()
			sys.exit()
		elif opt == '-v':
			print 'getOpt.py version ' + Version
			sys.exit()
		elif opt in ("-c"):
			getCerts(arg)
		elif opt in ("-b"):
			global MP_SRV_BASE
			global MP_SRV_ETC
			MP_SRV_BASE = arg
			if sys.platform.startswith('linux'):
				MP_SRV_ETC = MP_SRV_BASE+"/etc"
			else:
				MP_SRV_ETC = MP_SRV_BASE+"/conf"

	sys.exit()

def getCerts (servers):

	if not os.path.exists(MP_SRV_ETC+"/jsseCerts"):
		os.makedirs(MP_SRV_ETC+"/jsseCerts")

	# Make a list of the server input arg
	_servers = []
	_servers = servers.split(' ')

	# Download and add the cert for each server
	for server in _servers:
		addCert(server)

	print
	print "Certificates have been download, and a jssecacerts file has been created."
	print
	print "****************** NOTE ******************"
	print "A reboot of the J2EE services will be requirerd for the application server to recognize the new cert(s)."
	print

def addCert(host):

	fileName = host.replace(':','_')
	hostNameShort = fileName.split('.')[0]

	if os.path.exists(MP_SRV_ETC+"/jsseCerts/"+host+".cer"):
		os.remove(MP_SRV_ETC+"/jsseCerts/"+host+".cer")

	# Download the new cert
	(ret, out) = commands.getstatusoutput('echo | openssl s_client -connect '+host+' 2>/dev/null | sed -ne \'/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p\' > "'+MP_SRV_ETC+'/jsseCerts/'+fileName+'.cer"')
	if ret == 0:
		print "Import "+host+" to jssecacerts"
		# if the jssecacerts file does not exist dont delete anything
		if os.path.exists(MP_SRV_ETC+'/jsseCerts/jssecacerts'):
			# Delete the alias if it exists, it's easier to just delete and re-add it
			(delRet, delOut) = commands.getstatusoutput('keytool -delete -alias "'+hostNameShort+'" -keystore "'+MP_SRV_ETC+'/jsseCerts/jssecacerts" -storepass changeit -trustcacerts -noprompt')
			if (delRet != 0):
				print "Error deleting alias for "+hostNameShort+ " " +delOut

		# Add the downloaded cert
		(addRet, addOut) = commands.getstatusoutput('keytool -import -file "'+MP_SRV_ETC+'/jsseCerts/'+fileName+'.cer" -alias "'+hostNameShort+'" -keystore "'+MP_SRV_ETC+'/jsseCerts/jssecacerts" -storepass changeit -trustcacerts -noprompt')
		if (addRet != 0):
			print "Error adding cert for "+hostNameShort+ " " +addOut
	else:
		print "Error getting cert for "+host+". "+out

def usage ():
	print ""
	print "USAGE: "
	print "    getRemoteCerts.py [-?] [-c]"
	print ""
	print "OPTIONS:"
	print "    -c  List Of Domain Controller(s) to get the cert from."
	print "    -b  Specify a base path to download the certs and create the jssecacerts file."
	print "    -?  this usage information"
	print ""
	print "EXAMPLE:"
	print "    getRemoteCerts.sh -c \"dc1.example.com:3269 dc2.example.com:3269\""
	print ""


if __name__ == "__main__":
	main(sys.argv[1:])
