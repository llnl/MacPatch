#!/bin/bash

# -------------------------------------------------------------
#
# Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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
# mpapi Startup and shutdown script
#

RETVAL=$?
MP_HOME="/opt/MacPatch/Server"
ENV_HOME="${MP_HOME}/env/api"
PATH="${ENV_HOME}/bin",$PATH
PIDFile="/tmp/mpapi.pid"

case "$1" in
 start)
	echo $"Starting MacPatch API's"
	
    source "${ENV_HOME}/bin/activate"
	"${ENV_HOME}/bin/gunicorn" \
	--pythonpath "${ENV_HOME}/lib/python3.11/site-packages" \
	--config "${MP_HOME}/apps/gunicorn/gunicorn_api.py" \
	--chdir "${MP_HOME}/apps/mpapi" "app:create_app()" --pid $PIDFile &
	;;
 stop)
	echo $"Stopping MacPatch API's"
	CurPID=$(<"$PIDFile")
	kill -9 $CurPID
 	;;
 *)
 	echo $"Usage: $0 {start|stop}"
	exit 1
	;;
esac

exit $RETVAL
