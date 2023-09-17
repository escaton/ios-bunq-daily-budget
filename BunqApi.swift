//
//  BunqApi.swift
//  Daily budget
//
//  Created by Egor Blinov on 22/08/2023.
//

import Foundation
import Alamofire
import SwiftyJSON

private class BunqApiRequestInterceptor: RequestInterceptor {
    private let withAuth: Bool
    private let privateKey: SecKey?
    private let serverPublicKey: SecKey?
    init (withAuth: Bool, privateKey: SecKey?, serverPublicKey: SecKey?) {
        self.withAuth = withAuth
        self.privateKey = privateKey
        self.serverPublicKey = serverPublicKey
    }
    
    private func signRequestBody(inputData: Data, privateKey: SecKey) -> String? {
        var error: Unmanaged<CFError>?
        if let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, inputData as CFData, &error) as Data? {
            return signature.base64EncodedString()
        } else {
            if let errorDescription = error?.takeRetainedValue() {
                print("Error creating signature: \(errorDescription)")
            }
            return nil
        }
    }
    
    func validateServerResponse(_: URLRequest?, httpURLResponse: HTTPURLResponse, data: Data?) -> Result<Void, Error> {
        guard let serverPublicKey = serverPublicKey, let data = data else {
            return .success(())
        }
        
        if httpURLResponse.statusCode >= 400 {
            return .success(())
        }
        
        guard let signString = httpURLResponse.value(forHTTPHeaderField: "X-Bunq-Server-Signature"),
              let signBase64Data = signString.data(using: .utf8),
              let signData = Data(base64Encoded: signBase64Data) else {
            return .failure(BunqApiError.noResponseSignature)
        }
        
        var error: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            serverPublicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            signData as CFData,
            &error
        )
        if verified {
            return .success(())
        } else {
            return .failure(BunqApiError.serverSignatureError(String(describing: error?.takeRetainedValue())))
        }
    }
    
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var urlRequest = urlRequest
        if withAuth,
           let httpBody = urlRequest.httpBody,
           let privateKey = self.privateKey,
           let sign = self.signRequestBody(inputData: httpBody, privateKey: privateKey) {
            urlRequest.addValue(sign, forHTTPHeaderField: "X-Bunq-Client-Signature")
        }
        
        var requestBody: String? = nil
        if let httpBody = urlRequest.httpBody,
           let string = String(data: httpBody, encoding: .utf8) {
            requestBody = string
        }
        
        print("=> \(urlRequest.httpMethod!) \(urlRequest.url!) \(requestBody ?? "<no body>")")
        completion(.success(urlRequest))
    }
}

enum BunqApiError: Error {
    case error(String)
    case noResponseSignature
    case serverSignatureError(String?)
}

struct Pagination {
    let newerUrl: String?
    let olderUrl: String?
}

enum Paginate {
    case newer
    case older
    
    func getPagination(_ pagination: Pagination) -> String? {
        switch self {
        case .newer:
            return pagination.newerUrl
        case .older:
            return pagination.olderUrl
        }
    }
}

private class BunqApiJSONSerializer: DataResponseSerializerProtocol {
    typealias SerializedObject = (JSON, Pagination?)
    private let dataResponseSerializer = DataResponseSerializer()

    
    func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> SerializedObject {
        let data = try dataResponseSerializer.serialize(request: request, response: response, data: data, error: error)
        let json = JSON(data);
        
        var pagination: Pagination? = nil
        if let paginationJSON = json["Pagination"].dictionary {
            pagination = Pagination(
                newerUrl: paginationJSON["newer_url"]?.string,
                olderUrl: paginationJSON["older_url"]?.string
            )
        }
        
        if let responseField = json["Response"].array {
            return (JSON(responseField), pagination)
        } else if let errorDescription = json["Error"][0]["error_description"].string {
            throw BunqApiError.error(errorDescription)
        }
        throw BunqApiError.error("No error description")
    }
}

class BunqApi {
    static let baseURL = "https://api.bunq.com"
    
    private let token: String?
    private let privateKey: SecKey?
    private let serverPublicKey: SecKey?
    private let errorHandler: ((Error) -> Void)?
    
    init(token: String? = nil, privateKey: SecKey? = nil, serverPublicKey: SecKey? = nil, errorHandler: ((Error) -> Void)? = nil) {
        self.token = token
        self.privateKey = privateKey
        self.serverPublicKey = serverPublicKey
        self.errorHandler = errorHandler
    }
    
