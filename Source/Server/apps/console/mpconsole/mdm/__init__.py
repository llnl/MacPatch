from flask import Blueprint

mdm = Blueprint('mdm', __name__)

from . import views