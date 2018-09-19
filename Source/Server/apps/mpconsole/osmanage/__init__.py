from flask import Blueprint

osmanage = Blueprint('osmanage', __name__)

from . import views