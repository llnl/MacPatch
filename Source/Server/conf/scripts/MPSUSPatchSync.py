#!/opt/MacPatch/Server/env/server/bin/python3

'''
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.

 This file is part of MacPatch, a program for installing and patching
 software.

 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.

 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.

 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
'''

'''
    Script: MPSUSPatchSync
    Version: 1.6.1

    Description: This Script read all of the patch information
    from the apple software update sucatlog files and post the
    info to the MacPatch database.

    Requirements:
    Python, the requests Library is required use pip or easy_install

    Sample Config JSON:

    {
        "description" : "Configuration settings for SUS Patch loader",
        "settings": {
            "ASUSServer": "swscan.apple.com",
            "Catalogs": [
                {
                    "osver": "10.9",
                    "catalogurl":"/content/catalogs/others/index-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog",
                    "enabled": true
                },
                {
                    "osver": "10.10",
                    "catalogurl":"/content/catalogs/others/index-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog",
                    "enabled": true
                },
                {
                    "osver": "10.11",
                    "catalogurl":"/content/catalogs/others/index-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog",
                    "enabled": false
                }
            ],
            "MPServerAddress":"localhost",
            "MPServerPort":"2600",
            "MPServerUseSSL": false
        }
    }
'''

import datetime
import logging
import os
import argparse
import re
import json
import requests
import xml.etree.ElementTree as ET
import base64
import sys
import subprocess
import hashlib
import plistlib
import fnmatch
from pprint import pprint
from sys import platform
import simplejson

MP_SRV_BASE  = "/opt/MacPatch/Server"
logFileName  = "MPSUSPatchSync.log"
logFile      = MP_SRV_BASE+"/logs/"+logFileName
loaderConf   = MP_SRV_BASE+"/etc/patchloader.json"
siteConf     = MP_SRV_BASE+"/etc/siteconfig.json"

# Define logging for global use
logger = logging.getLogger('MPSUSPatchSync')
_par_dir = os.path.abspath(os.path.join(logFile, os.pardir))
if not os.path.exists(_par_dir):
    logFile = "/tmp/"+logFileName
    print("Changing log file location to " + logFile)

# Variables That Can be Changed
wsPostKey       = '123456' # Ref from siteconfig.json settings->server->apiKey

# Do not Change
susConfig = {}
wsPostAPIURI    = '/api/v1/sus/patches/apple'
wsPostKeyHash   = 'NA'  #hashlib.md5(wsPostKey).hexdigest()
wsPostVersion   = "1.0.0"

# --------------------------------------------
# Define Main Methods
# --------------------------------------------

def createWSApiKeyHash(key, datetimestamp):

    apiKeyFormat = "%s-%s" % (key, datetimestamp)
    _apiKeyHash  = hashlib.sha1(apiKeyFormat.encode('utf-8')).hexdigest()
    return _apiKeyHash.lower()

def returnVersionFromCDATAString(aStr):
    _str = aStr.replace("'", '')
    _str = _str.replace("\"", '')
    _str = _str.replace(";", '')
    return _str.split("=")[1].strip()

def returnDateTimeAsString(aDate):
    # Converts a datetime object to string, needed for JSON
    return aDate.strftime('%Y-%m-%d %H:%M:%S')

# Deprecated
def readServerMetadata(metaURL):

    title = 'NA'
    version = '1.0.0'
    description = 'NA'

    r = requests.get(metaURL)
    if r.status_code == requests.codes.ok:

        #plist = plistlib.readPlistFromString(r.text.encode('utf-8'))
        plist = plistlib.loads(r.text.encode('utf-8'))

        if "CFBundleShortVersionString" in plist:
            version = str(plist["CFBundleShortVersionString"])

        localization = {}
        try:
            _loc = plist.get('localization',None)
            if _loc == None:
                _loc = plist.get('localizations',None)

            if _loc != None:
                if "English" in _loc:
                    localization = _loc["English"]
                elif "en" in _loc:
                    localization = _loc["en"]
                else:
                    localization = None

                if localization != None:
                    if 'title' in localization:
                        title = localization['title']
                    if 'description' in localization:
                        descASCII = localization['description'].encode('ascii', 'ignore').decode('ascii')
                        description = base64.b64encode(descASCII)
                        #description = base64.b64encode(str(localization['description']).encode('utf-8'))

        except Exception as e:
            logger.error("Error: %s" % e)
            logger.error("Offending URL: %s" % metaURL)

    metaData = {}
    metaData['title'] = title
    metaData['version'] = version
    metaData['description'] = description

    return metaData

