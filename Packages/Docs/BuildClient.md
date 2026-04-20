# Build MacPatch Agent PKG's

The MacPatch Agent packages require some assembly. Much of it can be automated using scripts.

## Structure (File System)

```
MacPatch PKG
    - Base
        - PKG_Resources (Package Resources, scripts etc.)
        - PKG_SRC (Package Root)

    - Updater
        - PKG_Resources (Package Resources, scripts etc.)
        - PKG_SRC (Package Root)

    - Combined
        - MPClientInstaller.mpkg (Pre-Built mpkg)
        - MPClientInstaller.pmproj (PKG Project)
```

## Files To Add

### Build "Base"

Any file that is prefixed with a "+" needs to be added to build the MacPatch Client.

```
- PKG_Resources
    + ccusr
    + MPPrefMigrate

- PKG_SRC
    - Library
        - MacPatch
            - Client
                + MPAgent
                + MPAgentExec
                + MPClientStatus.app
                + MPWorker
                + MPLogout.app
                + MPReboot.app
                + MPTask Editor.app
                + Self Patch.app
                + MPRebootD
```

### Build "Updater"

Any file that is prefixed with a "+" needs to be added to build the MacPatch Client Updater.

```
- PKG_SRC
    - Library
        - MacPatch
            - Updater
                + MPAgentUp2Date
```

## Create Packages

Building the packages is quiet simple. In fact it's more simple to build them via the "Command Line" then using the PackageMaker GUI application. Here are two examples of building the MacPatch Base and Update package via the command line.

### Build the Client Base Package

Simply replace or set **`${BUILDDIR}`** variable with the path to the "MacPatch PKG" directory.

*Update the Info.plist*

```bash
defaults write  "${BUILDDIR}/Base/PKG/Info" CFBundleGetInfoString "${pkgMPBaseVerFull}"
defaults write  "${BUILDDIR}/Base/PKG/Info" CFBundleShortVersionString "${pkgVer}"
defaults write  "${BUILDDIR}/Base/PKG/Info" IFMajorVersion "${pkgMPBaseVerMajor}"
defaults write  "${BUILDDIR}/Base/PKG/Info" IFMinorVersion "${pkgMPBaseVerMinor}"
```

*Build the PKG*

```bash
PackageMaker.app/Contents/MacOS/PackageMaker -r "${BUILDDIR}/Base/PKG_SRC" \
-o "${BUILDDIR}/Base/PKG/MPBaseClient.pkg" \
-s "${BUILDDIR}/Base/PKG_Scripts" \
-f "${BUILDDIR}/Base/PKG/Info.plist" \
--no-relocate --root-volume-only \
--title "MacPatch Base Client" --id "gov.llnl.mp.agent" --no-recommend
```

### Build the Client Updater Package

Simply replace or set **`${BUILDDIR}`** variable with the path to the "MacPatch PKG" directory.

*Update the Info.plist*

```bash
defaults write  "${BUILDDIR}/Updater/PKG/Info" CFBundleGetInfoString "${pkgMPBaseVerFull}"
defaults write  "${BUILDDIR}/Updater/PKG/Info" CFBundleShortVersionString "${pkgVer}"
defaults write  "${BUILDDIR}/Updater/PKG/Info" IFMajorVersion "${pkgMPBaseVerMajor}"
defaults write  "${BUILDDIR}/Updater/PKG/Info" IFMinorVersion "${pkgMPBaseVerMinor}"
```

*Build the PKG*

```bash
PackageMaker.app/Contents/MacOS/PackageMaker -r "${BUILDDIR}/Updater/PKG_SRC" \
-o "${BUILDDIR}/Updater/PKG/MPUpdateClient.pkg" \
-s "${BUILDDIR}/Updater/PKG_Scripts" \
-f "${BUILDDIR}/Updater/PKG/Info.plist" \
--no-relocate --root-volume-only \
--title "MacPatch Updater" --id "gov.llnl.mp.updater" --no-recommend
```

### Copy Packages To MPKG

```bash
cp -R -p "${BUILDDIR}/Base/PKG/MPBaseClient.pkg" "${BUILDDIR}/Combined/MPClientInstaller.mpkg/Contents/Packages/MPBaseClient.pkg"
cp -R -p "${BUILDDIR}/Updater/PKG/MPUpdateClient.pkg" "${BUILDDIR}/Combined/MPClientInstaller.mpkg/Contents/Packages/MPUpdateClient.pkg"
```

### Updater MPKG Version Info (MUST BE DONE)

Edit ***mpInfo.ini***

NOTE: the "mpInfo.ini" file is used to process the packages when uploading the agent via the web admin console. Clients will be updated based on "**version,agent_version,build**" properties.

```ini
--------------------------------------------------

[agent]
version="2.1.1"
agent_version="2.1.1"
build="1"
framework="1.0.0"
osver="*"
pkg=/Contents/Packages/MPBaseClient.pkg

[updater]
version="2.1.1"
agent_version="2.1.1"
build="1"
framework="1.0.0"
osver="*"
pkg=/Contents/Packages/MPUpdateClient.pkg

--------------------------------------------------
```

```bash
cp "${BASEDIR}/PKG/Combined/mpInfo.ini" > "${BUILDDIR}/Combined/MPClientInstaller.mpkg/Contents/Resources/.mpInfo.ini"
```

### Create ZIP file for uploading agent

```bash
ditto -c -k --keepParent "${BUILDDIR}/Combined/MPClientInstaller.mpkg" "${BUILDDIR}/Combined/MPClientInstaller.mpkg.zip"
```
