import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AssistantViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    pipCard
                    ocrCard
                    inferenceCard
                    stepsCard
                }
                .padding(18)
            }
            .background(Color(red: 0.95, green: 0.96, blue: 0.98))
            .navigationTitle("四国军棋助手")
        }
        .navigationViewStyle(.stack)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(model.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(model.statusText)
                    .font(.headline)
                Spacer()
                Text(model.stepText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(model.isRunning ? "重新启动" : "启动辅助") {
                    model.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.10, green: 0.18, blue: 0.30))

                Button("停止") {
                    model.stop()
                }
                .buttonStyle(.bordered)
                .disabled(!model.isRunning)
            }
        }
        .cardStyle()
    }

    private var pipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("画中画情报")
                    .font(.headline)
                Spacer()
                Text(model.pip.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PiPPreviewRepresentable(view: model.pip.previewView)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .cardStyle()
    }

    private var ocrCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OCR 识别")
                .font(.headline)
            Text("已识别棋子：\(model.knownPiecesText)")
                .font(.subheadline)
            Text(model.ocrText.isEmpty ? "暂无识别文字" : model.ocrText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(8)
        }
        .cardStyle()
    }

    private var inferenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("候选情报")
                .font(.headline)
            Text(model.inferenceText)
                .font(.subheadline)
                .lineSpacing(4)
        }
        .cardStyle()
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("使用顺序")
                .font(.headline)
            Text("1. 点击“启动辅助”，确认画中画出现。\n2. 切到微信小游戏。\n3. 从控制中心启动系统录屏并选择“军棋助手”。\n4. 保持录屏运行，画中画会自动更新。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

private struct PiPPreviewRepresentable: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
    }
}
