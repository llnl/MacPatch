from flask import current_app

import logging

def log(logString):
	# Logs at the configured LOGGING_LEVEL, so the message is always written (used for audit messages)
	_level = getattr(logging, current_app.config['LOGGING_LEVEL'].upper(), logging.INFO)
	current_app.logger.log(_level if isinstance(_level, int) else logging.INFO, logString)

def log_Crit(logString):
	current_app.logger.critical(logString)
	sendMsgOnError(logString)

def log_Error(logString):
	current_app.logger.error(logString)
	sendMsgOnError(logString)

def log_Exception(logString):
	# Use inside an except block, logs the message at error level with the traceback
	current_app.logger.exception(logString)
	sendMsgOnError(logString)

def log_Warn(logString):
	current_app.logger.warning(logString)

def log_Info(logString):
	current_app.logger.info(logString)

def log_Debug(logString):
	current_app.logger.debug(logString)

def sendMsgOnError(logString):
	#from mputil import sendEmailMessage
	#subject = "[Critical Error] MacPatch Server"
	#sendEmailMessage(subject, logString)
	# TODO
	pass
