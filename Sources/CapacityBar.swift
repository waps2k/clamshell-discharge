// 용량 막대 하나로: 설계 용량(전체 폭) 안에 최대 용량, 그 안에 현재 충전된 용량
//
//  [■■■■■■■■■■■■■■■░░░░░░▒▒▒▒▒▒]
//   현재 충전      남은 공간  열화로 잃은 용량
//   └──── 최대 용량 ────┘
//   └────────── 설계 용량 ──────────┘

import SwiftUI

struct CapacityBar: View {
    let current: Int   // 현재 충전된 용량 (mAh)
    let max: Int       // 현재 최대 용량 (mAh)
    let design: Int    // 설계 용량 (mAh)
    var height: CGFloat = 16
    var showLegend = true

    private var soh: Double { design > 0 ? Double(max) / Double(design) * 100 : 0 }
    private var chargePct: Int { max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0 }
    private var lostPct: Int { Swift.max(0, 100 - Int(soh.rounded())) }
    private var fillColor: Color { chargePct <= 10 ? .red : (chargePct <= 20 ? .orange : .green) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("용량").foregroundStyle(.secondary)
                Spacer()
                Text(current.formatted()).fontWeight(.semibold).monospacedDigit()
                Text("/ \(max.formatted()) mAh").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)

            GeometryReader { geo in
                let w = geo.size.width
                let d = Double(Swift.max(design, 1))
                let wMax = w * CGFloat(Double(Swift.min(max, design)) / d)
                let wCur = w * CGFloat(Double(Swift.min(current, max)) / d)
                ZStack(alignment: .leading) {
                    // 설계 용량 전체 (열화로 잃은 부분은 빗금)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.12))
                    Stripes()
                        .stroke(Color.secondary.opacity(0.28), lineWidth: 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .mask(HStack(spacing: 0) { Color.clear.frame(width: wMax); Color.black })
                    // 최대 용량 (충전 가능한 공간)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(fillColor.opacity(0.22))
                        .frame(width: wMax)
                    // 현재 충전
                    RoundedRectangle(cornerRadius: 5)
                        .fill(fillColor.gradient)
                        .frame(width: wCur)
                    // 최대 용량 경계선
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2, height: height + 6)
                        .offset(x: wMax - 1)
                }
            }
            .frame(height: height)
            .padding(.bottom, 3)

            if showLegend {
                HStack(spacing: 10) {
                    legend(fillColor, "현재 \(chargePct)%")
                    legend(fillColor.opacity(0.3), "최대 \(max.formatted())")
                    legend(Color.secondary.opacity(0.3), "설계 \(design.formatted())")
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                HStack {
                    Text("배터리 성능(SOH) ").foregroundColor(.secondary)
                    + Text(String(format: "%.1f%%", soh)).foregroundColor(soh >= 80 ? Color.primary : Color.orange).fontWeight(.semibold)
                    Spacer()
                    Text("열화로 \(lostPct)% (\((design - max).formatted()) mAh) 감소").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            Text(t).monospacedDigit()
        }
    }
}

/// 대각선 빗금
struct Stripes: Shape {
    var spacing: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.height))
            p.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return p
    }
}
