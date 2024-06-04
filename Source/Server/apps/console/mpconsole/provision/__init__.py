from flask import Blueprint

provision = Blueprint('provision', __name__)

from . import views