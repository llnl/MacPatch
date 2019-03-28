//
//  ViewController.swift
//  MPAgentUploder
//
//  Created by Charles Heizer on 12/7/16.
//
/*
 Copyright (c) 2016, Lawrence Livermore National Security, LLC.
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
 */

import Cocoa
import Alamofire
import LogKit


class ViewController: NSViewController, AuthViewControllerDelegate
{
    @IBOutlet weak var mpServerPort: NSTextField!
    @IBOutlet weak var mpServerHost: NSTextField!
    @IBOutlet weak var useSSL: NSButton!
    
    @IBOutlet weak var agentPackage: NSTextField!
    @IBOutlet weak var signingIdentity: NSTextField!
    @IBOutlet weak var signPackageButton: NSButton!
    
    @IBOutlet weak var pluginsPath: NSTextField!
	@IBOutlet weak var profilesPath: NSTextField!
    @IBOutlet weak var registrationKey: NSTextField!
    
    @IBOutlet weak var agentConfigStatus: NSTextField!
    @IBOutlet weak var extractStatus: NSTextField!
    @IBOutlet weak var writeConfigStatus: NSTextField!
    @IBOutlet weak var flattenPackageStatus: NSTextField!
    @IBOutlet weak var compressPackageStatus: NSTextField!
    @IBOutlet weak var postPackageStatus: NSTextField!
    
    @IBOutlet weak var agentConfigImage: NSImageView!
    @IBOutlet weak var extractAgentImage: NSImageView!
    @IBOutlet weak var writeConfigImage: NSImageView!
    @IBOutlet weak var flattenPackageImage: NSImageView!
    @IBOutlet weak var compressPackageImage: NSImageView!
    @IBOutlet weak var postPackageImage: NSImageView!
    
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var uploadButton: NSButton!
    
    @IBOutlet weak var headerView: NSView!
    @IBOutlet weak var headerViewVersionLabel: NSTextField!
    
    let defaults = UserDefaults.standard
    let fm = FileManager.default
    
    var api_token: String = "NA"
    var pkg_tmp_dir: String = ""
    var agent_dictionary: [String: Any] = [:]
    var updater_dictionary: [String: Any] = [:]
    var migration_plist: String = ""
	
	var plugins_list: [String: Any] = [:]
	var profiles_list: [String: Any] = [:]
    
    
    override func viewDidLoad()
	{
        super.viewDidLoad()
        self.uploadButton.isEnabled = false

        NotificationCenter.default.addObserver(self, selector: #selector(self.toggleLoggingLevel(notification:)), name: Notification.Name("LogLevel"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.toggleAgentUpload(notification:)), name: Notification.Name("AgentUpload"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.setLogLevel(notification:)), name: Notification.Name("setLogLevel"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.toggleSelfSigned(notification:)), name: Notification.Name("SelfSigned"), object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(self.resetAuthToken(notification:)), name: Notification.Name("ResetAuthToken"), object: nil)
        
        self.headerView.wantsLayer = true
        headerViewVersionLabel.stringValue = "Version " + (Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)
        self.mpServerHost.placeholderString = "MacPatch Server"
        self.resetUI()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    lazy var authViewController: AuthViewController = {
        return self.storyboard!.instantiateController(withIdentifier: "AuthViewController")
            as! AuthViewController
    }()
    
    @IBAction func displayAuthSheet(sender: AnyObject)
    {
        authViewController.delegate = self
        authViewController.x_mpServer = self.mpServerHost.stringValue
        authViewController.x_mpPort = self.mpServerPort.stringValue
        authViewController.x_useSSL = self.useSSL.state.rawValue
        self.presentAsSheet(authViewController)
    }
    
    func displayMigrationPlistSheet()
    {
        let openPanel = NSOpenPanel()
        openPanel.message = "Please select the migration plist file."
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["plist"]
        
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSFileHandlingPanelOKButton {
                self.migration_plist = (openPanel.url?.path)!
                self.writeConfigStatus.stringValue = "Migration plist will be added."
				log.info("choosePlist: \(String(describing: openPanel.url?.path))")
            }
        }
    }
    
    
    func didFinishAuthRequest(sender: AuthViewController, token:String)
    {
        // do stuff like updating the UI
        self.api_token = token
        self.processAndUploadAgent(sender: self)
    }
    
    @IBAction func choosePackage(sender: AnyObject)
    {
        let openPanel = NSOpenPanel()
        openPanel.message = "Please select the MacPatch Client Installer zip file."
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["zip"]
        
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSFileHandlingPanelOKButton {
                self.agentPackage.stringValue = (openPanel.url?.path)!
                self.uploadButton.isEnabled = true
				log.info("choosePackage: \(String(describing: openPanel.url?.path))")
				self.defaults.set(self.agentPackage.stringValue, forKey: "package")
				self.defaults.synchronize()
            }
        }
    }
    
