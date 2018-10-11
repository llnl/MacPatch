
<a name='a1'></a>Apple patch content in MacPatch is collected from the Apple Software Update servers. Every patch apple offers is processed and posted to the MacPatch database via the `MPSUSPatchSync.py` script. This script is run on a 8 hour interval by default. By default all new apple patches will show up in the database with it's patch state set to "Create". In order for a patch to install it's state needs to be changed to "QA" or "Production".

**Example - Apple patch in `Create` state**

[![](images/content/apple1.png)](images/content/apple1.png)

#### Extending an Apple Patch <a name='a2'></a>

MacPatch offers the ability to enhance and extend apple supplied patches. MacPatch offers the ability to change the order in which the patch is installed. This is done with the "Patch Install Weight"; the lower the number the sooner the install. By default custom patches have an install weight of 30 and apple patches have an install weight of 60. You also have the ability to override the reboot setting as well. For example if you have an apple patch that does not require a reboot you can change it so it does and vice versa.

[![](images/content/apple2.png)](images/content/apple2.png)

The final option to extending an apple patch is being able to assign and pre and post install script.

[![](images/content/apple3.png)](images/content/apple3.png)

### Testing Patch Content <a name='a3'></a>

The preferred method to testing new patches is once a patch has been created involves creating a new patch group and client group and changing the client setting for the new client group.

* Create new patch group, call it "QA"
* Create new client group, call it "QA"
* Edit the client group settings
	* Set "Patch Group" to "QA"
	* Set "Patch State Patching" to "Production & QA"
	* Save the settings
* Assign client to the "QA" client group

With the groups and the settings created, and client(s) assigned. The next step will be to change the "Patch State" on the newly created patch to "QA".
In this configuration any client assigned to the QA client group will now scan for the new patch, it will not patch it until the new patch has been added to the QA patch group and saved.
