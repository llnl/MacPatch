# Remove Plaintext Credentials from Siteconfig - Summary

This document summarizes the solution to remove hardcoded plaintext credentials from `siteconfig.json` and use secure database authentication instead.

---


**Usage:**

### Auto-generate secure password
`python3 create_admin_account.py`

### Specify custom password
`python3 create_admin_account.py --password "MySecureP@ss"`

### Custom username
`python3 create_admin_account.py --username admin`


**Output:**

```
MacPatch Admin Account Created

  Username: mpadmin
  Password: 8vK2$mN9#pLx4@Zy7wQ1

===================================================================
  IMPORTANT:
  1. Save this password securely - it cannot be recovered
  2. Login at: http://your-server/local_auth/login
  3. Change your password after first login
===================================================================
```

### 2. **migrate_siteconfig_admin.py**
One-time migration for existing installations.

**Usage:**

```
# Migrate with new auto-generated password (recommended)
python3 migrate_siteconfig_admin.py

# Keep existing password for backward compatibility
python3 migrate_siteconfig_admin.py --use-default-password
```

---



## Examples

### Example 1: New Installation

```
# 1. Install MacPatch (with updated code)

# 2. Create initial admin account
cd /opt/MacPatch/Server/apps/console/scripts
python3 create_admin_account.py

# Output Example:
#   Username: mpadmin
#   Password: 8vK2$mN9#pLx4@Zy7wQ1

# 3. Login and create additional admins
# http://your-server/local_auth/login

# 4. Done!
```

### Example 2: Upgrade Existing Installation

```
# 1. Before upgrade, check current siteconfig
cat /opt/MacPatch/Server/etc/siteconfig.json | grep -A5 '"admin"'

# Output:
#   "admin": {
#       "enabled": true,
#       "name": "mpadmin",
#       "pass": "*mpadmin*"
#   }

# 2. Upgrade MacPatch to new version

# 3. Run migration script
cd /opt/MacPatch/Server/apps/console/scripts
python3 migrate_siteconfig_admin.py

# Output:
#   ✓ Found admin account: mpadmin
#   ✓ Created database account
#   New Password: 8vK2$mN9#pLx4@Zy7wQ1

# 4. Disable siteconfig admin
jq 'del(.settings.users.admin)' /opt/MacPatch/Server/etc/siteconfig.json > /tmp/config.json
mv /tmp/config.json /opt/MacPatch/Server/etc/siteconfig.json

# 5. Restart services
systemctl restart MPConsole MPAPI

# 6. Test login with new password
# http://your-server/local_auth/login
```

### Example 3: Migration Keeping Old Password

```
# For backward compatibility, keep the existing password
python3 migrate_siteconfig_admin.py --use-default-password

# Output:
#   Username: mpadmin
#   Password: *mpadmin*  (unchanged)

# This allows existing scripts/processes to continue working
# while you transition to new password management
```