    @IBAction func choosePluginFolder(sender: AnyObject)
    {
        let openPanel = NSOpenPanel()
        openPanel.message = "Please select the MacPatch Client plugins directory."
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = false
        
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSFileHandlingPanelOKButton {
                self.pluginsPath.stringValue = (openPanel.url?.path)!
				self.defaults.set(self.pluginsPath.stringValue, forKey: "pluginsFolder")
				self.defaults.synchronize()
            }
        }
		
    }
	
	@IBAction func chooseProfilesFolder(sender: AnyObject)
	{
		let openPanel = NSOpenPanel()
		openPanel.message = "Please select the MacPatch Client OS Configuration profiles directory."
		openPanel.allowsMultipleSelection = false
		openPanel.canChooseDirectories = true
		openPanel.canCreateDirectories = false
		openPanel.canChooseFiles = false
		
		openPanel.begin { (result) -> Void in
			if result.rawValue == NSFileHandlingPanelOKButton {
				self.profilesPath.stringValue = (openPanel.url?.path)!
				self.defaults.set(self.profilesPath.stringValue, forKey: "profiles")
				self.defaults.synchronize()
			}
		}
	}
	
	
	@objc func resetAuthToken(notification: NSNotification)
	{
		let a = NSAlert()
		a.messageText = "Reset Authentication?"
		a.informativeText = "Are you sure you would like to reset your authentication data.?"
		a.addButton(withTitle: "Reset")
		a.addButton(withTitle: "Cancel")
		a.alertStyle = NSAlert.Style.warning
		
		a.beginSheetModal(for: self.view.window!, completionHandler: { (modalResponse) -> Void in
			if modalResponse == NSApplication.ModalResponse.alertFirstButtonReturn {
				self.api_token = "NA"
			}
		})
	}
    
    @IBAction func processAndUploadAgent(sender: AnyObject)
    {
        // Check to see if we need to enable Self-Signed Certs
        if defaults.bool(forKey: "selfSigned") {
            MPAlamofire={ ()->Alamofire.SessionManager in
                let policies:[String:ServerTrustPolicy]=[self.mpServerHost.stringValue: .disableEvaluation]
                let manager=Alamofire.SessionManager(serverTrustPolicyManager:ServerTrustPolicyManager(policies:policies))
                return manager
            }()
        }
		
		if (UserDefaults.standard.string(forKey: "server") != self.mpServerHost.stringValue) {
			self.displayAuthSheet(sender: self)
			return
		}
        
        // Check for api_token, if no token then display auth dialog
        if (self.api_token.isEmpty || self.api_token == "NA") {
            self.displayAuthSheet(sender: self)
            return
        }
        
        // Check is api_token is valid, if no then display auth dialog
        if (!isTokenValid(token: self.api_token)) {
            self.displayAuthSheet(sender: self)
            return
        }

        self.processAgentPackage()
    }
    
