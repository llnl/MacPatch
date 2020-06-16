#!/opt/MacPatch/Server/env/server/bin/python3

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

'''
  MacPatch Patch Database Setup Script
  MacPatch Version 3.5.x

  Script Version 1.0.0
'''

import getpass
import os
import psutil
import socket
import subprocess
import mysql.connector
from mysql.connector import errorcode

def passwordEntry():
	passwrd = ""
	passwrdVfy = ""

	while True:
		passwrd = getpass.getpass("Password:")
		passwrdVfy = getpass.getpass("Password (verify):")
		if passwrd == passwrdVfy:
			break
		else:
			print("Passwords did not match, please try again.")

	return passwrd

def isProcessRunning(processName):
	#Iterate over the all the running process
	for proc in psutil.process_iter():
		try:
			# Check if process name contains the given name string.
			if processName.lower() in proc.name().lower():
				return True
		except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
			pass
	
	return False

def which(program):
	def is_bin(fpath):
		return os.path.isfile(fpath) and os.access(fpath, os.X_OK)

	fpath, fname = os.path.split(program)
	if fpath:
		if is_bin(program):
			return program
	else:
		for path in os.environ["PATH"].split(os.pathsep):
			bin_file = os.path.join(path, program)
			if is_bin(bin_file):
				return bin_file
	return None

def mpSqlModes(modes):
	res = modes.replace("ONLY_FULL_GROUP_BY,", "")
	res = res.replace(",ONLY_FULL_GROUP_BY,", ",")
	res = res.replace(",ONLY_FULL_GROUP_BY", "")
	return res

def main():
	
	MPUSRPAS=""
	HOST=socket.gethostname()
	RESSTR=""
	MYSQLVER="0"
 
	mysqld=which('mysqld')
	if mysqld is None:
		print("Could not find mysqld. Please make sure that")
		print("mysqld is installed.")
		exit(1)
	else:
		result = subprocess.run(['mysqld', '-V'], stdout=subprocess.PIPE)
		resLst = result.stdout.decode('utf-8').split(" ")
		for i, v in enumerate(resLst):
			if v == 'Ver':
				i += 1
				MYSQLVER=resLst[i]
				break
 
	if not isProcessRunning('mysqld'):
		print("Could not find mysqld running. Please make sure that")
		print("mysql is running before continuing.")
		exit(1)
 
	print("")
	print("*************** MacPatch Database Setup ***************")
	print("Notice:")
	print("Please remeber the following user name and password")
	print("They will be needed later.")
	print("")
	print("")
	mp_db_name = input("MacPatch Database Name [MacPatchDB3]: ") or "MacPatchDB3"
	mp_db_usr = input("MacPatch Database User Account [mpdbadm]: ") or "mpdbadm"
	print("MacPatch Database User Password... ")
	mp_db_usr_pass = passwordEntry()
 
	SQL=[]
	Q1=f"CREATE DATABASE IF NOT EXISTS `{mp_db_name}`;"
	Q2=f"CREATE USER '{mp_db_usr}'@'%' IDENTIFIED BY '{mp_db_usr_pass}';"

	if MYSQLVER.startswith('8'):
		QA="DROP USER IF EXISTS 'mpdbadm'@'localhost';"
		QB="DROP USER IF EXISTS 'mpdbadm'@'%';"
		Q3=f"GRANT ALL PRIVILEGES ON {mp_db_name}.* TO '{mp_db_usr}'@'%' WITH GRANT OPTION;"
		Q4A=f"CREATE USER '{mp_db_usr}'@'localhost' IDENTIFIED BY '{mp_db_usr_pass}';"
		Q4=f"GRANT ALL PRIVILEGES ON {mp_db_name}.* TO '{mp_db_usr}'@'localhost' WITH GRANT OPTION;"
		SQL=[QA, QB, Q1, Q2, Q3, Q4A, Q4]
	else:
		# Older Version of MySQL 5.x
		Q3=f"GRANT ALL ON {mp_db_name}.* TO '{mp_db_usr}'@'%' IDENTIFIED BY '{mp_db_usr_pass}';"	
		Q4=f"GRANT ALL PRIVILEGES ON {mp_db_name}.* TO '{mp_db_usr}'@'localhost' IDENTIFIED BY '{mp_db_usr_pass}';"
		SQL=[Q1, Q2, Q3, Q4]		
	
	SQL.append("SET GLOBAL log_bin_trust_function_creators = 1;")
	SQL.append("DELETE FROM mysql.user WHERE User='';")
	SQL.append("FLUSH PRIVILEGES;")
 
	print("")
	print("Please enter the MySQL root password to apply the configuration")
	db_root_pass = getpass.getpass("Password: ")
	cnx = mysql.connector.connect(user='root', password=db_root_pass)
	cursor = cnx.cursor()
 
	hadErr = False
	for qry in SQL: 
		try:
			cursor.execute(qry)
		except mysql.connector.Error as err:
			print(f"Error: {err.msg}")
			print("Err Run: " + qry)
			hadErr = True

	cursor.close()
	if hadErr:
		print("There was an error, please review the error and make corrections")
		print("and re-run this script.")
		cnx.close()
		exit(1)

	# Check SQL Modes, need to remove ONLY_FULL_GROUP_BY
	cursor = cnx.cursor()
	modes = ""
	modeLst = []
	mqry="SELECT @@GLOBAL.sql_mode;"
	cursor.execute(mqry)

	for row in cursor:
		modeLst.append(row[0])

	# Remove conflicting mode
	modes = mpSqlModes(modeLst[0])
	newModesQry=(f"SET GLOBAL sql_mode = '{modes}';")
	cursor.execute(newModesQry)
 
	cursor.close()	
	cnx.close()
 
	# Done
	print("")
	print("*************** MacPatch Database Setup Complete ***************")
	print(f"MacPatch database ({mp_db_name}) has been configured.")
	print("")
if __name__ == "__main__":
	main()