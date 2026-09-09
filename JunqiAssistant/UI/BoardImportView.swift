import PhotosUI
import SwiftUI
import UIKit

struct BoardImportView: View {
    @EnvironmentObject private var model: AssistantViewModel
    @State private var selectedOwner: BoardOwner = .ours
    @State private var isPickerPresented = false
    @State private var isManualEditorExpanded = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ownerPicker
                    importButtons
                    imageEditor
                    validationCard
                    manualEditor
                    actionButtons
                }
                .padding(16)
            }
            .background(Color(red: 0.95, green: 0.96, blue: 0.98))
            .navigationTitle("棋谱导入")
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $isPickerPresented) {
            BoardImagePicker { image in
                Task {
                    await model.importBoardImage(image, owner: selectedOwner)
                }
            }
        }
    }

    private var ownerPicker: some View {
        Picker("棋谱身份", selection: $selectedOwner) {
            ForEach(BoardOwner.allCases) { owner in
                Text(owner.title).tag(owner)
            }
        }
        .pickerStyle(.segmented)
    }

    private var importButtons: some View {
        HStack(spacing: 10) {
            Button {
                selectedOwner = .ours
                isPickerPresented = true
            } label: {
                Label("导入我方棋谱", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.10, green: 0.35, blue: 0.65))

            Button {
                selectedOwner = .teammate
                isPickerPresented = true
            } label: {
                Label("导入队友棋谱", systemImage: "person.2")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.12, green: 0.52, blue: 0.34))
        }
    }

    @ViewBuilder
    private var imageEditor: some View {
        if let image = currentImage {
            BoardImageEditor(
                image: image,
                record: currentRecord
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("尚未导入\(selectedOwner.title)")
                    .font(.headline)
                Text("导入后原图会显示在这里，点击原图棋位即可修正 OCR。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var validationCard: some View {
        let validation = currentRecord.wrappedValue.validation
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(validation.isValid ? .green : .orange)
                Text("\(selectedOwner.title)校验")
                    .font(.headline)
                Spacer()
                Text(validation.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(validation.isValid ? .green : .orange)
            }

            if !validation.issues.isEmpty {
                Text(validation.issues.prefix(5).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var manualEditor: some View {
        DisclosureGroup(
            "手动编辑棋位",
            isExpanded: $isManualEditorExpanded
        ) {
            BoardEditorGrid(record: currentRecord)
                .padding(.top, 10)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actionButtons: some View {
        HStack {
            Button("清空当前棋谱") {
                model.clearBoardRecord(owner: selectedOwner)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("保存棋盘") {
                model.saveBoardRecords()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.10, green: 0.18, blue: 0.30))
        }
    }

    private var currentRecord: Binding<ImportedBoardRecord> {
        selectedOwner == .ours
            ? $model.oursBoardRecord
            : $model.teammateBoardRecord
    }

    private var currentImage: UIImage? {
        selectedOwner == .ours
            ? model.oursBoardImage
            : model.teammateBoardImage
    }
}

private struct BoardImageEditor: View {
    let image: UIImage
    @Binding var record: ImportedBoardRecord
    @State private var selectedCell: BoardCellSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原图校正")
                .font(.headline)
            Text("点击原图上的棋位即可修改 OCR 结果")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let imageRect = aspectFitRect(
                    imageSize: image.size,
                    containerSize: geometry.size
                )
                let gridRect = gridRect(in: imageRect)
                let cellWidth = gridRect.width / CGFloat(BoardLayout.columns)
                let cellHeight = gridRect.height / CGFloat(BoardLayout.rows)

                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()

                    ForEach(0..<BoardLayout.rows, id: \.self) { row in
                        ForEach(0..<BoardLayout.columns, id: \.self) { col in
                            cellOverlay(
                                row: row,
                                col: col,
                                cellWidth: cellWidth,
                                cellHeight: cellHeight
                            )
                            .frame(
                                width: cellWidth * 0.94,
                                height: cellHeight * 0.90
                            )
                            .position(
                                x: gridRect.minX + (CGFloat(col) + 0.5) * cellWidth,
                                y: gridRect.minY + (CGFloat(row) + 0.5) * cellHeight
                            )
                        }
                    }
                }
            }
            .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $selectedCell) { selection in
            PieceSelectionSheet(
                selection: selection,
                record: $record
            )
        }
    }

    @ViewBuilder
    private func cellOverlay(
        row: Int,
        col: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat
    ) -> some View {
        let key = BoardLayout.key(row: row, col: col)
        let isCamp = BoardLayout.isCamp(row: row, col: col)
        let kind = record.cells[key]

        Button {
            guard !isCamp else { return }
            selectedCell = BoardCellSelection(row: row, col: col)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: max(4, min(cellWidth, cellHeight) * 0.14))
                    .fill(overlayColor(kind: kind, isCamp: isCamp))
                RoundedRectangle(cornerRadius: max(4, min(cellWidth, cellHeight) * 0.14))
                    .stroke(
                        kind == nil ? Color.white.opacity(0.8) : Color.white,
                        lineWidth: kind == nil ? 1 : 2
                    )

                Text(overlayText(kind: kind, isCamp: isCamp))
                    .font(.system(
                        size: max(8, min(cellWidth, cellHeight) * 0.42),
                        weight: .bold
                    ))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCamp)
    }

    private func overlayText(kind: PieceKind?, isCamp: Bool) -> String {
        if isCamp { return "营" }
        return kind?.shortName ?? "+"
    }

    private func overlayColor(kind: PieceKind?, isCamp: Bool) -> Color {
        if isCamp {
            return Color.black.opacity(0.52)
        }
        guard kind != nil else {
            return Color.black.opacity(0.20)
        }
        switch record.owner {
        case .ours:
            return Color(red: 0.12, green: 0.38, blue: 0.72).opacity(0.88)
        case .teammate:
            return Color(red: 0.10, green: 0.54, blue: 0.34).opacity(0.88)
        }
    }

    private func gridRect(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + BoardLayout.imageGridRect.minX * imageRect.width,
            y: imageRect.minY + BoardLayout.imageGridRect.minY * imageRect.height,
            width: BoardLayout.imageGridRect.width * imageRect.width,
            height: BoardLayout.imageGridRect.height * imageRect.height
        )
    }

    private func aspectFitRect(
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }

        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct BoardCellSelection: Identifiable {
    var row: Int
    var col: Int

    var id: String { BoardLayout.key(row: row, col: col) }
}

private struct PieceSelectionSheet: View {
    let selection: BoardCellSelection
    @Binding var record: ImportedBoardRecord
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    selectionButton(title: "空", kind: nil)
                    ForEach(PieceKind.allCases) { kind in
                        selectionButton(title: kind.name, kind: kind)
                    }
                }
                .padding(16)
            }
            .navigationTitle("\(selection.row + 1)行\(selection.col + 1)列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func selectionButton(title: String, kind: PieceKind?) -> some View {
        Button {
            let key = BoardLayout.key(row: selection.row, col: selection.col)
            if let kind {
                record.cells[key] = kind
            } else {
                record.cells.removeValue(forKey: key)
            }
            record.updatedAt = Date()
            dismiss()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color(red: 0.93, green: 0.95, blue: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct BoardEditorGrid: View {
    @Binding var record: ImportedBoardRecord

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 5),
        count: 5
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(0..<BoardLayout.rows, id: \.self) { row in
                ForEach(0..<BoardLayout.columns, id: \.self) { col in
                    if BoardLayout.isCamp(row: row, col: col) {
                        Text("营")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.30, green: 0.38, blue: 0.34))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(Color(red: 0.78, green: 0.84, blue: 0.80))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    } else {
                        BoardCellMenu(
                            kind: record.cells[BoardLayout.key(row: row, col: col)],
                            owner: record.owner
                        ) { kind in
                            let key = BoardLayout.key(row: row, col: col)
                            if let kind {
                                record.cells[key] = kind
                            } else {
                                record.cells.removeValue(forKey: key)
                            }
                            record.updatedAt = Date()
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(Color(red: 0.91, green: 0.94, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct BoardCellMenu: View {
    let kind: PieceKind?
    let owner: BoardOwner
    let onSelect: (PieceKind?) -> Void

    var body: some View {
        Menu {
            Button("空") {
                onSelect(nil)
            }

            ForEach(PieceKind.allCases) { piece in
                Button(piece.name) {
                    onSelect(piece)
                }
            }
        } label: {
            Text(kind?.shortName ?? "空")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(kind == nil ? Color.secondary : .white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(cellColor)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var cellColor: Color {
        guard kind != nil else {
            return Color.white
        }
        switch owner {
        case .ours:
            return Color(red: 0.12, green: 0.38, blue: 0.72)
        case .teammate:
            return Color(red: 0.10, green: 0.54, blue: 0.34)
        }
    }
}

private struct BoardImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImage: (UIImage) -> Void

        init(onImage: @escaping (UIImage) -> Void) {
            self.onImage = onImage
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                return
            }

            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async {
                    self?.onImage(image)
                }
            }
        }
    }
}
