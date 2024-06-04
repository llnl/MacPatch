from flask import render_template, jsonify, request, session
from flask_security import login_required
import json

from . import test
from mpconsole.app import db, login_manager
from mpconsole.model import *
from mpconsole.mplogger import *

# This is a UI Request
@test.route('/')
@login_required
def new():

	return render_template('base_new.html')