from flask import Blueprint

registration = Blueprint('registration', __name__)

from . import views