from flask import Blueprint

patches = Blueprint('patches', __name__)

from . import views