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
            date: Date.now, todayLeftPercent: 1, todayLeft: 1, totalLeft: 100, balance: 100, daysLeft: 1
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        let entry = BalanceEntry(date: Date(), balance: Balance(
            date: Date.now, todayLeftPercent: 0.7, todayLeft: 62, totalLeft: 100, balance: 100, daysLeft: 1
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
            .accessoryRectangular
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
        } else if (family == .accessoryRectangular) {
            RectWidgetView(balance: entry.balance)
        } else if (family == .systemMedium) {
            MediumWidgetBalanceView(balance: entry.balance)
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
        }
        .widgetBackground(Color(UIColor.systemBackground))
    }
}

struct MediumWidgetBalanceView : View {
    var balance: Balance
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
//                Spacer()
                BalanceView(
                    todayLeftPercent: balance.todayLeftPercent,
                    todayLeft: balance.todayLeft,
                    balance: balance.balance,
                    thickness: 16,
                    widget: true
                )
                Spacer()
                VStack(alignment: .trailing) {
                    HStack {
                        Text("Balance: \(Text("€").font(.system(.title3, design: .rounded)))\(Int(balance.balance))")
                            
                        if (balance.totalLeft == balance.todayLeft) {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                    }
                    Text("^[\(balance.daysLeft) \("day")](inflect: true) left")
                }
                
            }
            .padding(10)
            Stripes()
                .frame(height: 5)
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

// Widget view for `accessoryRectangular`
struct RectWidgetView: View {
    var balance: Balance
    var body: some View {
        VStack(alignment: .leading) {
            Gauge(value: balance.todayLeftPercent) {
                    Text("\(Text("€").font(.system(.callout, design: .rounded)))\(Int(balance.todayLeft))")
                        .font(.callout)
            }
            .gaugeStyle(.accessoryLinearCapacity)
            HStack {
                Text("Balance: \(Text("€").font(.system(.callout, design: .rounded)))\(Int(balance.balance))")
                    .font(.callout)
                    
                if (balance.totalLeft == balance.todayLeft) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                }
            }
            Text("^[\(balance.daysLeft) \("day")](inflect: true) left")
        }
        .widgetBackground(Color(UIColor.systemBackground))
    }
}

@available(iOS 17.0, *)
#Preview("Small", as: .systemSmall, widget: {
    Daily_budget_widget()
}) {
    BalanceEntry(date: Date.now, balance: Balance(
        date: Date.now,
        todayLeftPercent: Float(1),
        todayLeft: 77.5,
        totalLeft: 100,
        balance: -300,
        daysLeft: 28
    ))
}

@available(iOS 17.0, *)
#Preview("Medium", as: .systemMedium, widget: {
    Daily_budget_widget()
}) {
    BalanceEntry(date: Date.now, balance: Balance(
        date: Date.now,
        todayLeftPercent: Float(1),
        todayLeft: 77.5,
        totalLeft: 770.5,
        balance: -30,
        daysLeft: 28
    ))
}

@available(iOS 17.0, *)
#Preview("Circular", as: .accessoryCircular, widget: {
    Daily_budget_widget()
}) {
    BalanceEntry(date: Date.now, balance: Balance(
        date: Date.now,
        todayLeftPercent: Float(1),
        todayLeft: 77.5,
        totalLeft: 100,
        balance: -300,
        daysLeft: 28
    ))
}

@available(iOS 17.0, *)
#Preview("Rect", as: .accessoryRectangular, widget: {
    Daily_budget_widget()
}) {
    BalanceEntry(date: Date.now, balance: Balance(
        date: Date.now,
        todayLeftPercent: Float(1),
        todayLeft: 77.5,
        totalLeft: 100,
        balance: -300,
        daysLeft: 28
    ))
}
