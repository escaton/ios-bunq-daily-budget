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

extension WidgetConfiguration
{
    func contentMarginsDisabledIfAvailable() -> some WidgetConfiguration
    {
        if #available(iOSApplicationExtension 17.0, *)
        {
            return self.contentMarginsDisabled()
        }
        else
        {
            return self
        }
    }
}

struct Daily_budget_widget: Widget {
    let kind: String = "Daily_budget_widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Daily_budget_widgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily budget")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,

            // Add Support to Lock Screen widgets
            .accessoryCircular,
        ])
        .contentMarginsDisabledIfAvailable()
    }
}

extension View {
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, macOSApplicationExtension 14.0, *) {
            return containerBackground(color, for: .widget)
        } else {
            return background(color)
        }
    }
}


struct Daily_budget_widgetEntryView : View {
    var entry: Provider.Entry
    
    @Environment(\.widgetFamily)
    var family
    
    var body: some View {
        if (family == .accessoryCircular) {
            CircularWidgetView(balance: entry.balance)
        } else {
            WidgetBalanceView(balance: entry.balance)
        }
    }
}

struct WidgetBalanceView : View {
    var balance: Balance
    var body: some View {
        VStack(spacing: 0) {
            
            BalanceView(
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
        .widgetBackground(Color(UIColor.systemBackground))
    }
}

// Widget view for `accessoryCircular`
struct CircularWidgetView: View {
    var balance: Balance
    var body: some View {
        Gauge(value: balance.todayLeftPercent) {
            Text("€\(Int(balance.todayLeft))")
                .font(.system(.largeTitle, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetBackground(Color(UIColor.systemBackground))
    }
}


//struct WidgetBalanceView_Previews: PreviewProvider {
//    static var previews: some View {
//        WidgetBalanceView(balance: Balance(
//            date: Date.now,
//            todayLeftPercent: Float(1),
//            todayLeft: 77.5,
//            balance: -300,
//            daysLeft: 28
//        ))
//            .previewContext(WidgetPreviewContext(family: .systemSmall))
//    }
//}

//#Preview("Widget", as: .systemMedium) {
//    Daily_budget_widget()
//} timeline: {
//    BalanceEntry(date: Date.now, balance: Balance(
//        date: Date.now,
//        todayLeftPercent: Float(1),
//        todayLeft: 77.5,
//        balance: -300,
//        daysLeft: 28
//    ))
//}

//struct CircularWidgetView_Preview: PreviewProvider {
//    static var previews: some View {
//        CircularWidgetView(balance: Balance(
//            date: Date.now,
//            todayLeftPercent: Float(0.1),
//            todayLeft: -77.5,
//            balance: -300,
//            daysLeft: 28
//        ))
//            .previewContext(WidgetPreviewContext(family: .accessoryCircular))
//    }
//}
