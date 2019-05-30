from flask import render_template, jsonify, request, session
from flask_security import login_required
import json

from .  import test
from .. import db
from .. import login_manager
from .. model import *
from .. mplogger import *

# This is a UI Request
@test.route('/')
@login_required
def new():

	return render_template('base_new.html')