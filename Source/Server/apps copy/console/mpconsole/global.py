from flask import session

def adminRole():
	_x = session['role']
	if _x[0] == 1:
		return True

	return False

def autopkgRole():
	_x = session['role']
	if _x[1] == 1:
		return True

	return False

def agentUploadRole():
	_x = session['role']
	if _x[2] == 1:
		return True

	return False

def apiRole():	
	_x = session['role']
	if _x[3] == 1:
		return True

	return False
