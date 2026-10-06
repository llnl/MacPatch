# ![MPLogo](./images/MPLogo_3_64x64.png) MacPatch 4.x

## Acknowledgements

MacPatch uses a number of open source components. Without all of the hard work of the authors of these great projects MacPatch wouldn't be a reality. Thank You!

MacPatch 4.x makes use of the following open source components:

### Server

|Project|License|URL|
|---|---|---|
| Python 3 | [Python Software Foundation License](https://docs.python.org/3/license.html) | [https://www.python.org]() |
| NGINX | [2-clause BSD](https://nginx.org/LICENSE) | [https://nginx.org]() |
| MySQL | [GPL-2.0](https://www.mysql.com/about/legal/licensing/oem/) | [https://www.mysql.com]() |
| Redis | [BSD-3-Clause (Redis 6)](https://redis.io/legal/licenses/) | [https://redis.io]() |
| OpenSSL | [Apache-2.0](https://www.openssl.org/source/license.html) | [https://www.openssl.org]() |
| PCRE | [BSD](https://www.pcre.org/licence.txt) | [https://www.pcre.org]() |
| SWIG | [GPL](http://www.swig.org/Release/LICENSE) | [http://www.swig.org]() |
| Yarn | [BSD-2-Clause](https://github.com/yarnpkg/yarn/blob/master/LICENSE) | [https://yarnpkg.com]() |
| Node.js | [MIT](https://github.com/nodejs/node/blob/main/LICENSE) | [https://nodejs.org]() |

PCRE, OpenSSL, SWIG, Yarn and Node.js are used to build and install the server.

### macOS Client

|Project|License|URL|
|---|---|---|
| FMDB | [MIT](https://github.com/ccgus/fmdb/blob/master/LICENSE.txt) | [https://github.com/ccgus/fmdb]() |
| STHTTPRequest | [BSD](https://github.com/nst/STHTTPRequest/blob/master/LICENSE) | [https://github.com/nst/STHTTPRequest]() |
| CocoaSecurity | [MIT](https://github.com/kelp404/CocoaSecurity/blob/master/LICENSE) | [https://github.com/kelp404/CocoaSecurity]() |
| UAObfuscatedString | [BSD](https://github.com/UrbanApps/UAObfuscatedString) | [https://github.com/UrbanApps/UAObfuscatedString]() |
| RegexKit Lite | [BSD](http://regexkit.sourceforge.net/Documentation/RegexKitProgrammingGuide.html#LicenseInformation) | [http://regexkit.sourceforge.net]() |
| NSData+Base64 | As-Is | [https://www.cocoawithlove.com/2009/06/base64-encoding-options-on-mac-and.html]() |
| MBProgressHUD | [MIT](https://github.com/jdg/MBProgressHUD/blob/master/LICENSE) | [https://github.com/jdg/MBProgressHUD]() |
| RHPreferences | [BSD](https://github.com/heardrwt/RHPreferences/blob/master/LICENSE) | [https://github.com/heardrwt/RHPreferences]() |
| MPOProgressBar | See source header | |

### Admin Console

JavaScript libraries installed with Yarn (`package.json`), replacing the Bower packages used by 3.x.

Each library remains under its own license, see the project sites.

| Library | Version |
|---|---|
| ace-editor-builds | ^1.2.4 |
| bootstrap | 3.4.1 |
| bootstrap-chosen | ^1.4.2 |
| bootstrap-editable | ^1.0.1 |
| bootstrap-table | ^1.22.6 |
| brace | ^0.11.1 |
| chart.js | ^2.9.4 |
| chosen-js | ^1.8.7 |
| dompurify | ^3.4.0 |
| font-awesome | ^4.7.0 |
| interactjs | ^1.10.27 |
| jquery | ^3.7.1 |
| jQuery-QueryBuilder | ^3.0.0 |
| jquery-resizable-columns | ^0.2.3 |
| jquery-steps-tc | ^1.1.0 |
| metismenu | 3.0.7 |
| modernizr | ^3.13.0 |
| moment | ^2.30.1 |
| morris.js | ^0.5.0 |
| popper.js | ^1.16.1 |
| raphael | ^2.3.0 |
| sb-admin-2 | ^3.3.8 |
| selectize | ^0.12.6 |
| sql-parser-mistic | ^1.2.3 |
| tableexport.jquery.plugin | ^1.30.0 |

### Python Modules

Installed with pip. The version listed is the one pinned for each component, a dash means the component does not use the module. Versions can differ between components because each has its own requirements file in `Source/Server/apps`.

| Module | API | Console | Server Tools |
|---|---|---|---|
| boto3 | 1.43.107 | 1.42.73 | - |
| cryptography | 50.0.2 | 46.0.5 | - |
| distro | 1.9.0 | 1.9.0 | 1.9.0 |
| email-validator | 2.3.0 | 2.3.0 | - |
| Flask | 3.1.3 | 3.1.3 | - |
| Flask-APScheduler | - | unpinned | - |
| Flask-Caching | 2.5.1 | 2.3.1 | - |
| Flask-Cors | - | 6.0.2 | - |
| Flask-Login | 0.6.3 | 0.6.3 | - |
| Flask-Mail | 0.10.0 | 0.10.0 | - |
| Flask-Migrate | 4.1.0 | 4.1.0 | - |
| Flask-RESTful | 0.3.10 | 0.3.10 | - |
| Flask-Session | - | 0.8.0 | - |
| Flask-SQLAlchemy | 3.1.1 | 3.1.1 | - |
| Flask-WTF | - | 1.2.2 | - |
| gevent | 26.9.0 | 25.9.1 | - |
| gunicorn | 26.2.0 | 25.1.0 | - |
| humanize | - | 4.15.0 | - |
| ldap3 | 2.9.1 | 2.9.1 | - |
| M2Crypto | - | - | 0.47.0 |
| msal | - | 1.35.1 | - |
| packaging | 24.2 | - | 26.0 |
| psutil | - | - | 7.2.2 |
| pycryptodome | - | - | 3.23.0 |
| PyJWT | 2.15.1 | - | - |
| pymysql | 1.2.3 | 1.1.2 | 1.1.2 |
| python-crontab | - | - | 3.3.0 |
| python-dateutil | - | 2.9.0.post0 | - |
| python-dotenv | 1.2.4 | 1.2.2 | 1.2.2 |
| redis | - | 7.3.0 | - |
| requests | 2.32.3 | 2.32.5 | 2.33.1 |
| simplejson | - | - | 3.20.2 |
| SQLAlchemy | 2.1.1 | 2.0.48 | - |
| urllib3 | - | 2.6.3 | - |
| Werkzeug | 3.1.9 | 3.1.6 | - |
| yattag | - | 1.16.1 | - |