    private func call<Body: Encodable>(
        enpoint: String,
        withAuth: Bool = true,
        method: HTTPMethod = .get,
        body: Body? = nil as String?
    ) -> DataTask<BunqApiJSONSerializer.SerializedObject> {
        let url = BunqApi.baseURL + enpoint
        var headers = HTTPHeaders([
            "Cache-Control": "no-cache",
            "User-Agent": "bunq-Daily-Budget/1.00"
        ])
        if withAuth, let token = self.token {
            headers.add(name: "X-Bunq-Client-Authentication", value: token)
        }
        
        let interceptor = BunqApiRequestInterceptor(
            withAuth: withAuth,
            privateKey: privateKey,
            serverPublicKey: serverPublicKey
        )
        
        return AF.request(
            url,
            method: method,
            parameters: body,
            encoder: JSONParameterEncoder.default,
            headers: headers,
            interceptor: interceptor
        )
            .validate(contentType: ["application/json"])
            .validate(interceptor.validateServerResponse)
            .responseString { response in
                print("<= \(response.response?.statusCode ?? 0) \(response.value ?? "<unknown response body>")")
            }
            .serializingResponse(using: BunqApiJSONSerializer())
    }
    
    func installation(publicKeyPEM: String) async -> Result<(String, String), Error> {
        let result = await call(
            enpoint: "/v1/installation",
            withAuth: false,
            method: .post,
            body: ["client_public_key": publicKeyPEM]
        ).result
        switch result {
        case .success(let (json, _)):
            if let token = json.arrayValue.first(where: {$0["Token"]["token"].exists()})?["Token"]["token"].string,
               let serverPublicKeyPEM = json.arrayValue.first(where: {$0["ServerPublicKey"]["server_public_key"].exists()})?["ServerPublicKey"]["server_public_key"].string {
                return .success((token, serverPublicKeyPEM))
            }
            return .failure(BunqApiError.error("No installation token or ServerPublicKey"))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func deviceServer(description: String, apiKey: String, permittedIps: [String]) async -> Result<JSON, AFError> {
        struct Body: Codable {
            let description: String
            let secret: String
            let permitted_ips: [String]
        }
        return await call(enpoint: "/v1/device-server", method: .post, body:
            Body(description: description, secret: apiKey, permitted_ips: permittedIps)
        ).result.map { (json, _) in json }
    }
    
    func sessionServer(_ apiKey: String) async -> Result<(String, String), Error> {
        let result = await call(enpoint: "/v1/session-server", method: .post, body: ["secret": apiKey]).result
     
        switch result {
        case .success(let (json, _)):
            if let sessionToken = json.arrayValue.first(where: {$0["Token"]["token"].exists()})?["Token"]["token"].string,
               let userId = json.arrayValue.first(where: {$0["UserPerson"]["id"].exists()})?["UserPerson"]["id"].number {
                return .success((sessionToken, userId.stringValue))
            }
            return .failure(BunqApiError.error("No session token or userId"))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func monetaryAccounts(userId: String) async -> Result<JSON, AFError> {
        return await call(enpoint: "/v1/user/\(userId)/monetary-account")
            .result.map { (json, _) in json }
    }
    
    func monetaryAccount(userId: String, accountId: String) async -> Result<JSON, AFError> {
        return await call(enpoint: "/v1/user/\(userId)/monetary-account/\(accountId)")
            .result.map { (json, _) in json }
    }
    
    // TODO 429 pauses
    func monetaryAccountPayments(userId: String, accountId: String, paginate: (_ json: JSON) -> Paginate?) async -> Result<[JSON], Error> {
        var url = "/v1/user/\(userId)/monetary-account/\(accountId)/payment"
        var result: [JSON] = []
        do {
            while true {
                let (json, pagination) = try await call(enpoint: url).result.get()
                if let jsonArray = json.array {
                    result.append(contentsOf: jsonArray)
                }
                if let pagination = pagination,
                   let paginationDecision = paginate(json),
                   let newUrl = paginationDecision.getPagination(pagination) {
                    url = newUrl
                } else {
                    return .success(result)
                }
            }
        } catch {
            return .failure(error)
        }
    }
}
