#!/bin/bash

HOME="/opt/MacPatch/Server"
APP_HOME="${HOME}/apps/api"
ENV_HOME="${HOME}/env/api"

source ${ENV_HOME}/bin/activate

${ENV_HOME}/bin/gunicorn \
--pythonpath ${ENV_HOME}/lib/python3.12/site-packages \
--config ${APP_HOME}/gunicorn_config.py \
--chdir ${APP_HOME} "app:create_app()" \
--access-logfile ${HOME}/logs/g_api_access.log \
--error-logfile ${HOME}/logs/g_api_error.log
