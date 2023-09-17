//
//  Daily_budget_widget.swift
//  Daily budget widget
//
//  Created by Egor Blinov on 26/08/2023.
//

import WidgetKit
import SwiftUI
import Intents

struct Provider: TimelineProvider {
    typealias Entry = BalanceEntry
    
    func placeholder(in context: Context) -> Entry {
        BalanceEntry(date: Date(), balance: Balance(
            date: Date.now, todayLeftPercent: 1, todayLeft: 1, balance: 100, daysLeft: 1
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        let entry = BalanceEntry(date: Date(), balance: Balance(
            date: Date.now, todayLeftPercent: 0.7, todayLeft: 62, balance: 100, daysLeft: 1
        ))
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            guard let authorization = BunqService.shared.getAuthorization() else {
                print("Failed to get autorization")
                return
            }
            guard let userPrefs = BunqService.shared.getUserPreferences() else {
                print("Failed to get user preferences")
                return
            }
            
            var balance: Balance? = nil
            if let lastBalance = BunqService.shared.getLastBalance(),
               lastBalance.date > Calendar.current.date(byAdding: .minute, value: -15, to: Date.now)! {
                print("reuse cached balance")
                balance = lastBalance
            } else {
                guard let newBalance = await BunqService.shared.todayBalance(
                    authorization,
                    userId: userPrefs.userId,
                    accountId: userPrefs.accountId
                ) else {
                    print("Failed to get balance")
                    return
                }
                
                balance = newBalance
                
                BunqService.shared.storeLastBalance(newBalance)
            }
            
            guard let balance = balance else {
                print("balance is unavailable")
                return
            }
            
            let entry = BalanceEntry(date: Date(), balance: balance)
            
            let nextUpdate = Calendar.current.date(
                byAdding: DateComponents(minute: 15),
                to: Date()
            )!
            
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            completion(timeline)
        }
    }
}

struct BalanceEntry: TimelineEntry {
    let date: Date
    let balance: Balance
}

struct Daily_budget_widget: Widget {
    let kind: String = "Daily_budget_widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Daily_budget_widgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily budget")
    }
}

struct Daily_budget_widgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        WidgetBalanceView(balance: entry.balance)
    }
}

struct WidgetBalanceView : View {
    var balance: Balance
    var body: some View {
        VStack(spacing: 0) {
            
            BalanceView(
                accountId: "",
                accountName: "Empty",
                todayLeftPercent: balance.todayLeftPercent,
                todayLeft: balance.todayLeft,
                balance: balance.balance,
                thickness: 16,
                widget: true
            )
            .padding(10)
            Stripes()
                .frame(height: 5)
        }.overlay(alignment: .bottomTrailing) {
            Text(Date(), style: .relative)
                .font(.system(size: 10))
                .padding(8)
        }
    }
}

class RelativeMinutesDateFormatter : Formatter {
    open override func string(for obj: Any?) -> String? {
        guard let date = obj as? Date else {
            return nil
        }
        let minutes = Int(date.timeIntervalSince(.now) / 60)
        return "\(minutes)m"
    }
}


struct WidgetBalanceView_Previews: PreviewProvider {
    static var previews: some View {
        WidgetBalanceView(balance: Balance(
            date: Date.now,
            todayLeftPercent: Float(1),
            todayLeft: 77.5,
            balance: -300,
            daysLeft: 28
        ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