// MARK: - Methods
    func processAgentPackage()
    {
		var _signButton: NSButton!
		var _signIdent: NSTextField!
		
		DispatchQueue.main.async {
			_signButton = self.signPackageButton
			_signIdent = self.signingIdentity
		}
		
        DispatchQueue.global(qos: .background).async
        {
            log.info("****************************************************************")
            log.info("Begin Processing Agent Packages")
            // If Signing is turned on check for signature value
	
			if (_signButton?.state == .on)
			{
				if ((_signIdent?.stringValue.count)! <= 0)
				{
					log.error("Property signingIdentity is selected but value is not set.")
					DispatchQueue.main.async {
						_ = self.alertWithOK(title: "Missing Identity", infoText: "You have choosen to sign the packages but did not enter an identity name. Please enter an identity name and try again.")
					}
					return;
				}
			}
            
            // UI Changes
            self.resetUI()
            self.toggleUIBegin()
            
            // ---------------------------------
            // Download Agent Configuration Data
            // ---------------------------------
            log.info("Download Agent Configuration Data")
			DispatchQueue.main.async {
				self.agentConfigImage.image = NSImage.init(named: NSImage.removeTemplateName)
			}
			
            let res = self.getAgentConfigurationData(token: self.api_token)
            if (res == nil || (res?.isEmpty)!) {
                log.error("Error getting agent configuration.")
                DispatchQueue.main.async {
                    self.agentConfigImage.image = NSImage.init(named: "RedDot")
                    self.agentConfigStatus.stringValue = "Error getting agent configuration."
                    self.toggleUIEnd()
                }
                return;
            } else {
                DispatchQueue.main.async {
                    self.agentConfigImage.image = NSImage.init(named: "GreenDot")
                }
            }
            let agent_config = res?["plist"] as? String
            
            // ---------------------------------
            // Unzip and extract packages
            // ---------------------------------
            log.info("Unzip and extract package")
            self.extractAgentImage.image = NSImage.init(named: NSImage.removeTemplateName)
            if (self.extractAgentPKG(package: self.agentPackage.stringValue)) {
                DispatchQueue.main.async {
                    self.extractAgentImage.image = NSImage.init(named: "GreenDot")
                }
            } else {
                log.error("Error unarchiving and extracting package.")
                DispatchQueue.main.async {
                    self.extractAgentImage.image = NSImage.init(named: "RedDot")
                    self.extractStatus.stringValue = "Error unarchiving and extracting package."
                    self.toggleUIEnd()
                }
                return
            }
            
            // ---------------------------------
            // Write config to packages
            // ---------------------------------
            log.info("Write config data to packages.")
            self.writeConfigImage.image = NSImage.init(named: NSImage.removeTemplateName)
            
            // Get an array of packages
            let base_dir = self.pkg_tmp_dir.stringByAppendingPathComponent(path: "MacPatch")
            log.debug("Working directory is \(base_dir)")

            var packages: [String] = self.getPackagesFromArchiveDir(path: base_dir)!
            if (packages.isEmpty) {
                log.error("Error no packages in archive.")
                DispatchQueue.main.async {
                    self.writeConfigImage.image = NSImage.init(named: "RedDot")
                    self.writeConfigStatus.stringValue = "Error no pkgs in archive"
                }
            }
            
            // Write Server Public Key to Base.pkg
            log.info("Write Server Public Key to Base.pkg")
            if (!self.writeServerPubKeyToPackage(packages: packages, pubKey: res?["pubKey"] as! String, keyHash: res?["pubKeyHash"] as! String))
			{
                log.error("Error writing server keys.")
                DispatchQueue.main.async {
                    self.writeConfigImage.image = NSImage.init(named: "RedDot")
                    self.writeConfigStatus.stringValue = "Error writing server keys."
                    self.toggleUIEnd()
                }
                return
            }
            // Write config plist to packages
            log.info("Write config plist to packages")
			if (!self.writePlistToPackage(packages: packages, plist: agent_config!))
			{
                log.error("Error writing config plist to package.")
                DispatchQueue.main.async {
                    self.writeConfigImage.image = NSImage.init(named: "RedDot")
                    self.writeConfigStatus.stringValue = "Error writing config plist to package."
                    self.toggleUIEnd()
                }
                return
            }
            
            // Write plugins to packages
            log.info("Write plugins to packages")
            if (!self.pluginsPath.stringValue.isEmpty) {
                if (!self.writePluginsToPackage(packages: packages, plugins_directory: self.pluginsPath.stringValue)) {
                    log.error("Error writing plugins to package.")
                    DispatchQueue.main.async {
                        self.writeConfigImage.image = NSImage.init(named: "RedDot")
                        self.writeConfigStatus.stringValue = "Error writing plugins to package."
                        self.toggleUIEnd()
                    }
                    return
                }
            }
			
			// Write profiles to packages
			log.info("Write profiles to packages")
			if (!self.profilesPath.stringValue.isEmpty) {
				if (!self.writeProfilesToPackage(packages: packages, profiles_directory: self.profilesPath.stringValue)) {
					log.error("Error writing profiles to package.")
					DispatchQueue.main.async {
						self.writeConfigImage.image = NSImage.init(named: "RedDot")
						self.writeConfigStatus.stringValue = "Error writing plugins to package."
						self.toggleUIEnd()
					}
					return
				}
			}
            
            // Write Version info to packages
            log.info("Write Version info to packages")
            let ver_info = base_dir.stringByAppendingPathComponent(path: "Resources/mpInfo.plist")
            for pkg in packages {
                if (!self.writeVersionInfoToPackage(package: pkg, version_file: ver_info)) {
                    log.error("Error writing version info to packages.")
                    DispatchQueue.main.async {
                        self.writeConfigImage.image = NSImage.init(named: "RedDot")
                        self.writeConfigStatus.stringValue = "Error writing version info to packages."
                        self.toggleUIEnd()
                    }
                    return
                }
            }
            
            // Write Reg Key to Base.pkg
            log.info("Write registration key to packages")
            if (!self.registrationKey.stringValue.isEmpty) {
                if (!self.writeRegKeyToPackage(packages: packages, regKey: self.registrationKey.stringValue)) {
                    log.error("Error writing registration key to packages.")
                    DispatchQueue.main.async {
                        self.writeConfigImage.image = NSImage.init(named: "RedDot")
                        self.writeConfigStatus.stringValue = "Error writing registration key to packages."
                        self.toggleUIEnd()
                    }
                    return
                }
            }
            
            // Change Background image
            log.info("Apply Background image.")
            if (!self.changeBackgroundImageToDoneImage(path: base_dir)) {
                log.error("Error changing background image.")
                DispatchQueue.main.async {
                    self.writeConfigStatus.stringValue = "Error changing background image."
                }
            }
            
            DispatchQueue.main.async {
                self.writeConfigImage.image = NSImage.init(named: "GreenDot")
            }
            
            // ---------------------------------
            // Flatten Packages
            // ---------------------------------
            log.info("Flatten Packages")
            self.flattenPackageImage.image = NSImage.init(named: NSImage.removeTemplateName)
            
            var flattend_packages: [String] = []
            packages.append(base_dir) // Add the Combined Package to flatten
            flattend_packages = self.flattenPackages(packages: packages, working_dir: self.pkg_tmp_dir)
            if (flattend_packages.count <= 0) {
                log.error("Error flattening packages.")
                DispatchQueue.main.async {
                    self.flattenPackageImage.image = NSImage.init(named: "RedDot")
                    self.flattenPackageStatus.stringValue = "Error flattening packages."
                    self.toggleUIEnd()
                }
                return
            } else {
                DispatchQueue.main.async {
                    self.flattenPackageImage.image = NSImage.init(named: "GreenDot")
                }
            }
            
            // ---------------------------------
            // Compress Packages
            // ---------------------------------
            log.info("Compress Packages")
            self.compressPackageImage.image = NSImage.init(named: NSImage.removeTemplateName)
            for fpkg in flattend_packages {
                
                var xFpkg = fpkg
                
                // If Signing is turned on we need to remove the toSign_
                if (self.signPackageButton.state == .on) {
                    xFpkg = fpkg.replacingOccurrences(of: "toSign_", with: "")
                }
                
                if (!self.compressPackage(package: xFpkg)){
                    log.error("Error archiving package.")
                    DispatchQueue.main.async {
                        self.compressPackageImage.image = NSImage.init(named: "RedDot")
                        self.compressPackageStatus.stringValue = "Error archiving package."
                        self.toggleUIEnd()
                    }
                    return
                }
            }
            self.compressPackageImage.image = NSImage.init(named: "GreenDot")
            
            // ---------------------------------
            // Post Packages
            // ---------------------------------
            log.info("Post Package")
            if (!self.defaults.bool(forKey: "doNotUpload"))
			{
                var xp:[String] = []
                for fpkg in flattend_packages {
                    xp.append(fpkg.replacingOccurrences(of: "toSign_", with: "").stringByAppendingPathExtension(ext: "zip")!)
                }
				
				// Gather Plugins and Profiles data
				
                
				let fdata: [String: Any] = ["app":self.agent_dictionary,"update":self.updater_dictionary,
											"plugins":self.collectPluginsData(), "profiles":self.collectProfilesData()]
                if(!self.uploadPackagesToServer(packages: xp, formData: fdata)) {
                    log.error("Error posting packages.")
                    DispatchQueue.main.async {
                        self.postPackageImage.image = NSImage.init(named: "RedDot")
                        self.postPackageStatus.stringValue = "Error posting packages."
                        self.toggleUIEnd()
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.postPackageImage.image = NSImage.init(named: "GreenDot")
                }
            } else {
                log.debug("Upload is disabled, opening working dir.")
                NSWorkspace.shared.openFile(base_dir)
            }
            self.toggleUIEnd()
        }
    }

// MARK: - Helper Methods
    
    func toggleUIBegin()
	{
        DispatchQueue.main.async
        {
            self.uploadButton.isEnabled = false
            self.progressBar.isHidden = false
            self.progressBar.isIndeterminate = true
            self.progressBar.startAnimation(nil)
        }
    }
    
    
    func toggleUIEnd()
	{
        DispatchQueue.main.async
        {
            self.uploadButton.isEnabled = true
            self.progressBar.stopAnimation(nil)
            self.progressBar.isHidden = true
        }
    }
    
    func resetUI()
    {
        DispatchQueue.main.async
        {
            self.agentConfigImage.image = NSImage.init(named: "ClearDot")
            self.agentConfigStatus.stringValue = ""
            self.extractAgentImage.image = NSImage.init(named: "ClearDot")
            self.extractStatus.stringValue = ""
            self.writeConfigImage.image = NSImage.init(named: "ClearDot")
            self.writeConfigStatus.stringValue = ""
            self.flattenPackageImage.image = NSImage.init(named: "ClearDot")
            self.flattenPackageStatus.stringValue = ""
            self.compressPackageImage.image = NSImage.init(named: "ClearDot")
            self.compressPackageStatus.stringValue = ""
            self.postPackageImage.image = NSImage.init(named: "ClearDot")
            if (self.defaults.bool(forKey: "doNotUpload")) {
                self.postPackageStatus.stringValue = "Upload is disabled for testing. Will open folder."
            } else {
                self.postPackageStatus.stringValue = ""
            }
			
			// If package is a valid path, enable upload button
			if (self.agentPackage.stringValue.count > 6)
			{
				if (FileManager.default.fileExists(atPath: self.agentPackage.stringValue))
				{
					self.uploadButton.isEnabled = true
				}
				else
				{
					log.error("\(self.agentPackage.stringValue) does not exist. Will not enable upload button")
				}
			}
        }
    }
    
    
    /**
     Create modal alert window with OK button
     
     - parameter title: NSAlert messageText
     - parameter infoText: NSAlert informativeText
     
     - returns: True since only OK button exists
     */
    func alertWithOK(title: String, infoText: String) -> Bool
    {
        let myAlert: NSAlert = NSAlert()
        myAlert.messageText = title
        myAlert.informativeText = infoText
        myAlert.alertStyle = NSAlert.Style.warning
        myAlert.addButton(withTitle: "OK")
        //myAlert(withTitle: "Cancel")
        return myAlert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn
    }
    
    /**
     Query Web API to see if auth token is valid
     
     - parameter token: auth token
     
     - returns: Bool
     */
    func isTokenValid(token: String) -> Bool
    {
        let _ssl = (useSSL.state == .on) ? "https" : "http"
        let _url = "\(_ssl)://\(mpServerHost.stringValue):\(mpServerPort.stringValue)\(URI_PREFIX)/token/valid/\(token)"
        
        let response = MPAlamofire.request(_url).responseJSON()
        switch response.result {
        case .success(let JSON):
            let result = JSON as! NSDictionary
            log.debug("result: \(result)")
            return result["result"] as? Bool ?? false
        case .failure(let error):
            log.error("\(error)")
            return false
        }
    }
    
    /**
     Get Agent Configuration Data from Web API
     
     - parameter token  auth token
     
     - returns: Dictionary of result
     */
    func getAgentConfigurationData(token: String) -> [String:Any]?
    {
        
        let _ssl = (useSSL.state == .on) ? "https" : "http"
        let _url = "\(_ssl)://\(mpServerHost.stringValue):\(mpServerPort.stringValue)/api/v2/agent/config/\(token)"
        
        let response = MPAlamofire.request(_url).validate(statusCode: 200..<300).responseJSON()
        
        switch response.result {
        case .success(let JSON):
            let result = JSON as! NSDictionary
            log.debug("result: \(result)")
            return result["result"] as? [String:Any]
        case .failure(let error):
            log.error("\(error)")
            return nil
        }
    }
    
    /**
     Get Array of PKG's from a path
     
     - parameter path: Directory Path
     
     - returns: Array of Strings
     */
    func getPackagesFromArchiveDir(path: String) -> [String]?
    {
        var dir_files: [String] = []
        let pkgPredicate = NSPredicate(format: "self ENDSWITH '.pkg'")
        let dir_files_pre = try! fm.contentsOfDirectory(atPath: path) as [String]
        let filtered_results = dir_files_pre.filter { pkgPredicate.evaluate(with: $0) }
        if (!filtered_results.isEmpty)
        {
            for x in filtered_results {
                dir_files.append(path.stringByAppendingPathComponent(path: x))
            }
        }
        log.debug(dir_files.joined(separator: ","))
        return dir_files
    }
    
    /**
     Extract Zipped Package and Expand the Package
     
     - parameter package: Zip Package path
     
     - returns: Boolean if succeeds
     */
    func extractAgentPKG(package: String) -> Bool
    {
        self.pkg_tmp_dir = "" // Clear any old variable value
        
        // Delete existing dir if found
        let tmpDir = NSTemporaryDirectory().stringByAppendingPathComponent(path: "mpPKG")
        if (fm.fileExists(atPath: tmpDir)) {
            do {
                try fm.removeItem(atPath: tmpDir)
            } catch let error as NSError {
                log.error(error.debugDescription)
                return false
            }
        }
        
        // Create Temp Dir
        do {
            try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            log.error(error.debugDescription)
            return false
        }
        
        // Assign temp di path to global variable
        self.pkg_tmp_dir = tmpDir
        
        // Extract Packages
        do {
            log.info("Extracting package, \(package)")
            _ = try Spawn(args: ["/usr/bin/ditto", "-x", "-k", package, tmpDir]) { str in
                log.debug(str)
            }
        } catch {
            log.error("\(error)")
            return false
        }
        
        
        let pkgName = tmpDir.stringByAppendingPathComponent(path: package.lastPathComponent).stringByDeletingPathExtension
        let expandedPkgDir = tmpDir.stringByAppendingPathComponent(path: "MacPatch")
        
        // Expand Package
        do {
            log.info("Expand package, \(pkgName)")
            _ = try Spawn(args: ["/usr/sbin/pkgutil", "--expand", pkgName, expandedPkgDir]) { str in
                log.debug(str)
            }
            try fm.removeItem(atPath: pkgName)
        } catch {
            log.error("\(error)")
            return false
        }
        
        return true
    }
    
    /**
     Extract Zipped Package and Expand the Package
     
     - parameter packages: Array of packages
     - parameter pubKey: plublic key string
     - parameter keyHash: md5 hash of the key
     
     - returns: Boolean if succeeds
     */
    func writeServerPubKeyToPackage(packages: [String], pubKey: String, keyHash: String) -> Bool
    {
        if (packages.isEmpty) {
            log.error("Packages array is empty.")
            return false
        }
        
        for p in packages
		{
            if (p.lastPathComponent == "Base.pkg" || p.lastPathComponent == "Client.pkg")
			{
                if fm.fileExists(atPath: p.stringByAppendingPathComponent(path: "Scripts"))
				{
                    let keyFile = p.stringByAppendingPathComponent(path: "Scripts/ServerPub.pem")
                    log.debug("Write public key to \(keyFile)")
                    try! pubKey.write(toFile: keyFile, atomically: false, encoding: String.Encoding.utf8)
                    let mpc = MPCrypto.init()
                    let fHash = mpc.md5Hash(forFile: keyFile)
					log.debug("\(fHash?.lowercased() ?? "Err") = \(keyHash.lowercased())")
                    if (fHash?.lowercased() == keyHash.lowercased()) {
                        return true
                    } else {
                        log.error("Package hashes did not match.")
                        return false
                    }
                }
            }
        }
        
        return false
    }
    
    /**
     Write plist data to Package
     
     - parameter packages: Array of packages
     - parameter plist: plist data
     
     - returns: Boolean if succeeds
     */
    func writePlistToPackage(packages: [String], plist: String) -> Bool
    {
        if (packages.isEmpty) {
            log.error("Packages array is empty.")
            return false
        }
        
        for p in packages
		{
            if ( p.lastPathComponent == "Base.pkg" || p.lastPathComponent == "Client.pkg" )
			{
                if fm.fileExists(atPath: p.stringByAppendingPathComponent(path: "Scripts")) {
                    let plistFile = p.stringByAppendingPathComponent(path: "Scripts/gov.llnl.mpagent.plist")
                    log.debug("Write plist to \(plistFile)")
                    do {
                        try plist.write(toFile: plistFile, atomically: false, encoding: String.Encoding.utf8)
                        var _main: NSDictionary?
                        var _defaults: NSDictionary?
                        _main = NSDictionary(contentsOfFile: plistFile)
                        
                        _defaults = _main?.object(forKey: "default") as? NSDictionary
                        _defaults?.write(toFile: plistFile, atomically: false)

                        return true
                    } catch {
                        log.error("\(error)")
                        return false
                    }
                }
            }
			else if (p.lastPathComponent == "Updater.pkg")
			{
                if fm.fileExists(atPath: p.stringByAppendingPathComponent(path: "Scripts"))
				{
                    if (migration_plist != "") {
                        let fm = FileManager.default
                        let plistFile = p.stringByAppendingPathComponent(path: "Scripts/migration.plist")
                        log.debug("Write migration plist to \(plistFile)")
                        do {
                            try fm.copyItem(atPath: migration_plist, toPath: plistFile)
                            return true
                        } catch {
                            log.error("\(error)")
                            return false
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    /**
     Write plugins to Package
     
     - parameter packages: Array of packages
     - parameter plugins: directory containing plugins
     
     - returns: Boolean if succeeds
     */
    func writePluginsToPackage(packages: [String], plugins_directory: String) -> Bool
    {
        if (packages.isEmpty) {
            log.error("Packages array is empty.")
            return false
        }
        
        for p in packages
		{
            if (p.lastPathComponent == "Base.pkg" || p.lastPathComponent == "Client.pkg")
			{
                let plugins_dir = p.stringByAppendingPathComponent(path: "Scripts/Plugins")
                
                if (!fm.fileExists(atPath: plugins_dir)) {
                    try! fm.createDirectory(atPath: plugins_dir, withIntermediateDirectories: true, attributes: [:])
                }
                
                let plugins_array: [String] = self.getPluginsFromDirectory(path: plugins_directory)!
                if (!plugins_array.isEmpty) {
                    do {
                        log.debug("Write plugins to \(plugins_dir)")
                        for plugin in plugins_array {
                            try fm.copyItem(atPath: plugin, toPath: plugins_dir.stringByAppendingPathComponent(path: plugin.lastPathComponent))
                        }
                        return true
                    } catch {
                        log.error("\(error)")
                        return false
                    }
                }
                
            }
        }
        
        return true
    }
	
	/**
	Write profiles to Package
	
	- parameter packages: Array of packages
	- parameter plugins: directory containing profiles
	
	- returns: Boolean if succeeds
	*/
	func writeProfilesToPackage(packages: [String], profiles_directory: String) -> Bool
	{
		if (packages.isEmpty) {
			log.error("Packages array is empty.")
			return false
		}
		
		for p in packages
		{
			if (p.lastPathComponent == "Base.pkg" || p.lastPathComponent == "Client.pkg")
			{
				let profiles_dir = p.stringByAppendingPathComponent(path: "Scripts/profiles")
				
				if (!fm.fileExists(atPath: profiles_dir)) {
					try! fm.createDirectory(atPath: profiles_dir, withIntermediateDirectories: true, attributes: [:])
				}
				
				let profiles_array: [String] = self.getProfilesFromDirectory(path: profiles_directory)!
				if (!profiles_array.isEmpty) {
					do {
						log.info("Write profiles to \(profiles_dir)")
						for profile in profiles_array {
							log.debug("Write \(profile) to \(profiles_dir.stringByAppendingPathComponent(path: profile.lastPathComponent))")
							try fm.copyItem(atPath: profile, toPath: profiles_dir.stringByAppendingPathComponent(path: profile.lastPathComponent))
						}
						return true
					} catch {
						log.error("\(error)")
						return false
					}
				}
				
			}
		}
		
		return false
	}
    
    /**
     Get Array of plugins from a path
     
     - parameter path: Directory Path
     
     - returns: Array of Strings
     */
    func getPluginsFromDirectory(path: String) -> [String]?
    {
        
        var dir_files: [String] = []
        if fm.fileExists(atPath: path)
        {
            let pkgPredicate = NSPredicate(format: "self ENDSWITH '.bundle'")
            let dir_files_pre = try! fm.contentsOfDirectory(atPath: path) as [String]
            let filtered_results = dir_files_pre.filter { pkgPredicate.evaluate(with: $0) }
            if (!filtered_results.isEmpty)
            {
                for x in filtered_results {
                    dir_files.append(path.stringByAppendingPathComponent(path: x))
                }
            }
        }
        return dir_files
    }
	
	/**
	Get Array of profiles from a path
	
	- parameter path: Directory Path
	
	- returns: Array of Strings
	*/
	func getProfilesFromDirectory(path: String) -> [String]?
	{
		var dir_files: [String] = []
		var dir_files_pre: [String] = []
		let pkgPredicate = NSPredicate(format: "self ENDSWITH '.mobileconfig'")
		
		
		do {
			dir_files_pre = try fm.contentsOfDirectory(atPath: path)
		} catch let error as NSError {
			// handle errors
			print(error.localizedDescription)
		}
		if (dir_files_pre.count >= 1) {
			let filtered_results = dir_files_pre.filter { pkgPredicate.evaluate(with: $0) }
			if (!filtered_results.isEmpty) {
				for x in filtered_results {
					dir_files.append(path.stringByAppendingPathComponent(path: x))
				}
			}
		}
		
		//let dir_files_pre = try! fm.contentsOfDirectory(atPath: path) as [String]
		return dir_files
	}
    
    /**
     Write version info plist to package. Also populates dictionaries for 
     post to web api durning upload
     
     - parameter packages: package path
     - parameter version_file: version file
     
     - returns: Boolean if succeeds
     */
    func writeVersionInfoToPackage(package: String, version_file: String) -> Bool
    {
        let type = package.lastPathComponent.stringByDeletingPathExtension
        var base_dict: [String:Any] = [:]
        let ver_dict: NSDictionary
        let info_dict: NSDictionary = NSDictionary.init(contentsOfFile: version_file)!
        
        let x_type: String
        if (type == "Base") {
            ver_dict = info_dict.object(forKey: "Agent") as! NSDictionary
            x_type = "app"
        } else {
            ver_dict = info_dict.object(forKey: "Updater") as! NSDictionary
            x_type = "update"
        }
        
        let vers: [String] = (ver_dict.object(forKey: "agent_version") as! String).components(separatedBy: ".")
        
        base_dict["framework"] = "0"
        base_dict["build"] = ver_dict.object(forKey: "build")
        base_dict["major"] = vers[0] as String
        base_dict["minor"] = vers[1] as String
        base_dict["bug"] = vers[2] as String
        base_dict["version"] = ver_dict.object(forKey: "version")
        
        // Write Version Plist to Package
        let plistFile = package.stringByAppendingPathComponent(path: "Scripts/.mpVersion.plist")
        log.debug("Write version info to \(plistFile)")
        //log.debug("Config data", userInfo: base_dict as [String : AnyObject])
        (base_dict as NSDictionary).write(toFile: plistFile, atomically: false)
        
        // Set Data needed for agent upload
        base_dict["pkg_name"] = package.lastPathComponent
        base_dict["type"] = x_type
        base_dict["osver"] = ver_dict.object(forKey: "osver")
        base_dict["agent_ver"] = ver_dict.object(forKey: "agent_version")
        base_dict["ver"] = ver_dict.object(forKey: "version")
        
        //log.debug("Config data for upload", userInfo: base_dict as [String : AnyObject])
        
        if (type == "Base") {
            self.agent_dictionary = base_dict
        } else {
            self.updater_dictionary = base_dict
        }
        
        return true
    }
    
    
    /**
     Write registration key to file in package
     
     - parameter packages: package array
     - parameter regKey: registration key string
     
     - returns: Boolean if succeeds
     */
    func writeRegKeyToPackage(packages: [String], regKey: String) -> Bool
    {
        if (packages.isEmpty) {
            return false
        }
        
        if (regKey.isEmpty) {
            return true
        }
        
        for p in packages
		{
            if (p.lastPathComponent == "Base.pkg" || p.lastPathComponent == "Client.pkg")
			{
                if fm.fileExists(atPath: p.stringByAppendingPathComponent(path: "Scripts"))
				{
                    let regFile = p.stringByAppendingPathComponent(path: "Scripts/.mpreg.key")
                    do {
                        try regKey.write(toFile: regFile, atomically: false, encoding: String.Encoding.utf8)
                        return true
                    } catch {
                        log.error("\(error)")
                        return false
                    }
                }
            }
        }
        return false
    }
    
    /**
     Change the background image
     post to web api durning upload
     
     - parameter path: base dir for Background images
     
     - returns: Boolean if succeeds
     */
    func changeBackgroundImageToDoneImage(path: String) -> Bool
    {
        let image = path.stringByAppendingPathComponent(path: "Resources/Background.png")
        let image_done = path.stringByAppendingPathComponent(path: "Resources/Background_done.png")
        
        if (fm.fileExists(atPath: image) && fm.fileExists(atPath: image_done)) {
            do {
                try fm.removeItem(atPath: image)
                try fm.moveItem(atPath: image_done, toPath: image)
                return true
            } catch {
                log.error("\(error)")
                return false
            }
        }
        return true
    }
    
    /**
     Flatten Packages for distribution, if signing is turned on 
     packages will be signed as well.
     
     - parameter packages: array of package paths
     
     - returns: Array of flatten packages
     */
    func flattenPackages(packages: [String], working_dir: String) -> [String]
    {
        var flat_packages: [String] = []
        let sign = (self.signPackageButton.state == .on) ? true : false
        
        
        for p in packages
        {
            var pkg_name: String
            var flatten_pkg_path: String
            
            // Assign the package name
            if (sign == true) {
                pkg_name = "toSign_\(p.lastPathComponent)"
            } else {
                pkg_name = p.lastPathComponent
            }
            
            // Create the path for the flattened package
            if (p.lastPathComponent.pathExtension == "pkg") {
                flatten_pkg_path = working_dir.stringByAppendingPathComponent(path: pkg_name)
            } else {
                flatten_pkg_path = working_dir.stringByAppendingPathComponent(path: pkg_name.stringByAppendingPathExtension(ext: "pkg")!)
            }
            
            // Flatten the package
            if (self.flattenPackage(package: p, flatten_package: flatten_pkg_path)) {
                flat_packages.append(flatten_pkg_path)
            } else {
                log.error("Error flattening package \(p)")
            }
            
            // Sign the flatten package
            if (sign == true) {
                if (!self.signPackage(flatten_pkg_path)) {
                    return []
                }
            }
        }
        return flat_packages
    }
    
    /**
     Flatten Package
     
     - parameter package: path of package to flatten
     - parameter flatten_package: the resulting flattened package
     
     - returns: Bool
     */
    func flattenPackage(package: String, flatten_package: String) -> Bool
    {
        do {
            log.info("Flatten package, \(package)")
			log.info("Flatten package, \(flatten_package)")
            _ = try Spawn(args: ["/usr/sbin/pkgutil", "--flatten", package, flatten_package]) { str in
                log.debug(str)
            }
            return true
        } catch {
            log.error("\(error)")
            return false
        }
    }
    
    /**
     Code Sign Package
     
     - parameter package: path of package to sign
     
     - returns: Bool
     */
    func signPackage(_ package: String) -> Bool
    {
        do {
			var hasErr = false
			
            log.info("Sign package, \(package)")
            let signed_package_name = package.replacingOccurrences(of: "toSign_", with: "")
			let sign_args = ["/usr/bin/productsign", "--sign", self.signingIdentity.stringValue, package, signed_package_name]
			log.info(sign_args.joined(separator: " "))
			
            _ = try Spawn(args: ["/usr/bin/productsign", "--sign", self.signingIdentity.stringValue, package, signed_package_name]) { str in
				log.debug("Sign result: \(str)")
				if (str.contains(find: "error:")) {
					log.error("\(str)")
					hasErr = true
				}
            }
			
			if (hasErr) {
				return false
			}
			
            try fm.removeItem(atPath: package)
            return true
        } catch {
            log.error("\(error)")
            return false
        }
    }
    
    /**
     Compress Package
     
     - parameter packages: array of packages
     
     - returns: Bool
     */
    func compressPackage(package: String) -> Bool
    {
        do {
            log.info("Compress package, \(package)")
            _ = try Spawn(args: ["/usr/bin/ditto", "-c", "-k", package, package.stringByAppendingPathExtension(ext: "zip")!]) { str in
                log.debug(str)
            }
            return true
        } catch {
            log.error("\(error)")
            return false
        }
    }
    
    
    /**
     Upload Packages and Package Data to Server
     
     - parameter packages: array of packages
     - parameter formData: dictionary of update and base package
     
     - returns: Bool
     */
	func uploadPackagesToServer(packages: [String], formData: [String: Any]) -> Bool
	{
		let aid: String = UUID.init().uuidString
		let _ssl = (self.useSSL.state == .on) ? "https" : "http"
		let _url: String = "\(_ssl)://\(self.mpServerHost.stringValue):\(self.mpServerPort.stringValue)/api/v2/agent/upload/\(aid)/\(api_token)"
		log.info("API URL: \(_url)")
		
		var pkgs = [[String:Any]]()
		var fileData: NSData
		
		for p in packages
		{
			fileData = try! NSData.init(contentsOfFile: p)
			let d: [String: Any]
			
			if (p.lastPathComponent.contains("Base.pkg") || p.lastPathComponent.contains("Client.pkg"))
			{
				d = ["name": "fBase", "fileName": p.lastPathComponent, "data": fileData as Data]
			}
			else if (p.lastPathComponent.contains("MacPatch.pkg"))
			{
				d = ["name": "fComplete", "fileName": p.lastPathComponent, "data": fileData as Data]
			}
			else if (p.lastPathComponent.contains("Updater.pkg"))
			{
				d = ["name": "fUpdate", "fileName": p.lastPathComponent, "data": fileData as Data]
			}
			else
			{
				continue
			}
			pkgs.append(d)
		}
		var didUpload = false
		let jsonData = try! JSONSerialization.data(withJSONObject: formData, options: [])
		let semaphore = DispatchSemaphore(value: 0)
		
		let jstring = NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue)
		log.info("JSON Data: \(jstring ?? "{}")")
		
		Alamofire.upload(multipartFormData: { multipartFormData in
			
			for f in pkgs {
				multipartFormData.append(f["data"] as! Data,
										 withName: f["name"] as! String,
										 fileName: f["fileName"] as! String,
										 mimeType: "application/octet-stream")
			}

			multipartFormData.append(jsonData, withName: "data")

		}, to: _url, encodingCompletion: { encodingResult in
			switch encodingResult {
			case .success(let upload, _, _):
				upload.validate()
					.responseJSON { response in
						switch response.result {
						case .success( _):
							didUpload = true
						case .failure(let responseError):
							let error = responseError as? AFError
							let message : String
							if let httpStatusCode = error?.responseCode {
								switch(httpStatusCode) {
								case 424:
									message = "Failed to verify user rights or bad token."
								case 426:
									message = "Agent Exists"
								default:
									message = responseError as! String
								}
							} else {
								message = responseError as! String
							}
							log.error("Upload error: \(message)")
						}
						semaphore.signal()
				}
			case .failure(let encodingError):
				log.error("encodingError: \(encodingError)")
				semaphore.signal()
			}
		})
		
		_ = semaphore.wait(timeout: .distantFuture)
		return didUpload
	}
	
// MARK: - Plugins and Profile Data
	
	/**
	Collects info on all plugins included with the agent install
	
	- returns: Array of Dictionaries
	*/
	func collectPluginsData() -> [[String:Any]]
	{
		var result = [[String:Any]]()
		
		let _plugins: [String] = self.getPluginsFromDirectory(path: self.pluginsPath.stringValue)!
		for p in _plugins
		{
			let b = Bundle.init(path: p)
			let d = b?.infoDictionary
			let x = ["plugin": p.lastPathComponent,
					 "bundleIdentifier": (d!["CFBundleIdentifier"] ?? "NA"),
					 "version": (d!["CFBundleShortVersionString"] ?? "NA")]
			result.append(x)
		}

		return result
	}
	
	/**
	Collects info on all profiles included with the agent install
	
	- returns: Array of Dictionaries
	*/
	func collectProfilesData() -> [[String:Any]]
	{
		var result = [[String:Any]]()
		let _profiles: [String] = self.getProfilesFromDirectory(path: self.profilesPath.stringValue)!
		for p in _profiles
		{
			let _profileConverted = self.convertSignedProfile(profile: p)
			let payload: NSDictionary? = NSDictionary(contentsOfFile: _profileConverted)
			_ = try? FileManager.default.removeItem(atPath: _profileConverted)
			let x = ["displayName": (payload!["PayloadDisplayName"] ?? "NA"),
					 "identifier": (payload!["PayloadIdentifier"] ?? "NA"),
					 "organization": (payload!["PayloadOrganization"] ?? "NA"),
					 "version": (payload!["PayloadVersion"] ?? "NA"),
					 "fileName": p.lastPathComponent]
			
			result.append(x)
		}
		
		return result
	}
	
	func convertSignedProfile(profile: String) -> String
	{
		let uuid = "/tmp/\(UUID().uuidString)"
		_ = run("/usr/bin/security", "cms", "-D", "-i", profile, "-o", uuid)
		return uuid
	}
	
	
// MARK: - Notifications
    
    @objc func toggleLoggingLevel(notification: Notification)
    {
        log.info("Changing Logging Level")
        if (defaults.object(forKey: "Debug") != nil) {
            if defaults.bool(forKey: "Debug") {
                log.info("Disable Debug Logging")
                defaults.set(false, forKey: "Debug")
                self.postPackageStatus.stringValue = ""
            } else {
                log.info("Enable Debug Logging")
                defaults.set(true, forKey: "Debug")
            }
        } else {
            log.info("Enable Debug Logging")
            defaults.set(true, forKey: "Debug")
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: Notification.Name("setLogLevel"), object: nil)
    }
    
    @objc func toggleAgentUpload(notification: Notification)
    {
        log.info("Changing Agent Upload Action")
        if (defaults.object(forKey: "doNotUpload") != nil) {
            if defaults.bool(forKey: "doNotUpload") {
                log.info("Enable Agent Upload")
                defaults.set(false, forKey: "doNotUpload")
                self.postPackageStatus.stringValue = ""
            } else {
                log.info("Disable Agent Upload")
                defaults.set(true, forKey: "doNotUpload")
                self.postPackageStatus.stringValue = "Upload is disabled for testing. Will open folder."
            }
        } else {
            log.info("Disable Agent Upload")
            defaults.set(true, forKey: "doNotUpload")
            self.postPackageStatus.stringValue = "Upload is disabled for testing. Will open folder."
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: Notification.Name("setLogLevel"), object: nil)
    }
    
    @objc func toggleSelfSigned(notification: Notification)
    {
        if (defaults.object(forKey: "selfSigned") != nil) {
            if defaults.bool(forKey: "selfSigned") {
                log.info("Disable Self Signed Certificates")
                defaults.set(false, forKey: "selfSigned")
            } else {
                log.info("Enable Self Signed Certificates")
                defaults.set(true, forKey: "selfSigned")
            }
        } else {
            log.info("Enable Self Signed Certificates")
            defaults.set(true, forKey: "selfSigned")
        }
        
        defaults.synchronize()
    }
    
    @objc func setLogLevel(notification: Notification)
    {
        if (defaults.object(forKey: "Debug") != nil)
        {
            
            if defaults.bool(forKey: "Debug")
            {
                log = LXLogger(endpoints: [
                    LXRotatingFileEndpoint(
                        baseURL: URL(fileURLWithPath: logPath),
                        numberOfFiles: 7,
                        maxFileSizeKiB: (10 * 1024 * 1024),
                        minimumPriorityLevel: .debug,
                        dateFormatter: LXDateFormatter(formatString: "yyyy-MM-dd HH:mm:ss",timeZone: NSTimeZone.local),
                        entryFormatter: LXEntryFormatter({ entry in return
                            "\(entry.dateTime) [\(entry.level)] [\(entry.fileName)] \(entry.functionName):\(entry.lineNumber) --- \(entry.message)"
                        })
                    )
                    ])
            }
            else
            {
                log = LXLogger(endpoints: [
                    LXRotatingFileEndpoint(
                        baseURL: URL(fileURLWithPath: logPath),
                        numberOfFiles: 7,
                        maxFileSizeKiB: (10 * 1024 * 1024),
                        minimumPriorityLevel: .info,
                        dateFormatter: LXDateFormatter(formatString: "yyyy-MM-dd HH:mm:ss",timeZone: NSTimeZone.local),
                        entryFormatter: LXEntryFormatter({ entry in return
                            "\(entry.dateTime) [\(entry.level)] [\(entry.fileName)] \(entry.functionName):\(entry.lineNumber) --- \(entry.message)"
                        })
                    )
                    ])
            }
        }
    }
}

