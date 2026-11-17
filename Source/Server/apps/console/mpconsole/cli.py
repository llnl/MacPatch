'''
	MacPatch Console setup commands (flask CLI)

	Normally run by ServerSetup.py (--setup, --setup-db, --config admin), they can
	also be run by hand from /opt/MacPatch/Server/apps/console/mpconsole with the
	console virtual env active, e.g.

		flask db upgrade head
		flask populate-db
		flask add-admin --username mpadmin
'''
import sys
import click

from mpconsole.admin_account import createAdminAccount, getAdminAccount
from mpconsole.mpsetupdb import checkDatabase, addDefaultData, addSiteKeys, resetSiteKeys, addUnassignedClientsToGroup
from mpconsole.software.checks import findBrokenSoftwareTasks, deactivateSoftwareTasks, deleteSoftwareTasks

DB_SETUP_STEPS = """
  The MacPatch database must be set up before running this command.

  1. Run MPDBSetup.sql on the MySQL server, to create the database and account.
  2. Verify the database settings (DB_HOST, DB_NAME, DB_USER, DB_PASS) are correct
       sudo /opt/MacPatch/Server/conf/scripts/setup/ServerSetup.py --config database
  3. Create the database schema and default data
       sudo /opt/MacPatch/Server/conf/scripts/setup/ServerSetup.py --setup-db
"""

ADMIN_SETUP_STEPS = """
  No enabled admin account was found in the database.
  The default groups are owned by the first admin account, create one with:

       sudo /opt/MacPatch/Server/conf/scripts/setup/ServerSetup.py --config admin

  Then re-run: sudo /opt/MacPatch/Server/conf/scripts/setup/ServerSetup.py --setup-db
"""

'''
	Helpers
'''
def requireDatabase():
	ok, message = checkDatabase()
	if not ok:
		click.echo(f"\nERROR: {message}")
		click.echo(DB_SETUP_STEPS)
		sys.exit(1)

def promptForPassword():
	"""Prompt for a new password, returns None to have one generated"""
	while True:
		password = click.prompt("Password (leave blank to generate one)", hide_input=True, default="", show_default=False)
		if not password:
			return None
		if len(password) < 8:
			click.echo("Password must be at least 8 characters.")
			continue
		if password == click.prompt("Confirm password", hide_input=True, default="", show_default=False):
			return password
		click.echo("Passwords do not match.")

def addAdmin(username, password=None, force=False):
	"""Create an admin account, returns the user_id or None"""
	success, password, message = createAdminAccount(username=username, password=password, force=force)
	if not success:
		click.echo(f"ERROR: {message}")
		return None

	click.echo("\n" + "=" * 70)
	click.echo("  MacPatch Admin Account Created")
	click.echo("=" * 70)
	click.echo(f"\n  Username: {username}")
	click.echo(f"  Password: {password}")
	click.echo("\n  Save this password securely - it cannot be recovered.")
	click.echo("  Change it after your first login.")
	click.echo("=" * 70 + "\n")
	return username

