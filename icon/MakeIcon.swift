// 앱 아이콘 생성기: swiftc MakeIcon.swift -o makeicon && ./makeicon <출력폴더>
// macOS 앱 아이콘 규격(1024 캔버스 안 824 스퀘어클, 그림자)에 맞춰 그림.
// 콘셉트: 배터리 건강 — 60% 근처로 '유지'되는 배터리 + 잎(건강) + 유지 구간 표시

import SwiftUI

struct IconView: View {
    var body: some View {
        ZStack {
            // 배경 스퀘어클
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(red: 0.06, green: 0.36, blue: 0.33),
                                            Color(red: 0.10, green: 0.60, blue: 0.47),
                                            Color(red: 0.36, green: 0.84, blue: 0.60)],
                                   startPoint: .bottomLeading, endPoint: .topTrailing)
                )
                .overlay(
                    // 위쪽 은은한 광택
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 22, y: 14)

            // 배터리
            ZStack(alignment: .leading) {
                // 외곽
                RoundedRectangle(cornerRadius: 62, style: .continuous)
                    .strokeBorder(.white, lineWidth: 30)
                    .frame(width: 520, height: 300)
                // 채움 (≈60%)
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.80, green: 1.0, blue: 0.86), Color(red: 0.55, green: 0.95, blue: 0.70)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 270, height: 216)
                    .padding(.leading, 42)
                // 유지 구간 표시(점선) — 60% 위치
                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 8, height: 236)
                    .offset(x: 42 + 270 + 14)
                    .mask(
                        VStack(spacing: 14) { ForEach(0..<9) { _ in Rectangle().frame(height: 14) } }
                            .frame(width: 8, height: 236)
                            .offset(x: 42 + 270 + 14)
                    )
            }
            .overlay(alignment: .trailing) {
                // 단자
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white)
                    .frame(width: 34, height: 110)
                    .offset(x: 40)
            }
            .offset(x: -18, y: 40)

            // 잎 (건강)
            Image(systemName: "leaf.fill")
                .font(.system(size: 210, weight: .regular))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color(red: 0.86, green: 1.0, blue: 0.90)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Color(red: 0.03, green: 0.25, blue: 0.20).opacity(0.45), radius: 10, y: 6)
                .rotationEffect(.degrees(-8))
                .offset(x: 212, y: -192)
        }
        .frame(width: 1024, height: 1024)
    }
}

let app = NSApplication.shared
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
MainActor.assumeIsolated {
let renderer = ImageRenderer(content: IconView())
renderer.scale = 1
guard let cg = renderer.cgImage else { fatalError("render failed") }
let rep = NSBitmapImageRep(cgImage: cg)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_1024.png"))
print("wrote \(out)/icon_1024.png")
}
