#!/bin/bash
#
# -------------------------------------------------------------
#
# Copyright (c) 2013, Lawrence Livermore National Security, LLC.
# Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
# Written by Charles Heizer <heizer1 at llnl.gov>.
# LLNL-CODE-636469 All rights reserved.
# 
# This file is part of MacPatch, a program for installing and patching
# software.
# 
# MacPatch is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License (as published by the Free
# Software Foundation) version 2, dated June 1991.
# 
# MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
# License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with MacPatch; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
# -------------------------------------------------------------

# -------------------------------------------------------------
# Script: MPDBSetup.sh
# Version: 1.2.0
#
# Description:
# This script will setup and configure a MySQL server for
# MacPatch
#
# History:
# Added a continue on error, if the error is more of a warning
# then the user may continue and add the schema to the db.
# 
# 1.1.0 Altered script for new python based backend
# 1.2.0 Changed the code for adding password, now requires a verify
#
# -------------------------------------------------------------

if [ "`whoami`" != "root" ] ; then   # If not root user,
   # Run this script again as root
   echo
   echo "You must be an admin user to run this script."
   echo "Please re-run the script using sudo."
   echo
   exit 1;
fi

DBNAME="MacPatchDB3"
MPUSER="mpdbadm"
MPROUSR="mpdbro"
MPUSRPAS=""
MPUSRROPAS=""
HOST=`hostname`
RESSTR=""

readUsrPass () {
  _prompt="$1"
    _thePass=""
    while IFS= read -p "$_prompt" -r -s -n 1 char
    do
      if [[ $char == $'\0' ]]; then
          break
      fi
      _prompt='*'
      _thePass+="$char"
    done
    RESSTR="$_thePass"
}

BTICK='`'
export PATH=$PATH:/usr/local/mysql/bin
MYSQL=`which mysql`

if [ -z "$MYSQL" ] ; then
  clear
  echo
  echo "Could not find mysql. Please make sure that"
  echo "mysql is installed and in your path."
  exit 1;
fi

CHECKFORMY=`ps -aef | grep mysqld | grep -v grep | head -n1`
if [ -z "$CHECKFORMY" ] ; then
  clear
  echo
  echo "Could not find mysqld running. Please make sure that"
  echo "mysql is running before continuing."
  exit 1;
fi

clear
echo
echo "Notice:"
echo "Please remeber the following user names and passwords"
echo "They will be needed later."
echo
read -p "MacPatch User Account [mpdbadm]: " MPUSER
MPUSER=${MPUSER:-mpdbadm}

while true
do
    readUsrPass "Password: "
    MPUSRPAS="$RESSTR"
    echo
    readUsrPass "Password (verify): "
    MPUSRPASb="$RESSTR"
    echo
    [ "$MPUSRPAS" = "$MPUSRPASb" ] && break
    echo "Please try again"
done

echo
read -p "MacPatch Read Only User Account [mpdbro]: " MPROUSR
MPROUSR=${MPROUSR:-mpdbro}

while true
do
    readUsrPass "Password: "
    MPUSRROPAS="$RESSTR"
    echo
    readUsrPass "Password (verify): "
    MPUSRROPASb="$RESSTR"
    echo
    [ "$MPUSRROPAS" = "$MPUSRROPASb" ] && break
    echo "Please try again"
done

# For MySQL 5.7, not supported yet
QA="DROP USER IF EXISTS 'mpdbadm'@'localhost';"
QB="DROP USER IF EXISTS 'mpdbadm'@'%';"
QC="DROP USER IF EXISTS 'mpdbro'@'localhost';"
QD="DROP USER IF EXISTS 'mpdbro'@'%';"

Q1="CREATE DATABASE IF NOT EXISTS ${BTICK}$DBNAME${BTICK};"
Q2="CREATE USER '${MPUSER}'@'%' IDENTIFIED BY '${MPUSRPAS}';"
Q3="GRANT ALL ON $DBNAME.* TO '${MPUSER}'@'%' IDENTIFIED BY '${MPUSRPAS}';"
Q4="GRANT ALL PRIVILEGES ON $DBNAME.* TO '${MPUSER}'@'localhost' IDENTIFIED BY '${MPUSRPAS}';"
Q5="CREATE USER '${MPROUSR}'@'%' IDENTIFIED BY '${MPUSRROPAS}';"
Q6="GRANT SELECT ON $DBNAME.* TO '${MPROUSR}'@'%';"
Q7="SET GLOBAL log_bin_trust_function_creators = 1;"
Q8="DELETE FROM mysql.user WHERE User='';"
Q9="FLUSH PRIVILEGES;"

SQL="${Q1}${Q2}${Q3}${Q4}${Q5}${Q6}${Q7}${Q8}${Q9}"

clear
echo
echo "MySQL Database is about to be configured."
echo "You will be prompted for the MySQL root user password"
echo

$MYSQL -uroot -p -e "$SQL"
if [ $? -ne 0 ]; then
  echo
  read -p "An error was detected, would you like to continue (Y/N)? [N]: " CONTONERR
  CONTONERR=${CONTONERR:-N}
  if [ "$CONTONERR" == "N" ] || [ "$CONTONERR" == "N" ]; then
    exit 1;
  fi
fi