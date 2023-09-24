//
//  BalanceView.swift
//  Daily budget
//
//  Created by Egor Blinov on 28/08/2023.
//

import SwiftUI

extension Color {
    func adjust(hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, opacity: CGFloat = 1) -> Color {
        let color = UIColor(self)
        var currentHue: CGFloat = 0
        var currentSaturation: CGFloat = 0
        var currentBrigthness: CGFloat = 0
        var currentOpacity: CGFloat = 0

        if color.getHue(&currentHue, saturation: &currentSaturation, brightness: &currentBrigthness, alpha: &currentOpacity) {
            return Color(hue: currentHue + hue, saturation: currentSaturation + saturation, brightness: currentBrigthness + brightness, opacity: currentOpacity + opacity)
        }
        return self
    }
}

struct BalanceView: View {
    var todayLeftPercent: Float
    var todayLeft: Float
    var balance: Float
    var thickness: Int
    var widget: Bool
    @State private var animationEnabled: Bool
    
    init(
        todayLeftPercent: Float,
        todayLeft: Float,
        balance: Float,
        thickness: Int = 20,
        widget: Bool = false
    ) {
        self.todayLeftPercent = todayLeftPercent
        self.todayLeft = todayLeft
        self.balance = balance
        self.thickness = thickness
        self.widget = widget
        self.animationEnabled = widget ? true : false
    }

    var body: some View {
        let strokeStyle = StrokeStyle(lineWidth: CGFloat(thickness))
        let startColor = Color(hue: 0.375, saturation: 0.738, brightness: 0.6)
        let endColor = Color(hue: 0.375, saturation: 0.738, brightness: 0.8)
        VStack {
            ZStack {
                ZStack {
                    Circle()
                        .stroke(
                            Color(UIColor.systemGray5),
                            style: strokeStyle
                        )
                    
                    GeometryReader { geo in
                        Circle()
                            .fill(startColor)
                            .frame(width: strokeStyle.lineWidth, height: strokeStyle.lineWidth)
                            .position(x: geo.size.width/2, y: 0)
                            .rotationEffect(.degrees(90))
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 0)
                            .clipShape(
                                Circle()
                                    .rotation(.degrees(-89))
                                    .trim(from: 0, to: 0.25)
                                    .stroke(style: strokeStyle)
                            )
                    }
                    Circle()
                        .trim(from: -0, to: animationEnabled ? CGFloat(todayLeftPercent) : 0)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [startColor, endColor]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: strokeStyle
                        )
                    GeometryReader { geo in
                        Circle()
                            .fill(Color(hue: 0.375, saturation: 0.738, brightness: 0.6 + 0.2*Double(todayLeftPercent)))
                            .frame(width: strokeStyle.lineWidth, height: strokeStyle.lineWidth)
                            .position(x: geo.size.width/2, y: 0)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 0)
                            .clipShape(
                                Circle()
                                    .rotation(.degrees(-91))
                                    .trim(from: 0, to: 0.25)
                                    .stroke(style: strokeStyle)
                            )
                    }
                    .rotationEffect(.degrees(animationEnabled ? Double(todayLeftPercent) * 360 + 90 : 90))
                }
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: todayLeftPercent)
                .padding(strokeStyle.lineWidth/2)
                Text("")
                    .modifier(
                        AnimatableNumberModifier(number: animationEnabled ? todayLeft : 0, isWidget: widget)
                    )
                    .animation(.easeInOut, value: todayLeft)
                GeometryReader { geo in
                    Text(String(format: "Balance: €%.0f", balance))
                        .font(.system(size: 40, design: .rounded))
                        .scaledToFit()
                        .minimumScaleFactor(0.01)
                        .padding(.bottom, 10)
                        .position(x: geo.size.width/2,y: geo.size.height/4*3)
                        .frame(width: geo.size.width*0.5-strokeStyle.lineWidth*2)
                        .opacity(widget ? 0 : 1)
                }
                
            }
            .aspectRatio(1, contentMode: .fit)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1)) {
                    animationEnabled = true
                }
            }
        }
    }
}

struct AnimatableNumberModifier: AnimatableModifier {
    var number: Float
    var isWidget: Bool
    
    @State private var wordHeight = CGFloat(0)
    
    var animatableData: Float {
        get { number }
        set { number = newValue }
    }
    
    private struct SizePreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = .zero
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = min(value, nextValue())
        }
    }
    
    func body(content: Content) -> some View {
        let (whole, fraction) = modf(number)
        let wholeString = "€\(Int(whole)),"
        let fractionString = String(format: "%.2f", abs(fraction)).dropFirst(2)
        
        VStack {
            if (isWidget) {
                (
                    Text(wholeString)
                        .font(.system(size: 40, design: .rounded))
                    +
                    Text(fractionString)
                        .font(.system(size: 20, design: .rounded))
                        .baselineOffset(wordHeight*0.3)
                    
                )
                .background {
                    GeometryReader { g in
                        Color.clear
                            .preference(key: SizePreferenceKey.self, value: g.size.height)
                    }
                }
                .padding(20)
            } else {
                (
                    Text(wholeString)
                        .font(.system(size: 80, design: .rounded))
                    +
                    Text(fractionString)
                        .font(.system(size: 40, design: .rounded))
                        .baselineOffset(wordHeight*0.3)
                    
                    
                )
                .background {
                    GeometryReader { g in
                        Color.clear
                            .preference(key: SizePreferenceKey.self, value: g.size.height)
                    }
                }
                .padding(30)
            }
        }
        .onPreferenceChange(SizePreferenceKey.self, perform: { wordHeight = $0 })
        
        .scaledToFit()
        .lineLimit(1)
        .minimumScaleFactor(0.01)
        
    }
}

struct Stripes: View {
    private var colors = [
        Color(red: 35/255, green: 134/255, blue: 71/255),
        Color(red: 47/255, green: 155/255, blue: 71/255),
        Color(red: 98/255, green: 182/255, blue: 79/255),
        Color(red: 137/255, green: 204/255, blue: 83/255),
        Color(red: 61/255, green: 184/255, blue: 173/255),
        Color(red: 51/255, green: 148/255, blue: 215/255),
        Color(red: 40/255, green: 114/255, blue: 188/255),
        Color(red: 29/255, green: 92/255, blue: 132/255),
        Color(red: 153/255, green: 50/255, blue: 51/255),
        Color(red: 225/255, green: 48/255, blue: 48/255),
        Color(red: 255/255, green: 120/255, blue: 25/255),
        Color(red: 245/255, green: 200/255, blue: 54/255)
    ]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(colors, id: \.self) { color in
                Rectangle()
                    .fill(color)
                    .ignoresSafeArea()
            }
        }
    }
}

struct BalanceView_Preveview: PreviewProvider {
    static var previews: some View {
        let left = Float(80.01)
        ZStack {
            BalanceView(
                todayLeftPercent: left/80,
                todayLeft: 100,
                balance: -300
            )
        }
    }
}

struct Stripes_Preveview: PreviewProvider {
    static var previews: some View {
        VStack {
            Stripes()
        }
    }
}

