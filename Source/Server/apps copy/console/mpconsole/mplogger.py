from flask import current_app

def log(logString):
	if current_app.config['LOGGING_LEVEL'].lower() == 'info':
		current_app.logger.info(logString)
	elif current_app.config['LOGGING_LEVEL'].lower() == 'debug':
		current_app.logger.debug(logString)
	elif current_app.config['LOGGING_LEVEL'].lower() == 'warning':
		current_app.logger.warning(logString)
	elif current_app.config['LOGGING_LEVEL'].lower() == 'error':
		current_app.logger.error(logString)
	elif current_app.config['LOGGING_LEVEL'].lower() == 'critical':
		current_app.logger.critical(logString)
	else:
		current_app.logger.info(logString)

def log_Crit(logString):
	current_app.logger.critical(logString)
	sendMsgOnError(logString)

def log_Error(logString):
	current_app.logger.error(logString)
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
