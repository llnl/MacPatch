//
//  AuthViewController.swift
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

protocol AuthViewControllerDelegate: class {
    func didFinishAuthRequest(sender: AuthViewController, token:String)
}

class AuthViewController: NSViewController
{
    
    var delegate: AuthViewControllerDelegate?
    
    var x_mpServer: String?
    var x_mpPort: String?
    var x_useSSL: Int?
    
    @IBOutlet weak var authUserID: NSTextField!
    @IBOutlet weak var authUserPass: NSSecureTextField!
    @IBOutlet weak var authProgressWheel: NSProgressIndicator!
    @IBOutlet weak var authStatusField: NSTextField!
    @IBOutlet weak var authRequestButton: NSButton!
    
    let defaults = UserDefaults.standard
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if defaults.bool(forKey: "selfSigned") {
            MPAlamofire={ ()->Alamofire.SessionManager in
                let policies:[String:ServerTrustPolicy]=[self.x_mpServer!: .disableEvaluation]
                let manager=Alamofire.SessionManager(serverTrustPolicyManager:ServerTrustPolicyManager(policies:policies))
                return manager
            }()
        }
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }

    @IBAction func makeAuthRequest(_ sender: Any)
    {
        self.authStatusField.stringValue = ""
        self.authProgressWheel.startAnimation(nil)
   
        let _ssl = (NSControl.StateValue.init(x_useSSL!) == NSControl.StateValue.on) ? "https" : "http"
        let _url: String = "\(_ssl)://\(x_mpServer!):\(x_mpPort!)\(URI_PREFIX)/auth/token"
		log.debug("Auth Request URL: \(_url)")
		
        let _params: Parameters = ["authUser":authUserID.stringValue, "authPass":authUserPass.stringValue]
        
        MPAlamofire.request(_url, method: .post, parameters: _params, encoding: JSONEncoding.default).validate().responseJSON
        { response in

            switch response.result
            {
            case .failure(let error):
				log.error("\(error.localizedDescription)")
                self.authStatusField.stringValue = error.localizedDescription
            
            case .success(let resultData):
                
                var api_token = "NA"
                
                if let resultDict = resultData as? [String: Any] {
                    if let res = resultDict["result"] as? [String: Any] {
                        api_token = res["token"] as! String? ?? "NA"
                        
                        if let delegate = self.delegate {
                            delegate.didFinishAuthRequest(sender: self, token:api_token)
                        }
                        
                        self.dismiss(self)
                    }
                }
            }
 
            self.authProgressWheel.stopAnimation(nil)
        }
    }
}