'''
	Commands
'''
def register_cli(app):

	@app.cli.command('populate-db')
	def populate_db():
		"""Add the default data for a new install, prompts for the first admin account if needed."""
		requireDatabase()

		owner = getAdminAccount()
		if owner is None and sys.stdin.isatty():
			click.echo("\nNo enabled admin account was found in the database.")
			if click.confirm("Create the first admin account now?", default=True):
				username = click.prompt("Admin account name", default="mpadmin")
				owner = addAdmin(username, promptForPassword())

		if owner is None:
			click.echo(ADMIN_SETUP_STEPS)
			sys.exit(1)

		click.echo(f"Adding default data, default groups will be owned by '{owner}'")
		addDefaultData(owner)

	@app.cli.command('add-admin')
	@click.option('--username', default='mpadmin', show_default=True, help='Admin account name.')
	@click.option('--password', default=None, help='Admin password (default: prompt, or generate when not interactive).')
	@click.option('--force', is_flag=True, help='Recreate the account if it already exists.')
	def add_admin(username, password, force):
		"""Create a console admin account in the database."""
		requireDatabase()
		if password is not None and len(password) < 8:
			click.echo("ERROR: Password must be at least 8 characters")
			sys.exit(1)

		if password is None and sys.stdin.isatty():
			password = promptForPassword()

		if addAdmin(username, password, force) is None:
			sys.exit(1)

	@app.cli.command('add-site-keys')
	def add_site_keys():
		"""Add the site keys from siteconfig.json to the database."""
		requireDatabase()
		addSiteKeys()

	@app.cli.command('reset-site-keys')
	def reset_site_keys():
		"""Replace the active site keys with the keys from siteconfig.json."""
		requireDatabase()
		resetSiteKeys()

	@app.cli.command('assign-to-default')
	def assign_to_default():
		"""Assign any client not in a group to the default group."""
		requireDatabase()
		addUnassignedClientsToGroup()

	@app.cli.command('check-software-tasks')
	@click.option('--deactivate', is_flag=True, help='Also set the broken tasks to inactive (default: report only).')
	@click.option('--delete', 'delete_tasks', is_flag=True,
		help='Delete the broken tasks, after removing them from their software groups and client groups.')
	@click.option('--yes', is_flag=True, help='Do not ask for confirmation before deleting.')
	def check_software_tasks(deactivate, delete_tasks, yes):
		"""Check that every software task still has its primary software package.

		Exits 0 when all tasks are fine and 1 when any are broken, so it can run from cron.
		"""
		if deactivate and delete_tasks:
			click.echo("ERROR: Use either --deactivate or --delete, not both.")
			sys.exit(2)

		requireDatabase()
		total, broken = findBrokenSoftwareTasks()

		click.echo(f"Checked {total} software task(s).")
		if not broken:
			click.echo("All software tasks have a primary software package.")
			return

		click.echo(f"\n{len(broken)} software task(s) have no primary software package:\n")
		click.echo(f"  {'Task ID':<37} {'Active':<6} {'Name':<31} Problem")
		click.echo(f"  {'-' * 37} {'-' * 6} {'-' * 31} {'-' * 40}")
		for t in broken:
			click.echo(f"  {t['tuuid']:<37} {'Yes' if t['active'] == 1 else 'No':<6} {t['name'][:31]:<31} {t['problem']}")
			for g in t['groups']:
				label = g['name'] if g['name'] else '(group no longer exists)'
				click.echo(f"      assigned to software group: {label} [{g['gid']}]")
			for g in t['clientGroups']:
				label = g['name'] if g['name'] else '(group no longer exists)'
				click.echo(f"      assigned to client group:   {label} [{g['gid']}]")

		in_groups = [t for t in broken if t['groups'] or t['clientGroups']]
		if in_groups:
			click.echo(f"\n{len(in_groups)} of these are assigned to software or client groups.")
		else:
			click.echo("\nNone of these are assigned to a group.")

		if delete_tasks:
			if not yes:
				if not sys.stdin.isatty():
					click.echo("\nERROR: Not an interactive terminal, add --yes to delete without a prompt.")
					sys.exit(2)
				if not click.confirm(f"\nRemove these {len(broken)} task(s) from their groups and delete them?", default=False):
					click.echo("Nothing was deleted.")
					sys.exit(1)

			rebuilt = []
			def republish(group_id):
				if republishGroup(group_id):
					rebuilt.append(group_id)

			result = deleteSoftwareTasks([t['tuuid'] for t in broken], republish=republish, log=lambda m: click.echo(f"  {m}"))
			click.echo(f"\nDeleted {result['deleted']} task(s), removed {result['softwareGroupRows']} software group "
				f"assignment(s) and {result['clientGroupRows']} client group assignment(s).")
			if result['groups']:
				click.echo(f"Rebuilt the published task data for {len(rebuilt)} of {len(result['groups'])} software group(s).")
			if len(rebuilt) < len(result['groups']):
				click.echo("Open the software groups listed in the warnings and save their tasks to rebuild them.")
				sys.exit(1)
			return

		if deactivate:
			count = deactivateSoftwareTasks([t['tuuid'] for t in broken if t['active'] == 1])
			click.echo(f"\nSet {count} active task(s) to inactive.")
		else:
			active = sum(1 for t in broken if t['active'] == 1)
			if active:
				click.echo(f"\n{active} of these are active. Re-run with --deactivate to turn them off, or --delete to remove them.")

		sys.exit(1)

def republishGroup(group_id):
	"""Rebuild a software group's published task data, the same as saving its tasks in the console.
	Returns True when it worked."""
	try:
		from mpconsole.software.views import _publishGroupTasks
		body, status = _publishGroupTasks(group_id)
	except Exception as e:
		click.echo(f"  WARNING: could not rebuild the published task data for software group {group_id}: {e}")
		return False

	if status != 200:
		click.echo(f"  WARNING: could not rebuild the published task data for software group {group_id}: {body}")
		return False
	return True
