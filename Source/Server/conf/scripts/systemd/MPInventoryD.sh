#!/bin/bash

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
#
# MPInventoryD Startup and shutdown script
#

RETVAL=$?
MP_HOME="/opt/MacPatch/Server"
MP_SCRIPT="${MP_HOME}/conf/scripts"
MP_INVDIR="${MP_HOME}/InvData/files"

case "$1" in
 start)
	if [ -f $MP_SCRIPT/MPInventoryD.py ]; then
	    echo $"Starting MacPatch Inventory"
		$MP_SCRIPT/MPInventoryD.py --config $MP_HOME/etc/siteconfig.json --files $MP_INVDIR &
    fi
	;;
 stop)
	if [ -f $MP_SCRIPT/MPInventoryD.py ]; then
		echo $"Stopping MacPatch Inventory"
		mpPID=`ps -ef | grep MPInventoryD.py | grep -v grep | awk '{ print $2 }'`
		kill -9 $mpPID
    fi
 	;;
 *)
 	echo $"Usage: $0 {start|stop}"
	exit 1
	;;
esac

exit $RETVAL
