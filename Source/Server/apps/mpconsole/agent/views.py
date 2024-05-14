from flask import render_template

from . import agent
from mpconsole.model import *

@agent.route('/download')
def clientDownload():
	columns1 = [('puuid', 'puuid', '0'), ('type', 'Type', '0'), ('osver', 'OS Ver', '1'), ('agent_ver', 'Agent Ver', '1'),
				('version', 'Version', '1'), ('build', 'Build', '1'), ('pkg_name', 'Package', '1'), ('pkg_url', 'Package URL', '1'),
				('pkg_hash', 'Package Hash', '1'), ('active', 'Active', '1'), ('state', 'State', '0'), ('mdate', 'Mod Date', '1')]

	qGet1 = MpClientAgent.query.filter(MpClientAgent.type == 'app', MpClientAgent.active == '1').all()
	return render_template('client_download.html', data=qGet1)
