from flask import current_app

def log_Crit(logString):
	current_app.logger.critical(logString)
	#sendMsgOnError(logString)

def log_Error(logString):
	current_app.logger.error(logString)

def log_Warn(logString):
	current_app.logger.warning(logString)

def log_Info(logString):
	current_app.logger.info(logString)

def log_Debug(logString):
	current_app.logger.debug(logString)

def sendMsgOnError(logString):
	from .mputil import sendEmailMessage
	subject = "[Critical Error] MacPatch Server"
	sendEmailMessage(subject, logString)
