from flask import Blueprint

software = Blueprint('software', __name__)

from . import views