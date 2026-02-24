from mpconsole.app import create_app, db
from mpconsole.mpsetupdb import addDefaultData, addSiteKeys, resetSiteKeys
from flask_migrate import Migrate

app = create_app()
migrate = Migrate(app, db)

@app.shell_context_processor
def make_shell_context():
	return dict(app=app, db=db)

@app.cli.command()
def populate_db():
	print('Add Default Data to Database')
	addDefaultData()
	print('Default Data Added to Database')

@app.cli.command()
def add_site_keys():
	print('Add Site Keys to Database')
	addSiteKeys()
	print('Default Site Keys Added to Database')
	 
@app.cli.command()
def reset_site_keys():
	print('Reset Site Keys in Database')
	resetSiteKeys()
	print('Site Keys Added to Database')
