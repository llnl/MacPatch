### Table of Contents
* [Default Admin Account](#a1)
	* [Change Password](#a1a)
	* [Disable Admin Account](#a1b)
* [User Accounts](#a2)
	* [Standard Accounts](#a2a)
	* [Directory Accounts](#a2b)
* [Account Rights](#a3)

#### Default Admin <a name='a1'></a>

The default admin account is local to the MacPatch server. This account should only be used for setup of the MacPatch "Master" server. Once a load admin account has been created. It's recommended that the admin account be disabled.

##### - Change Default Admin password
<a name='a1a'></a>Changing the default admin account password requires editing the **siteconfig.json** file. This file is lcoated in "/opt/MacPatch/Server/etc/". Please note, the password is in clear text.

##### - Disable Default Admin account
<a name='a1b'></a> Disabling the default requires editing the **siteconfig.json** file. This file is lcoated in "/opt/MacPatch/Server/etc/". To disable the account simply change the "enabled" key value to "false".

**From:**
<pre>
`"users": {
    "admin": {
        "enabled": true,
        "name": "mpadmin",
        "pass": "*mpadmin*"
    }
}`
</pre>
**To:**
<pre>
`"users": {
    "admin": {
        "enabled": false,
        "name": "mpadmin",
        "pass": "*mpadmin*"
    }
}`
</pre>

#### User Accounts <a name='a2'></a>

MacPatch supports 2 different accounts not including the default admin account. MacPatch supports standard database accounts and LDAP/Active Directory accounts.

<a name='a2a'></a>
##### Local Accounts
To add or remove a standard account, navigate to the Admin->Accounts menu. Simply click on the "+" icon just above the accounts table.

Assiging rights to a user account is fairly straight forward. If no rights are assigned the user can login and create a Client group and a patch group. This user will also be the owner of these groups and can assign additional users who can assist in managing these options.

<a name='a2b'></a>
##### Directory Accounts
MacPatch supports user accounts coming from LDAP/Active directory. During the server setup you were asked if you wanted to enable LDAP user support. If you answered "Yes", then all of your settings were entered in to the "siteconfig.json" file. The settings are under the "ldap" key.

By default any user in the directory is allowed to login to MacPatch. This user will have the basic standard user rights. If you wish to limit directory users who can log in to the MacPatch admin console you will need to populate to keys in the "ldap" dictiobnary. First you will need to enable the "enableGroupFilter" attribute by setting it to "true". Then you will need to edit the "groupFilter" attribute. This attribute is a list, and is just the name the LDAP group.

Example:
`"groupFilter": ['Group1', 'Group2']`

Assiging rights to ldap users is just like a standard account. The only difference is the user has to login at least one time so that the user will show in the accounts table.

#### Account Rights <a name='a3'></a>

|Right |Description|
|---|---|
|Admin | This right gives the user admin rights through out the console.|
|AutoPKG | This right allows the user account to upload new packages using the autopkg tool.  |
|Agent Upload | This rtight allows the user to upload new MacPatch client agents. |
|API | This right allows the user to access MacPatch API's for automation. (Not Completed)|
