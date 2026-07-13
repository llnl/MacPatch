#!/usr/bin/env python3
"""
MacPatch Initial Admin Account Creator

Creates the mpadmin database account for initial setup.
This replaces the plaintext password stored in siteconfig.json.

Usage:
    python3 create_admin_account.py [--username USERNAME] [--password PASSWORD]

If password is not provided, a strong random password will be generated.
"""

import sys
import os
import secrets
import string
import argparse
from datetime import datetime

# Add the mpconsole module to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mpconsole.app import create_app, db
from mpconsole.model import AdmUsers, AdmUsersInfo
from werkzeug.security import generate_password_hash


def generate_strong_password(length=20):
    """Generate a cryptographically secure random password"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_=+"
    password = ''.join(secrets.choice(alphabet) for _ in range(length))
    return password


def create_admin_account(username='mpadmin', password=None, force=False):
    """
    Create initial admin account in database

    Args:
        username: Admin username (default: mpadmin)
        password: Admin password (if None, generates random password)
        force: If True, recreate account even if it exists

    Returns:
        tuple: (success: bool, password: str, message: str)
    """

    app = create_app()

    with app.app_context():
        # Check if admin user already exists
        existing_user = AdmUsers.query.filter_by(user_id=username).first()
        existing_info = AdmUsersInfo.query.filter_by(user_id=username).first()

        if existing_user and not force:
            return False, None, f"User '{username}' already exists. Use --force to recreate."

        # Generate password if not provided
        if password is None:
            password = generate_strong_password()

        try:
            # Delete existing user if force flag is set
            if force:
                if existing_user:
                    db.session.delete(existing_user)
                if existing_info:
                    db.session.delete(existing_info)
                db.session.commit()

            # Create AdmUsers entry with hashed password
            admin_user = AdmUsers()
            admin_user.user_id = username
            admin_user.user_pass = generate_password_hash(password)

            db.session.add(admin_user)
            db.session.commit()

            # Create AdmUsersInfo entry with admin privileges
            admin_info = AdmUsersInfo()
            admin_info.user_id = username
            admin_info.user_type = 1  # Database user
            admin_info.enabled = 1
            admin_info.admin = 1
            admin_info.autopkg = 1
            admin_info.agentUpload = 1
            admin_info.apiAccess = 1
            admin_info.number_of_logins = 0
            admin_info.last_login = datetime.now()

            db.session.add(admin_info)
            db.session.commit()

            return True, password, f"Admin account '{username}' created successfully."

        except Exception as e:
            db.session.rollback()
            return False, None, f"Error creating admin account: {str(e)}"


def main():
    parser = argparse.ArgumentParser(
        description='Create MacPatch initial admin account',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create mpadmin with auto-generated password
  python3 create_admin_account.py

  # Create mpadmin with specific password
  python3 create_admin_account.py --password "MySecureP@ssw0rd"

  # Create custom username
  python3 create_admin_account.py --username admin --password "MyP@ss"

  # Recreate existing account
  python3 create_admin_account.py --force

Security Notes:
  - Generated passwords are 20 characters with mixed case, digits, and symbols
  - Passwords are hashed using Werkzeug's secure hash (bcrypt/scrypt)
  - Save the generated password securely - it cannot be recovered
  - Change the password after first login via the web console
        """
    )

    parser.add_argument(
        '--username',
        default='mpadmin',
        help='Admin username (default: mpadmin)'
    )

    parser.add_argument(
        '--password',
        help='Admin password (if not provided, generates random password)'
    )

    parser.add_argument(
        '--force',
        action='store_true',
        help='Recreate account if it already exists'
    )

    parser.add_argument(
        '--quiet',
        action='store_true',
        help='Only output the password (for scripting)'
    )

    args = parser.parse_args()

    # Validate password strength if provided
    if args.password:
        if len(args.password) < 8:
            print("ERROR: Password must be at least 8 characters", file=sys.stderr)
            sys.exit(1)

    # Create the account
    success, password, message = create_admin_account(
        username=args.username,
        password=args.password,
        force=args.force
    )

    if success:
        if args.quiet:
            # For scripting: only output password
            print(password)
        else:
            print("\n" + "=" * 70)
            print("  MacPatch Admin Account Created")
            print("=" * 70)
            print(f"\n  Username: {args.username}")
            print(f"  Password: {password}")
            print("\n" + "=" * 70)
            print("\n  IMPORTANT:")
            print("  1. Save this password securely - it cannot be recovered")
            print("  2. Login at: http://your-server/local_auth/login")
            print("  3. Change your password after first login")
            print("  4. Create additional admin accounts via the web console")
            print("  5. Consider disabling 'mpadmin' after creating other admins")
            print("\n" + "=" * 70 + "\n")

        sys.exit(0)
    else:
        if not args.quiet:
            print(f"ERROR: {message}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
