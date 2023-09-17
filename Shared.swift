//
//  Shared.swift
//  Daily budget
//
//  Created by Egor Blinov on 28/08/2023.
//

import Foundation

enum ContentState {
    case nonAuthorized
    case authorized(AuthorizationData)
    case ready(AuthorizationData, UserPreferences)
}
