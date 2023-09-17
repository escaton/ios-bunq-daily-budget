//
//  BunqService.swift
//  Daily budget
//
//  Created by Egor Blinov on 22/08/2023.
//

import Foundation
import Security
import SwiftyJSON

struct AuthorizationData {
    let privateKey: SecKey
    let serverPublicKey: SecKey
    let installationToken: String
    let apiKey: String
}

struct UserPreferences: Codable {
    let accountId: String
    let accountName: String
    let userId: String
}

struct MonetaryAccount: Identifiable {
    let id: String
    let userId: String
    let description: String
    let balance: String
}

struct Payment: Identifiable {
    let id: NSNumber
    let created: Date
    let description: String
    let amount: Float
    let balanceAfter: Float
}

struct Balance: Codable {
    let date: Date
    let todayLeftPercent: Float
    let todayLeft: Float
    let balance: Float
    let daysLeft: Int
}

class BunqService {
    static let shared = BunqService()
    
    func getUserPreferences() -> UserPreferences? {
        guard let appGroup = UserDefaults(suiteName: "group.com.escaton.Daily-budget.shared"),
              let prefsData = appGroup.data(forKey: "user-preferences"),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: prefsData) else {
            return nil
        }
        return prefs
    }
    
    func storeUserPreferences(_ prefs: UserPreferences) -> Void {
        if let appGroup = UserDefaults(suiteName: "group.com.escaton.Daily-budget.shared"),
           let prefsJson = try? JSONEncoder().encode(prefs) {
            appGroup.set(prefsJson, forKey: "user-preferences")
        }
    }
    
    func getLastBalance() -> Balance? {
        guard let appGroup = UserDefaults(suiteName: "group.com.escaton.Daily-budget.shared"),
              let balanceData = appGroup.data(forKey: "last-balance"),
              let balance = try? JSONDecoder().decode(Balance.self, from: balanceData) else {
            return nil
        }
        return balance
    }
    
    func storeLastBalance(_ balance: Balance) -> Void {
        if let appGroup = UserDefaults(suiteName: "group.com.escaton.Daily-budget.shared"),
           let balanceJson = try? JSONEncoder().encode(balance) {
            appGroup.set(balanceJson, forKey: "last-balance")
        }
    }
    
    func getAuthorization() -> AuthorizationData? {
        guard let apiKey = getTokenFromKeychain(key: "api-key") else {
            print("Failed to get apiKey from keychain")
            return nil
        }
        guard let installationToken = getTokenFromKeychain(key: "installation-token") else {
            print("Failed to get installationToken from keychain")
            return nil
        }
        guard let serverPublicKey = getRSAKeyFromKeychain(key: "server-public-key", keyClass: kSecAttrKeyClassPublic) else {
            print("Failed to get serverPublicKey from keychain")
            return nil
        }
        guard let privateKey = getRSAKeyFromKeychain(key: "private-key", keyClass: kSecAttrKeyClassPrivate) else {
            print("Failed to get privateKey from keychain")
            return nil
        }
        return AuthorizationData(
            privateKey: privateKey,
            serverPublicKey: serverPublicKey,
            installationToken: installationToken,
            apiKey: apiKey
        )
    }
    
    func inspectRSAInKeychain() {
        let attributes: [String: Any] = [
            kSecClass as String             : kSecClassKey,
            kSecReturnAttributes as String  : true,
            kSecMatchLimit as String        : kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            print("Found \(String(describing: result))")
        default:
            let message = SecCopyErrorMessageString(status, nil) as NSString? as String?
            print("Failed to inspect keychain status: \(message ?? "<unknown \(status) code>")")
        }
    }
    
    func accounts(_ auth: AuthorizationData) async -> [MonetaryAccount]? {
        let installationToken = auth.installationToken
        let privateKey = auth.privateKey
        let serverPublicKey = auth.serverPublicKey
        let apiKey = auth.apiKey
        
        var api = BunqApi(token: installationToken, privateKey: privateKey, serverPublicKey: serverPublicKey)
        do {
            let ( sessionToken, userId ) = try await api.sessionServer(apiKey).get()
            api = BunqApi(token: sessionToken, privateKey: privateKey, serverPublicKey: serverPublicKey)
            let accounts = try await api.monetaryAccounts(userId: userId).get()
            return accounts.array?.compactMap {
                let account = $0["MonetaryAccountBank"]
                if let id = account["id"].number?.stringValue,
                   let description = account["description"].string,
                   let balance = account["balance"]["value"].string,
                   let userId = account["user_id"].number?.stringValue {
                    return MonetaryAccount(
                        id: id,
                        userId: userId,
                        description: description,
                        balance: balance
                    )
                } else {
                    return nil
                }
            }
        } catch {
            print("Error \(error)")
        }
        return nil
    }
    
    func todayBalance(_ auth: AuthorizationData, userId: String, accountId: String) async -> Balance? {
        let installationToken = auth.installationToken
        let privateKey = auth.privateKey
        let serverPublicKey = auth.serverPublicKey
        let apiKey = auth.apiKey
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        let startOfToday = Calendar.current.startOfDay(for: Date.now)
        
        let daysBefore25th = {
            let fromDay = Calendar.current.component(.day, from: startOfToday)
            var toDate = Calendar.current.date(byAdding: .day, value: 25-fromDay, to: startOfToday)!
            if (fromDay >= 25) {
                toDate = Calendar.current.date(byAdding: .month, value: 1, to: toDate)!
            }

            return Calendar.current.dateComponents([.day], from: startOfToday, to: toDate).day!
        }()
        
        var api = BunqApi(token: installationToken, privateKey: privateKey, serverPublicKey: serverPublicKey)
        do {
            let ( sessionToken, _ ) = try await api.sessionServer(apiKey).get()
            api = BunqApi(token: sessionToken, privateKey: privateKey, serverPublicKey: serverPublicKey)
            let payments = try await api.monetaryAccountPayments(userId: userId, accountId: accountId) { json in
                if let created = json.array?.last?["Payment"]["created"].string,
                   let date = dateFormatter.date(from: created) {
                    print("oldest payment is \(date)")
                    if (date >= startOfToday) {
                        return .older
                    }
                }
                return .none
            }.get().compactMap {
                let payment = $0["Payment"]
                if let id = payment["id"].number,
                   let createdString = payment["created"].string,
                   let created = dateFormatter.date(from: createdString),
                   let description = payment["description"].string,
                   let amount = payment["amount"]["value"].string,
                   let balanceAfter = payment["balance_after_mutation"]["value"].string {
                    return Payment(
                        id: id,
                        created: created,
                        description: description,
                        amount: (amount as NSString).floatValue,
                        balanceAfter: (balanceAfter as NSString).floatValue
                    )
                } else {
                    return nil
                }
            }
            
            var todaySpent = Float(0)
            var balanceAfter = Float(0)
            
            if let recentPayment = payments.first {
                if recentPayment.created > startOfToday {
                    if let yesterdayPayment = payments.first(where: { $0.created < startOfToday }) {
                        // have today and yesterday history
                        todaySpent = yesterdayPayment.balanceAfter - recentPayment.balanceAfter
                        balanceAfter = recentPayment.balanceAfter
                    } else {
                        // all payments are today's
                        todaySpent = 0
                        balanceAfter = recentPayment.balanceAfter
                    }
                } else {
                    // no payments today
                    todaySpent = 0
                    balanceAfter = recentPayment.balanceAfter
                }
            }
            
            let todayLeft = min(max(80-todaySpent,0),80)
            
            return Balance(
                date: Date.now,
                todayLeftPercent: todayLeft/80,
                todayLeft: todayLeft,
                balance: balanceAfter - todayLeft - Float(daysBefore25th-1) * 80,
                daysLeft: daysBefore25th
            )
        } catch {
            print("Error \(error)")
        }
        return nil
    }
    
    func setup(apiKey: String) async throws {
        
        clearKeychain()

        var api = BunqApi()
        
        guard let privateKey = generateRSAKeyPair() else {
            fatalError("Failed to generate private key")
        }
        
        if setRSAKeyToKeychain(secKey: privateKey, key: "private-key") == nil {
            fatalError("Failed to set privateKey to keychain")
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            fatalError("Failed to generate public key")
        }
        guard let publicKeyPEM = secKeyToPEM(key: publicKey, kind: "RSA PUBLIC") else {
            fatalError("Failed to generate public key PEM")
        }
        
        let installationResult = await api.installation(publicKeyPEM: publicKeyPEM)
        guard let (installationToken, serverPublicKeyPEM) = try? installationResult.get() else {
            fatalError("Failed to create installation")
        }
        
        guard let serverPublicKey = PEMtoSecKey(serverPublicKeyPEM, keyClass: kSecAttrKeyClassPublic) else {
            fatalError("Failed to generate serverPublicKey")
        }
        if setRSAKeyToKeychain(secKey: serverPublicKey, key: "server-public-key") == nil {
            fatalError("Failed to set serverPublicKey to keychain")
        }
        
        if setTokenToKeychain(token: installationToken, key: "installation-token") == nil {
            fatalError("Failed to set setInstallationToken to keychain")
        }
        
        api = BunqApi(token: installationToken, privateKey: privateKey, serverPublicKey: serverPublicKey)
        let deviceServerResult = await api.deviceServer(description: "Daily budget app", apiKey: apiKey, permittedIps: ["*"])

        switch deviceServerResult {
        case .success(let json):
            print("success device server \(json)")
        case .failure(let error):
            fatalError("Failed to call device server \(error)")
        }
        
        if setTokenToKeychain(token: apiKey, key: "api-key") == nil {
            fatalError("Failed to set apiKey to keychain")
        }
    }
    
    private func getRSAKeyFromKeychain(key: String, keyClass: CFString) -> SecKey? {
        let attributes: [String: Any] = [
            kSecClass as String             : kSecClassKey,
            kSecAttrKeyClass as String      : keyClass,
            kSecAttrApplicationTag as String: Data(key.utf8),
            kSecReturnRef as String         : true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if (status == errSecSuccess) {
            return (item as! SecKey)
        } else {
            let message = SecCopyErrorMessageString(status, nil) as NSString? as String?
            print("Failed to get key \"\(key)\" from keychain, status: \(message ?? "<unknown \(status) code>")")
        }
        return nil
    }
    
    private func setRSAKeyToKeychain(secKey: SecKey, key: String) -> Void? {
        let attributes: [String: Any] = [
            kSecClass as String              : kSecClassKey,
            kSecAttrApplicationTag as String : Data(key.utf8),
            kSecAttrAccessible as String     : kSecAttrAccessibleAfterFirstUnlock,
            kSecValueRef as String           : secKey
        ]
        
        let status = SecItemAdd(attributes as CFDictionary, nil)
        
        switch status {
        case errSecSuccess:
            return ()
        default:
            let message = SecCopyErrorMessageString(status, nil) as NSString? as String?
            print("Failed to set key \"\(key)\" to keychain , status: \(message ?? "<unknown \(status) code>")")
        }
        return nil
    }
    
    private func getTokenFromKeychain(key: String) -> String? {
        let attributes: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : key,
            kSecAttrService as String : "Bunq",
            kSecReturnData as String   : true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            if let token = result as? Data {
                return String(data: token, encoding: .utf8)
            } else {
                print("Failed to parse \"\(key)\" keychain value to Data")
            }
            
        default:
            let message = SecCopyErrorMessageString(status, nil) as NSString? as String?
            print("Failed to get token \"\(key)\" from keychain , status: \(message ?? "<unknown \(status) code>"), statusCode: \(status)")
        }
        return nil
    }
    
    private func setTokenToKeychain(token: String, key: String) -> Void? {
        let attributes: [String: Any] = [
            kSecClass as String          : kSecClassGenericPassword,
            kSecAttrAccount as String    : key,
            kSecAttrService as String    : "Bunq",
            kSecAttrAccessible as String : kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String      : Data(token.utf8)
        ]
        
        let status = SecItemAdd(attributes as CFDictionary, nil)
        
        switch status {
        case errSecSuccess:
            return ()
        default:
            let message = SecCopyErrorMessageString(status, nil) as NSString? as String?
            print("Failed to set token \"\(key)\" to keychain , status: \(message ?? "<unknown \(status) code>")")
        }
        return nil
    }
    
    private func generateRSAKeyPair() -> SecKey? {
        let keyPairAttr: [String: Any] = [
            kSecAttrKeyType as String       : kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String : 2048,
        ]

        var error: Unmanaged<CFError>?
        
        guard let privateKey = SecKeyCreateRandomKey(keyPairAttr as CFDictionary, &error) else {
            if let errorDescription = error?.takeRetainedValue() {
                print("Key generation failed with error: \(errorDescription)")
            }
            return nil
        }
        
        return privateKey
    }
    
    private func secKeyToPEM(key: SecKey, kind: String) -> String? {
        var error: Unmanaged<CFError>?
        
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            if let errorDescription = error?.takeRetainedValue() {
                print("Error converting key to PEM format: \(errorDescription)")
            }
            return nil
        }
        let base64EncodedKey = keyData.base64EncodedString()
        let lineLength = 64
        var pemFormattedKey = "-----BEGIN \(kind) KEY-----\n"
        var startIndex = base64EncodedKey.startIndex
        while startIndex < base64EncodedKey.endIndex {
            let endIndex = base64EncodedKey.index(startIndex, offsetBy: lineLength, limitedBy: base64EncodedKey.endIndex) ?? base64EncodedKey.endIndex
            pemFormattedKey += base64EncodedKey[startIndex..<endIndex] + "\n"
            startIndex = endIndex
        }
        pemFormattedKey += "-----END \(kind) KEY-----"
        return pemFormattedKey
    }
    
    private func PEMtoSecKey(_ pem: String, keyClass: CFString) -> SecKey? {
        let base64 = pem.components(separatedBy: .newlines)
            .filter({!$0.isEmpty})
            .dropFirst()
            .dropLast()
            .joined()
        guard let certData = Data(base64Encoded: base64) else {
            print("failed to create Data from base64")
            return nil
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String       : kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String      : keyClass,
        ]

        var error: Unmanaged<CFError>? = nil
        guard let secKey = SecKeyCreateWithData(certData as CFData, attributes as CFDictionary, &error) else {
            print(error.debugDescription)
            return nil
        }
        return secKey
    }
    
    func clearKeychain() {
        for classKey in [kSecClassKey, kSecClassGenericPassword] {
            let attributes: [String: Any] = [
                kSecClass as String: classKey,
            ]
            let status = SecItemDelete(attributes as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                print("Successfuly clear keychain \(classKey)")
            default:
                let message = SecCopyErrorMessageString(status, nil) as NSString? as String?
                print("Failed to clear keychain \(classKey), status: \(message ?? "<unknown \(status) code>")")
            }
        }
        
    }
    
    func clearUserDefaults() {
        if let appGroup = UserDefaults(suiteName: "group.com.escaton.Daily-budget.shared") {
            appGroup.removeObject(forKey: "user-preferences")
            appGroup.removeObject(forKey: "last-balance")
        }
    }
}
