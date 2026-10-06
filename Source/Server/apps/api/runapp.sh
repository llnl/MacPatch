#!/bin/bash

HOME="/opt/MacPatch/Server"
APP_HOME="${HOME}/apps/api"
ENV_HOME="${HOME}/env/api"

source ${ENV_HOME}/bin/activate

${ENV_HOME}/bin/gunicorn \
--pythonpath "$(${ENV_HOME}/bin/python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')" \
--config ${APP_HOME}/gunicorn_config.py \
--chdir ${APP_HOME} "app:create_app()" \
--access-logfile ${HOME}/logs/g_api_access.log \
--error-logfile ${HOME}/logs/g_api_error.log
