MPAgentUploader.py Setup
------------------------------------------------------------------------------------------

To use the agent uploader you will need to create a virtual env and install a few python modules.

Setup Python Virtual Env - 

% python3 -m venv venv --copies --clear
% source venv/bin/activate
% venv/bin/pip3 install --upgrade pip --no-cache-dir
% venv/bin/pip3 install -r {MACPATCH_GIT_CLONE_DIR}/scripts/Agent\ Uploader/Requirements.txt

------------------------------------------------------------------------------------------

How to run MPAgentUploader.py

1) Fill-in all the necessary fields in the MPAgentUploader.config file
2) source the venv (source venv/bin/activate)
3) Run ./MPAgentUploader.py --help to see all the options

The most common way to test a new agent build is. This will build the installer but wont notarize or upload the agent to the MacPatch server.

% ./MPAgentUploader.py -c ./MPAgentUpload.config -d -n -p /Users/smith1/MP-Build/3.6.4/20220208-084745/Combined/MacPatch.pkg.zip --destDir /Users/smith1/MP-Build/3.6.4/20220208-084745

If the build is good and you wish to upload it to the server. The "uploadData.json" file is in the "Completed" directory.

% ./MPAgentUploader.py -c ./MPAgentUpload.config -j /Users/smith1/MP-Build/3.6.4/20220208-084745/Completed/MacPatch_20220208084918/uploadData.json