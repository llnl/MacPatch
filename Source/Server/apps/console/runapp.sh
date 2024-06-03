#!/bin/bash

HOME="/opt/MacPatch/Server"
APP_HOME="${HOME}/apps/console"
ENV_HOME="${HOME}/env/console"

source ${ENV_HOME}/bin/activate

${ENV_HOME}/bin/gunicorn \
--pythonpath ${ENV_HOME}/lib/python3.12/site-packages \
--config ${APP_HOME}/gunicorn_console.py \
--chdir ${APP_HOME} "app:create_app()" \
--access-logfile ${HOME}/logs/g_console_access.log \
--error-logfile ${HOME}/logs/g_console_error.log
