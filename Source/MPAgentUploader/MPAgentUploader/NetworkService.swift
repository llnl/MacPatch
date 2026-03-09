//
//  NetworkService.swift
//  MPAgentUploder
//
//  Native URLSession replacement for Alamofire
//
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

// MARK: - Network Result Types

enum NetworkResult<T> {
    case success(T)
    case failure(Error)
    
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

struct NetworkResponse<T> {
    let result: NetworkResult<T>
    let statusCode: Int?
    let data: Data?
}

// MARK: - Network Service

class NetworkService: NSObject {
    static let shared = NetworkService()
    
    private var session: URLSession!
    private var allowSelfSigned: Bool = false
    private var trustedHost: String?
    
    private override init() {
        super.init()
        configureSession(allowSelfSigned: false, trustedHost: nil)
    }
    
    func configureSession(allowSelfSigned: Bool, trustedHost: String?) {
        self.allowSelfSigned = allowSelfSigned
        self.trustedHost = trustedHost
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Async Request Methods
    
    func request(
        _ url: String,
        method: HTTPMethod = .get,
        parameters: [String: Any]? = nil,
        encoding: ParameterEncoding = .url,
        headers: [String: String]? = nil,
        completion: @escaping (NetworkResponse<Any>) -> Void
    ) {
        guard let requestURL = URL(string: url) else {
            let error = NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            completion(NetworkResponse(result: .failure(error), statusCode: nil, data: nil))
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = method.rawValue
        
        // Set headers
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        // Encode parameters
        do {
            request = try encoding.encode(request, with: parameters)
        } catch {
            completion(NetworkResponse(result: .failure(error), statusCode: nil, data: nil))
            return
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            self.handleResponse(data: data, response: response, error: error, completion: completion)
        }
        task.resume()
    }
    
    // MARK: - Synchronous Request Methods
    
    func requestSync(_ url: String) -> NetworkResponse<Any> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: NetworkResponse<Any>!
        
        request(url) { response in
            result = response
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .distantFuture)
        return result
    }
    
    func validateStatusCode(_ statusCode: Int, in range: ClosedRange<Int>) -> Bool {
        return range.contains(statusCode)
    }
    
    // MARK: - Upload Methods
    
    func upload(
        multipartFormData: MultipartFormData,
        to url: String,
        method: HTTPMethod = .post,
        headers: [String: String]? = nil,
        completion: @escaping (NetworkResponse<Any>) -> Void
    ) {
        guard let requestURL = URL(string: url) else {
            let error = NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            completion(NetworkResponse(result: .failure(error), statusCode: nil, data: nil))
            return
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = method.rawValue
        
        // Set multipart headers
        request.setValue("multipart/form-data; boundary=\(multipartFormData.boundary)", forHTTPHeaderField: "Content-Type")
        
        // Set additional headers
        headers?.forEach { key, value in
            if key.lowercased() != "content-type" { // Don't override Content-Type
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        request.httpBody = multipartFormData.encode()
        
        let task = session.dataTask(with: request) { data, response, error in
            self.handleResponse(data: data, response: response, error: error, completion: completion)
        }
        task.resume()
    }
    
    // MARK: - Response Handling
    
    private func handleResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (NetworkResponse<Any>) -> Void
    ) {
        if let error = error {
            completion(NetworkResponse(result: .failure(error), statusCode: nil, data: data))
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            let error = NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            completion(NetworkResponse(result: .failure(error), statusCode: nil, data: data))
            return
        }
        
        let statusCode = httpResponse.statusCode
        
        guard let data = data else {
            let error = NSError(domain: "NetworkService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
            completion(NetworkResponse(result: .failure(error), statusCode: statusCode, data: nil))
            return
        }
        
        // Try to parse JSON
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            completion(NetworkResponse(result: .success(json), statusCode: statusCode, data: data))
        } catch {
            // If JSON parsing fails, return the raw data as string
            if let string = String(data: data, encoding: .utf8) {
                completion(NetworkResponse(result: .success(string), statusCode: statusCode, data: data))
            } else {
                completion(NetworkResponse(result: .failure(error), statusCode: statusCode, data: data))
            }
        }
    }
}

// MARK: - URLSessionDelegate for SSL Pinning

extension NetworkService: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowSelfSigned else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        // Check if we should trust this specific host
        if let trustedHost = trustedHost,
           challenge.protectionSpace.host == trustedHost,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

// MARK: - Parameter Encoding

enum ParameterEncoding {
    case url
    case json
    
    func encode(_ request: URLRequest, with parameters: [String: Any]?) throws -> URLRequest {
        guard let parameters = parameters else { return request }
        
        var modifiedRequest = request
        
        switch self {
        case .url:
            if let url = modifiedRequest.url {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.queryItems = parameters.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
                modifiedRequest.url = components?.url
            }
            
        case .json:
            let jsonData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            modifiedRequest.httpBody = jsonData
            modifiedRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return modifiedRequest
    }
}

// MARK: - Multipart Form Data

class MultipartFormData {
    private(set) var boundary: String
    private var bodyParts: [BodyPart] = []
    
    private struct BodyPart {
        let data: Data
        let name: String
        let fileName: String?
        let mimeType: String?
    }
    
    init() {
        self.boundary = "Boundary-\(UUID().uuidString)"
    }
    
    func append(_ data: Data, withName name: String, fileName: String? = nil, mimeType: String? = nil) {
        let bodyPart = BodyPart(data: data, name: name, fileName: fileName, mimeType: mimeType)
        bodyParts.append(bodyPart)
    }
    
    func encode() -> Data {
        var body = Data()
        
        for bodyPart in bodyParts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            
            var disposition = "Content-Disposition: form-data; name=\"\(bodyPart.name)\""
            if let fileName = bodyPart.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            body.append("\(disposition)\r\n".data(using: .utf8)!)
            
            if let mimeType = bodyPart.mimeType {
                body.append("Content-Type: \(mimeType)\r\n".data(using: .utf8)!)
            }
            
            body.append("\r\n".data(using: .utf8)!)
            body.append(bodyPart.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}
