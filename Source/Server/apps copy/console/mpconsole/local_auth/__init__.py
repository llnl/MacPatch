from flask import Blueprint

local_auth = Blueprint('local_auth', __name__)

from . import views