def readDistributionFile(distURL):

    distData = {}
    distData['name'] = ''
    distData['suname'] = ''
    distData['restart'] = 'NoRestart'
    distData['version'] = None
    distData['title'] = ''
    distData['description'] = ''

    r = requests.get(distURL)
    if r.status_code == requests.codes.ok:

        root = ET.fromstring(r.text.encode('utf-8'))
        c = root.findall("./choice[@suDisabledGroupID]")

        if len(c) == 1:
            for x in c:
                distData['name'] = x.get('suDisabledGroupID','')
                distData['title'] = x.get('title','')
                distData['version'] = x.get('versStr','')
                if len(x) >= 1:
                    distData['restart'] = x[0].get('onConclusion','NoRestart')
                    distData['suname'] = distData['name'] + "-" + distData['version']

        _strings = root.findtext("./localization/strings")

        # Get Title
        if distData['title'] == '' or distData['title'] == 'SU_TITLE':
            _su_title = re.findall(r'(?<="SU_TITLE" =).?"(.*)(?=\"|\';)', _strings)
            if len(_su_title) >= 1:
                distData['title'] = _su_title[0]

        # Get Version
        if distData['version'] == '' or distData['version'] == None or distData['version'] == 'SU_VERS':
            _su_vers = re.findall(r'(?<="SU_VERS" =).?"(.*)(?=\"|\';)', _strings)
            if len(_su_vers) >= 1:
                distData['version'] = _su_vers[0]

        # Get Description
        if distData['description'] == None or distData['description'] == '':
            _desc = re.findall(r'(?<="SU_DESCRIPTION" =).?\'(.*)(?<=</html>)', _strings, re.DOTALL | re.MULTILINE)
            if len(_desc) >= 1:
                descASCII = _desc[0].encode('ascii', 'ignore').decode('ascii')
                distData['description'] = base64.b64encode(descASCII.encode('utf-8'))

        # Some of apples patches now have a space where the version number
        # would go, patch wont install without the space
        if distData['version'] == None or distData['version'] == '' or distData['version'] == ' ':
            distData['suname'] = distData['name'] + "- "
        else:
            distData['suname'] = distData['name'] + "-" + distData['version']

    else:
        print("Error reading distribution file ({}).".format(distURL))

    return distData

def postDataToWebService(patches, config):

    httpPrefix = "http"
    if config['MPServerUseSSL'] == True:
        httpPrefix = "https"

    dt      = datetime.datetime.now()
    dts     = "%s%s%s%s%s" % (dt.year, dt.month, dt.day, dt.hour, dt.minute)
    apiKey  = createWSApiKeyHash(wsPostKey,dts)
    _url    = httpPrefix + "://" + str(config['MPServerAddress']) + ":" + str(config['MPServerPort']) + wsPostAPIURI
    logger.debug("Post URL: "+ _url)

    payload = {'type': 'json' , 'data': simplejson.dumps(patches)}
    headers = {'X-API-Key': apiKey, 'MPVersion-API': wsPostVersion, 'X-API-TS': dts, 'X-AGENT-ID': 'MacPatch', 'X-AGENT-VER': '99'}

    try:
        request = requests.post(_url, data=payload, verify=False, headers=headers)
        print(request.status_code)
        #if request.status_code == requests.codes.ok:
        if request.status_code in [200, 201, 202]:
            logger.info("Data post was successful.")
            logger.info(request.text)
        else:
            logger.error("Data post was not successful.")
            logger.error(request.text)

    except requests.exceptions.RequestException as e:
        logger.error(e)

def readSUSCatalogFile(sucatalog, filterList=[], asFile=False):

    if asFile:
        prefs = plistlib.readPlist(sucatalog)
    else:
        r = requests.get(sucatalog)
        if r.status_code == requests.codes.ok:
            #prefs = plistlib.readPlistFromString(r.text.encode('utf-8'))
            prefs = plistlib.loads(r.text.encode('utf-8'))

    if not prefs:
        return None

    productKeys = list(prefs['Products'].keys())
    patches = []

    logger.info("Found " + str(len(productKeys)) + " to process." )

    for key in productKeys:

        logger.info("Processing key " + key )

        patch = {}
        patch['akey'] = key
        if "PostDate" in prefs['Products'][key]:
            patch['postdate'] = returnDateTimeAsString(prefs['Products'][key]['PostDate'])
        else:
            patch['postdate'] = '1984-01-01 00:00:00'
        if len(prefs['Products'][key]['Packages']) > 0 and "Size" in prefs['Products'][key]['Packages'][0]:
            patch['size'] = str(prefs['Products'][key]['Packages'][0]['Size'])
        else:
            patch['size'] = '0'

        patch['title'] = 'NA'
        patch['description'] = base64.b64encode('NA'.encode('utf-8'))
        patch['name'] = ''
        patch['suname'] = 'NA'
        patch['restart'] = ''
        patch['version'] = '1.0.0'

        if "ServerMetadataURL" in prefs['Products'][key]:
            patch['ServerMetadataURL'] = prefs['Products'][key]["ServerMetadataURL"]
        else:
            patch['ServerMetadataURL'] = ""

        if "Distributions" in prefs['Products'][key]:
            if "en" in prefs['Products'][key]["Distributions"]:
                patch['Distribution'] = prefs['Products'][key]["Distributions"]['en']
            elif "English" in prefs['Products'][key]["Distributions"]:
                patch['Distribution'] = prefs['Products'][key]["Distributions"]['English']
            else:
                patch['Distribution'] = ""
        else:
            patch['Distribution'] = ""

        if len(patch['Distribution']) >= 1:
            df = readDistributionFile(patch['Distribution'])
            patch.update(df.copy())

        # Deprecated
        #if len(patch['ServerMetadataURL']) >= 1:
        #   md = readServerMetadata(patch['ServerMetadataURL'])
        #   patch.update(md.copy())

        # Make sure we dont have an empty patch name
        if len(patch['name']) <= 2:
            patch['name'] = patch['akey']
            if patch['version'] is None:
                patch['version'] = ''
            patch['suname'] = patch['akey']+'-'+patch['version']

        # If we end up with a empty title check to see if we got one from the dist file
        if patch['title'] == 'NA':
            if patch['titleAlt'] != 'NA':
                patch['title'] = patch['titleAlt']


        patch.pop("titleAlt", None)
        patch.pop("ServerMetadataURL", None)
        patch.pop("Distribution", None)

        #print patch
        containsFilterItem = False
        if len(filterList) >= 1:
            for f in filterList:
                if fnmatch.fnmatch(patch['title'], f):
                    containsFilterItem = True
                    break

        if patch['akey'] in patch['suname']:
            containsFilterItem = True

        if containsFilterItem == False:
            logger.info("Adding patch: " + str(patch['suname']))
            print(("Adding patch: " + str(patch['suname'])))
            patches.append(patch)
        else:
            logger.info("Excluding patch: " + str(patch['suname']))

    return patches

