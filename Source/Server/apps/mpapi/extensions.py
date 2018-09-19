from flask import Flask

from flask_sqlalchemy import SQLAlchemy
db = SQLAlchemy()

from flask_migrate import Migrate
migrate = Migrate()

from flask_caching import Cache
cache = Cache()
