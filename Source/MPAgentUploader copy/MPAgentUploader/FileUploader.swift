//
//  FileUploader.swift
//  MPAgentUploder
//
//  Created by Charles Heizer on 12/11/16.
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

import Foundation
import Alamofire
/*
class AlamofireSynchronous
{
    class func uploadRequest(multipartFormData: @escaping (MultipartFormData) -> Void, to: URLConvertible, method: HTTPMethod, headers: HTTPHeaders? = nil) -> UploadRequest? {
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: UploadRequest? = nil
        var intResult = 2
        
        
        
        MPAlamofire.upload(multipartFormData: multipartFormData, to: to, method: method, headers: headers) { (res: Alamofire.Session.MultipartFormDataEncodingResult) in
            
            switch res {
                case .success(let upload, _, _):
                    upload.validate(statusCode: 200...299)
                        .validate(contentType: ["application/json"])
                        .response { response in
                            upload.responseJSON {res2 in
                                if(res2.result.isSuccess) {
                                    result = upload
                                    intResult = 0
                                    //let response = res.result.value as! NSDictionary
                                    //success
                                    //var jsonData = JSON(response)
                                    //print(jsonData)
                                }
                            }
                        }
                case .failure(let e):
                    print("Error while creating upload request : \(e)")
                    intResult = 1
                    break
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .distantFuture)
        while intResult > 1 {
            sleep(1)
        }
        return result
    }
}
*/
