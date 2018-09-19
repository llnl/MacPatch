## Table of Contents
* [Required Software](#a1)
* [Perquisites](#a2)
	* [Linux Packages](#a2a)
	* [MySQL](#a2b)
* [Download, Setup and Install](#a3)
	* [Get Software](#a3a)
	* [Setup Database](#a3b)
	* [Install Server Software](#a3c)
	* [Configure Server Software](#a3d)
	* [Load and Populate Database](#a3f)
* [Server Setup & Configuration](#a4)
	* [First Login](#a4a)
	* [Server Configuration](#a4b)
	* [Default Patch Group Configuration](#a4c)
	* [Client Agent Configuration](#a4d)
* [Download and Add Patch Content](#a5)
	* [Apple Patches](#a5a)
	* [Custom Patches](#a5b)

### Prequisits & Requirements
root or sudo access will be needed to perform these tasks.

#### Requirements <a name='a1'></a>
- Operating System:
	- macOS
		- Mac OS X 10.10 or higher
	- Linux
		- RHEL 7.x or CentOS 7.x
		- Ubuntu Server 16.04
- RAM: 4 Gig min
- MySQL (5.6.x is Recommended)
	- 	MySQL 8 not tested.

#### Perquisites <a name='a2'></a>
- Install MySQL 5.6.x (must have root password)
- If Installing on Mac OS X, **Xcode and command line developer tools** need to be installed **AND** the license agreement needs to have been accepted.

##### Linux Packages <a name='a2a'></a>

The MacPatch server build script will attempt to install a number of required software packages there are a few packages that are recommended that be installed prior to running the build script.

**RedHat & CentOS**

RedHat & CentOS will require the "Development tools" group install. This group has a number of packages needed to build the MacPatch server.

	yum groupinstall "Development tools"
	yum install epel-release

**Ubuntu**

	apt-get install build-essential

##### MySQL <a name='a2b'></a>

While MySQL 5.6 is still the recommended database version. MySQL 5.7 has been out for some time now. MySQL changed the sql_mode settings in 5.7 which broke some queries in MacPatch. In order to use MacPatch with MySQL 5.7 the **sql\_mode** setting will have to be changed.

To view and set the config use

	SELECT @@GLOBAL.sql_mode;
	SET GLOBAL sql_mode = 'modes';

The default SQL mode in MySQL 5.7 includes these modes:

	ONLY_FULL_GROUP_BY, STRICT_TRANS_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO, NO_AUTO_CREATE_USER, and NO_ENGINE_SUBSTITUTION.

The default SQL mode in MySQL 5.6 includes this mode:

	NO_ENGINE_SUBSTITUTION

Preliminary testing has been successful when removing the **ONLY\_FULL\_GROUP\_BY** mode.

### Download, Setup and Install <a name='a3'></a>

##### Get Software <a name='a3a'></a>
		mkdir /opt (If Needed)
		cd /opt
		git clone https://github.com/LLNL/MacPatch.git

##### Setup Database <a name='a3b'></a>

The database setup script only creates the MacPatch database and the 2 database accounts needed to use the database. Tuning the MySQL server is out of scope for this document.

Please remeber the passwords for mpdbadm and mpdbro accounts while running this script. They will be required during the SetupServer.py script database section.

		cd /opt/MacPatch/Server/conf/scripts/setup
		./MPDBSetup.sh (must be run on the MySQL server)

**Note:** The MPDBSetup.sh ***can be/should be*** copied to another host if the database exists on a seperate server.

##### Install Software <a name='a3c'></a>

		cd /opt/MacPatch/Scripts
		sudo ./MPBuildServer.sh

**Note:** If your behind a SSL content inspector add the custom ca using

		export PIP_CERT=/path/to/ca/cert.crt

##### Configure Server Software <a name='a3d'></a>

		cd /opt/MacPatch/Server/conf/scripts/setup
		sudo ./ServerSetup.py --setup

##### Configure MacPatch schema & populate default data <a name='a3f'></a>

		cd /opt/MacPatch/Server/apps
		source env/bin/activate
		./mpapi.py db upgrade head
		./mpapi.py populate_db
		deactivate

**Note:** If "mpapi.py db upgrade head" is done using a root shell. Please delete the "/opt/MacPatch/Server/logs/mpwsapi.log" file. It will be owned by root and the REST api will not launch.

##### Start Services

		cd /opt/MacPatch/Server/conf/scripts/setup
		sudo ./ServerSetup.py --load All

--

### Server Setup & Configuration <a name='a4'></a>

The MacPatch server software has now been installed and should be up and running. The server is almost ready for accepting clients. There are a few more server configuration settings which need to be configured.

#### First Login <a name='a4a'></a>
The default user name is “mpadmin” and the password is “\*mpadmin\*”, Unless it was changed using the “ServerSetup.py” script. You will need to login for the first time with this account to do all of the setup tasks. Once these tasks are completed it’s recommended that this account be disabled. This can be done by editing the **siteconfig.json** file, which is located in /opt/MacPatch/Server/etc/.

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
#### Server Configuration <a name='a4b'></a>
Each MacPatch server needs to be added to the environment. The master server is always added automatically.

It is recommended that you login and verify the master server settings. It is common during install that the master server address will be added as localhost or 127.0.0.1. Please make sure that the correct hostname or IP address is set and that **"active"** is enabled.

* Go to “Admin -> Server -> MacPatch Servers”
* Double Click the row with your server or single click the row and click the “Pencil” button.

#### Default Patch Group Configuration <a name='a4c'></a>
A default patch group will be created during install. The name of the default patch group is “Default”. You may use it or create a new one.

To edit the contents for the patch group simply click the “Pencil” icon next to the group name. To add patches click the check boxes to add or subtract patches from the group. When done click the “Save” icon. (Important Step)

* Go to “Patches -> Patch Groups”
* Double Click the row with your server or single click the row and click the “Pencil” button.

#### Client Agent Configuration <a name='a4d'></a>

A default agent configuration is added during the install. Please verify the client agent configuration before the client agent is uploaded.

**Recommended**

* Go to “Admin -> Client Agents -> Configure”
* Set the following 3 properties to be enforced
	* MPServerAddress
	* MPServerPort
	* MPServerSSL
* Verify the “PatchGroup” setting. If you have changed it set it before you upload the client agent.
* Click the save button
* Click the icon in the “Default” column for the default configuration. (Important Step)
* Set MPServerAllowSelfSigned to 1 if your in a test environment and not using a valid SSL vertificate.

Only the default agent configuration will get added to the client agent upon upload.


--

### Download & Add Patch Content <a name='a5'></a>

**Apple Updates** <a name='a5a'></a>

Apple patch content will download eventually on it’s own cycle, but for the first time it’s recommended to download it manually.

The Apple Software Update content settings are stored in a json file (/opt/MacPatch/Server/etc/patchloader.json). By default, Apple patches for 10.9 through 10.12 will be processed and supported.

Run the following command via the Terminal on the Master MacPatch server.

**Linux**

	# sudo -u www-data /opt/MacPatch/Server/conf/scripts/MPSUSPatchSync.py

**Mac**

	# sudo -u _appserver /opt/MacPatch/Server/conf/scripts/MPSUSPatchSync.py

**Custom Updates** <a name='a5b'></a>

To create your own custom patch content please read the "Custom Patch Content" [docs](http://macpatch.llnl.gov/docs/4_custom-patch-content/).

To use "AutoPkg" to add patch content please read the "AutoPkg patch content" [docs](http://macpatch.llnl.gov/docs/7_packaging-autopkg/).
