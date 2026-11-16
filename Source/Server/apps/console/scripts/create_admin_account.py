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
import argparse

# Add the console directory (parent of scripts) to path so mpconsole can be imported
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mpconsole.app import create_app
from mpconsole.admin_account import createAdminAccount


def create_admin_account(username='mpadmin', password=None, force=False):
    """
    Create initial admin account in database

    Returns:
        tuple: (success: bool, password: str, message: str)
    """
    app = create_app()
    with app.app_context():
        return createAdminAccount(username=username, password=password, force=force)


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
