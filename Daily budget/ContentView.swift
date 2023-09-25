//
//  ContentView.swift
//  Daily budget
//
//  Created by Egor Blinov on 21/08/2023.
//

import SwiftUI
import SwiftyJSON
import WidgetKit

struct ContentView: View {
    @State private var state: ContentState = {
        guard let authorization = BunqService.shared.getAuthorization() else {
            return .nonAuthorized
        }
        guard let userPrefs = BunqService.shared.getUserPreferences() else {
            return .authorized(authorization)
        }
        return .ready(authorization, userPrefs)
    }()
    
    var body: some View {
        WithSettings {
            switch state {
            case .nonAuthorized:
                AuthorizeView { apiKey in
                    Task {
                        do {
                            try await BunqService.shared.setup(apiKey: apiKey)
                            guard let authorization = BunqService.shared.getAuthorization() else {
                                print("failed to get authorization from keychain")
                                return
                            }
                            state = .authorized(authorization)
                        } catch {
                            print("Error \(error)")
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            case .authorized(let authorization):
                SetupViewContainer(authorization: authorization) { account in
                    let userPrefs = UserPreferences(
                        accountId: account.id,
                        accountName: account.description,
                        userId: account.userId
                    )
                    BunqService.shared.storeUserPreferences(userPrefs)
                    state = .ready(authorization, userPrefs)
                }
                .frame(maxHeight: .infinity)
                
            case .ready(let authorization, let userPrefs):
                AccountViewContainer(authorization: authorization, userPreferences: userPrefs)
                    .frame(maxHeight: .infinity)
            }
        } onClearData: {
            BunqService.shared.clearKeychain()
            BunqService.shared.clearUserDefaults()
            state = .nonAuthorized
        }
    }
}

struct WithSettings <Content: View>: View {
    var content: () -> Content
    var onClearData: () -> Void
    init(
        @ViewBuilder content: @escaping () -> Content,
        onClearData: @escaping () -> Void
    ) {
        self.content = content
        self.onClearData = onClearData
    }
    
    @State private var showingSheet = false
    @State private var sheetContentHeight = CGFloat(0)
    @State private var showConfirm = false

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button {
                    showingSheet.toggle()
                } label: {
                    Image(systemName: "gear")
                }
                .padding(20)
                
                .sheet(isPresented: $showingSheet) {
                        VStack {
                            Button {
                                showConfirm.toggle()
                            } label: {
                                Text("Clear data")
                                    .frame(maxWidth: .infinity)
                            }
                            .alert("Are you sure?", isPresented: $showConfirm) {
                                Button("Clear data", role: .destructive) {
                                    onClearData()
                                    showingSheet.toggle()
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                            .tint(.red)
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(20)
                        .padding(.top, 15)
                        .background {
                            GeometryReader { g in
                                Color.clear
                                    .task {
                                        sheetContentHeight = g.size.height
                                    }
                            }
                        }
                        .presentationDetents([.height(sheetContentHeight)])
                        .presentationDragIndicator(.visible)
                    }
            }
    }
}

struct AuthorizeView: View {
    @State private var apiKey: String = ""

    var onStartAuthorization: (_ apiKey: String) -> Void
    
    var body: some View {
        VStack() {
            TextField("Api Key", text: $apiKey)
                .padding(.all, 50)
                .textFieldStyle(.roundedBorder)
            Link("Go to Bunq", destination: URL(string: "https://go.bunq.com/link/developer/apikeys")!)
            .padding()
            Button("Authorize") {
                onStartAuthorization(apiKey)
            }
            .disabled(apiKey == "")
        }
    }
}

struct SetupViewContainer: View {
    var authorization: AuthorizationData
    var onSelectAccount: (_ account: MonetaryAccount) -> Void
    @State private var accounts: [MonetaryAccount]? = nil
    
    var body: some View {
        SetupView(accounts: accounts, onSelectAccount: onSelectAccount)
        .task {
            accounts = await BunqService.shared.accounts(authorization)
        }
    }
}

struct SetupView: View {
    var accounts: [MonetaryAccount]?
    var onSelectAccount: (_ account: MonetaryAccount) -> Void
    
    var body: some View {
        VStack() {
            switch accounts {
            case .none:
                ProgressView()
            case .some(let accounts):
                List {
                    Section {
                        ForEach(accounts) { account in
                            HStack {
                                Text(account.description)
                                Spacer()
                                Text("€ \(account.balance)")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectAccount(account)
                            }
                        }
                    } header: {
                        Text("Select account:")
                            .padding(.top, 50)
                    }
                }
            }
        }
    }
}

struct AccountViewContainer: View {
    @State private var seq = 0
    @State private var balance: Balance? = nil
    
    var authorization: AuthorizationData
    var userPreferences: UserPreferences
    
    var body: some View {
        AccountView(userPreferences: userPreferences, balance: balance) {
            seq += 1
        }
        .task(id: seq) {
            balance = await BunqService.shared.todayBalance(
                authorization,
                userId: userPreferences.userId,
                accountId: userPreferences.accountId
            )
            if let appGroup = UserDefaults(suiteName: "group.com.escaton.Daily-budget.shared"),
               let balance = balance,
               let json = try? JSONEncoder().encode(balance) {
                appGroup.set(json, forKey: "last-balance")
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

struct AccountView: View {
    var userPreferences: UserPreferences
    var balance: Balance?
    var onRefresh: () -> Void
    var body: some View {
        GeometryReader { g in
            ScrollView {
                VStack {
                    switch balance {
                    case .none:
                        ProgressView()
                    case .some(let balance):
                        Link(destination: URL(string: "https://go.bunq.com/link/accounts/\(userPreferences.accountId)")!
                        ) {
                            Text(userPreferences.accountName)
                            Label("", systemImage: "arrow.up.forward.app").labelStyle(.iconOnly)
                        }
                        .font(.title)
                        .padding()
                        BalanceView(
                            todayLeftPercent: balance.todayLeftPercent,
                            todayLeft: balance.todayLeft,
                            balance: balance.balance
                        )
                        .padding()
                        Text("^[\(balance.daysLeft) day](inflect: true) before salary")
                            .padding()
                        
                    }
                }
                .frame(minWidth: g.size.width, minHeight: g.size.height)
            }
            .refreshable {
                onRefresh()
            }
        }
    }
}

struct AuthorizeView_Preview: PreviewProvider {
    static var previews: some View {
        WithSettings {
            AuthorizeView { _ in }
        } onClearData: {}
    }
}

struct SetupView_Preview: PreviewProvider {
    static var previews: some View {
        WithSettings {
            SetupView(accounts: [
                MonetaryAccount(id: "1", userId: "", description: "My Account", balance: "100"),
                MonetaryAccount(id: "2", userId: "", description: "My Account", balance: "100"),
                MonetaryAccount(id: "3", userId: "", description: "My Account", balance: "100"),
                MonetaryAccount(id: "4", userId: "", description: "My Account", balance: "100"),
            ])  { _ in }
        } onClearData: {}
    }
}

struct AccountView_Preview: PreviewProvider {
    static var previews: some View {
        WithSettings {
            AccountView(
                userPreferences: UserPreferences(
                    accountId: "", accountName: "Account", userId: ""
                ),
                balance: Balance(
                    date: Date.now,
                    todayLeftPercent: 0.7,
                    todayLeft: 65,
                    balance: 30,
                    daysLeft: 25
                )
            ) { }
        } onClearData: {}
    }
}

struct SettingsDemo: View {
    @State var text = "text"
    var body: some View {
        WithSettings {
            Text(text)
        } onClearData: {
            text += " closed"
        }
    }
}

struct SettingsDemo_Preview: PreviewProvider {
    static var previews: some View {
        SettingsDemo()
    }
}
