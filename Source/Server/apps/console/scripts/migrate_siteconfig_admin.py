#!/usr/bin/env python3
"""
MacPatch Siteconfig Admin Migration Script

Migrates the mpadmin account from siteconfig.json (plaintext) to database (hashed).

This is a ONE-TIME migration script for existing installations upgrading to
the version that removes siteconfig authentication.

Usage:
    python3 migrate_siteconfig_admin.py [--use-default-password]
"""

import sys
import os
import secrets
import string
import argparse
import json
from datetime import datetime

# Add the mpconsole module to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mpconsole.app import create_app, db
from mpconsole.model import AdmUsers, AdmUsersInfo
from mpconsole.mputil import return_data_for_root_key
from werkzeug.security import generate_password_hash


def read_siteconfig_admin():
    """Read admin config from siteconfig.json"""
    try:
        users = return_data_for_root_key('users')
        if 'admin' not in users:
            return None, "No 'admin' section found in siteconfig users"

        admin = users['admin']
        if not admin.get('enabled'):
            return None, "Siteconfig admin is disabled, nothing to migrate"

        return {
            'username': admin.get('name', 'mpadmin'),
            'password': admin.get('pass', '*mpadmin*'),
            'enabled': admin.get('enabled', True)
        }, None

    except Exception as e:
        return None, f"Error reading siteconfig: {str(e)}"


def generate_strong_password(length=20):
    """Generate a cryptographically secure random password"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_=+"
    password = ''.join(secrets.choice(alphabet) for _ in range(length))
    return password


def migrate_admin_to_database(admin_config, use_default_password=False):
    """
    Migrate admin account from siteconfig to database

    Args:
        admin_config: Dict with username and password from siteconfig
        use_default_password: If True, keeps the siteconfig password instead of generating new one

    Returns:
        tuple: (success: bool, new_password: str, message: str)
    """

    app = create_app()

    with app.app_context():
        username = admin_config['username']
        old_password = admin_config['password']

        # Check if user already exists in database
        existing_user = AdmUsers.query.filter_by(user_id=username).first()
        if existing_user:
            return False, None, f"User '{username}' already exists in database. Migration not needed."

        # Determine what password to use
        if use_default_password:
            # Keep the siteconfig password (for backward compatibility)
            new_password = old_password
            password_source = "siteconfig password"
        else:
            # Generate new secure password
            new_password = generate_strong_password()
            password_source = "auto-generated"

        try:
            # Create AdmUsers entry with hashed password
            admin_user = AdmUsers()
            admin_user.user_id = username
            admin_user.user_pass = generate_password_hash(new_password)

            db.session.add(admin_user)
            db.session.commit()

            # Create AdmUsersInfo entry with admin privileges
            admin_info = AdmUsersInfo()
            admin_info.user_id = username
            admin_info.user_type = 1  # Database user (not siteconfig)
            admin_info.enabled = 1
            admin_info.admin = 1
            admin_info.autopkg = 1
            admin_info.agentUpload = 1
            admin_info.apiAccess = 1
            admin_info.number_of_logins = 0
            admin_info.last_login = datetime.now()

            db.session.add(admin_info)
            db.session.commit()

            message = f"Successfully migrated '{username}' to database with {password_source}"
            return True, new_password, message

        except Exception as e:
            db.session.rollback()
            return False, None, f"Error creating database entry: {str(e)}"


def main():
    parser = argparse.ArgumentParser(
        description='Migrate MacPatch admin account from siteconfig to database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
This script migrates the mpadmin account from plaintext siteconfig.json storage
to hashed database storage.

By default, a NEW strong random password will be generated for security.
Use --use-default-password to keep the existing siteconfig password.

Examples:
  # Migrate with new auto-generated password (recommended)
  python3 migrate_siteconfig_admin.py

  # Migrate keeping the existing password
  python3 migrate_siteconfig_admin.py --use-default-password

After Migration:
  1. Test login with the new password
  2. Edit siteconfig.json to disable or remove the admin section
  3. Restart MacPatch services
        """
    )

    parser.add_argument(
        '--use-default-password',
        action='store_true',
        help='Keep the existing siteconfig password instead of generating a new one'
    )

    parser.add_argument(
        '--quiet',
        action='store_true',
        help='Minimal output (for scripting)'
    )

    args = parser.parse_args()

    # Read siteconfig admin
    if not args.quiet:
        print("\n" + "=" * 70)
        print("  MacPatch Siteconfig Admin Migration")
        print("=" * 70 + "\n")
        print("Step 1: Reading siteconfig.json...")

    admin_config, error = read_siteconfig_admin()

    if error:
        if not args.quiet:
            print(f"\nNo migration needed: {error}\n")
        sys.exit(0)

    if not args.quiet:
        print(f"  ✓ Found admin account: {admin_config['username']}")
        print(f"  ✓ Current password: {'*' * len(admin_config['password'])} (plaintext)")

    # Migrate to database
    if not args.quiet:
        print("\nStep 2: Creating database account with hashed password...")

    success, new_password, message = migrate_admin_to_database(
        admin_config,
        use_default_password=args.use_default_password
    )

    if success:
        if args.quiet:
            # For scripting: only output critical info
            print(f"{admin_config['username']}:{new_password}")
        else:
            print(f"  ✓ {message}")
            print("\n" + "=" * 70)
            print("  Migration Successful!")
            print("=" * 70)
            print(f"\n  Username: {admin_config['username']}")
            print(f"  New Password: {new_password}")
            print("\n" + "=" * 70)
            print("\n  NEXT STEPS:")
            print("  -----------")
            print(f"  1. Test login at http://your-server/local_auth/login")
            print(f"     Username: {admin_config['username']}")
            print(f"     Password: {new_password}")
            print()
            print("  2. Edit /opt/MacPatch/Server/etc/siteconfig.json:")
            print("     Remove or disable the 'users.admin' section:")
            print()
            print('     "users": {')
            print('         "admin": {')
            print('             "enabled": false,   ← Change to false')
            print('             "name": "mpadmin",')
            print('             "pass": "*mpadmin*"')
            print('         }')
            print('     }')
            print()
            print("     Or run:")
            print('     jq \'del(.settings.users.admin)\' siteconfig.json > config.new')
            print('     mv config.new siteconfig.json')
            print()
            print("  3. Restart MacPatch services:")
            print("     systemctl restart macpatch-console")
            print()
            print("  4. Save the new password securely and change it after login")
            print("\n" + "=" * 70 + "\n")

        sys.exit(0)
    else:
        if not args.quiet:
            print(f"\nMigration failed: {message}")
            print()
        else:
            print(f"ERROR: {message}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