def main():
    '''Main command processing'''
    parser = argparse.ArgumentParser(description='Process some args.')
    parser.add_argument('--config', help="MacPatch SUS Config file", required=False, default=loaderConf)
    parser.add_argument('--debug', help='Set log level to debug', action='store_true')
    parser.add_argument('--data', help="JSON results file", required=False)
    parser.add_argument('--save', help='Saves patches as JSON file', action='store_true')
    parser.add_argument('--noPost', help='Does not post patches to server', action='store_true')
    args = parser.parse_args()

    # Setup Logging
    try:
        hdlr = logging.FileHandler(logFile)
        formatter = logging.Formatter('%(asctime)s %(levelname)s --- %(message)s')
        hdlr.setFormatter(formatter)
        logger.addHandler(hdlr)

        if args.debug:
            logger.setLevel(logging.DEBUG)
        else:
            logger.setLevel(logging.INFO)

    except Exception as e:
        print("%s" % e)
        sys.exit(1)

    # Read and Parse Config
    config_data = None
    settings = None
    if args.config:
        if not os.path.exists(args.config):
            print("Unable to open " + args.config +". File not found.")
            sys.exit(1)

        json_data_fh = open(args.config).read()
        config_data = json.loads(json_data_fh)
        if "settings" in config_data:
            settings = config_data['settings']
        else:
            print("Structure of config files is not correct.")
            sys.exit(1)


    logger.info('# ------------------------------------------------------')
    logger.info('# Starting SUS patch sync'                               )
    logger.info('# ------------------------------------------------------')

    if args.data != None:
        if os.path.exists(args.data):
            file = open(args.data, 'r')
            patches = json.loads(file.read())
        else:
            print("Unable to open " + args.data +". File not found.")
            sys.exit(1)
    else:
        # Build the Catalogs Array to get the Patches from
        catalogs = []
        if 'Catalogs' in settings:
            if 'ASUSServerPort' in settings:
                _port = settings['ASUSServerPort']
            else:
                _port = 80

            for cat in settings['Catalogs']:
                if 'enabled' in cat:
                    if cat['enabled'] == True:
                        if _port != 80:
                            catStr = "http://"+settings['ASUSServer']+":"+settings['ASUSServerPort']+cat['catalogurl']
                        else:
                            catStr = "http://"+settings['ASUSServer']+cat['catalogurl']

                        catalogs.append(catStr)

        else:
            logger.error('Cant find Catalogs key.')
            sys.exit(0)

        # Read each catalog and parse each patch
        _patches = []
        patchesRaw = []
        for catalog in catalogs:
            logger.info("Parsing catalog %s" % os.path.basename(catalog))
            if 'filter' in settings:
                _patches = readSUSCatalogFile(catalog,settings['filter'])
            else:
                _patches = readSUSCatalogFile(catalog)

            patchesRaw.extend(_patches)

        # Remove any duplicate keys from the array before posting
        logger.info("Total patches found %d, begin removing duplicates." % len(patchesRaw))
        patches = list({v['akey']:v for v in patchesRaw}.values())
        logger.info("Total patches %d to post to web service." % len(patches))


    if args.noPost:
        logger.info("Posting patches to web service is disabled")
        print("Posting patches to web service is disabled, using the --noPost arg.")
    else:
        logger.info("Posting patches to web service")
        postDataToWebService(patches,settings)

    if args.save:
        file = open("/tmp/SUSPatches.json", "w")
        file.write(json.dumps(patches))
        file.close()

if __name__ == '__main__':
    main()