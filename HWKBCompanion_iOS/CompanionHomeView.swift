import Combine
import Accessibility
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum ExpandedKeymapLayer: String, CaseIterable, Identifiable {
    case letters
    case symbols1
    case symbols2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .symbols1:
            return "SYM1"
        case .symbols2:
            return "SYM2"
        case .letters:
            return "ABC"
        }
    }
}

private extension ExpandedKeymapLayer {
    var navigationLayer: HWKKeymapEditorExpandedLayer {
        switch self {
        case .symbols1, .symbols2:
            return .symbols
        case .letters:
            return .letters
        }
    }

    var surface: KeyboardRowSurface {
        switch self {
        case .symbols1:
            return .symbols1
        case .symbols2:
            return .symbols2
        case .letters:
            return .letters
        }
    }
}

private enum KeyboardEditorSurface: String, CaseIterable, Identifiable {
    case mainRow
    case symbols1
    case symbols2
    case letters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mainRow:
            return "Main Row"
        case .symbols1:
            return "SYM1"
        case .symbols2:
            return "SYM2"
        case .letters:
            return "ABC"
        }
    }
}

private extension KeyboardEditorSurface {
    var rowSurface: KeyboardRowSurface {
        switch self {
        case .mainRow:
            return .mainRow
        case .symbols1:
            return .symbols1
        case .symbols2:
            return .symbols2
        case .letters:
            return .letters
        }
    }

    var navigationSurface: HWKKeymapEditorSurface {
        switch self {
        case .mainRow:
            return .mainRow
        case .symbols1, .symbols2:
            return .symbols
        case .letters:
            return .letters
        }
    }
}

private struct KeyboardEditorLayerOption: Identifiable, Hashable {
    static let mainRowID = "mainRow"
    static let symbols1ID = "symbols1"
    static let symbols2ID = "symbols2"
    static let lettersID = "letters"
    static let customIDPrefix = "custom:"

    var id: String
    var title: String
    var systemImage: String
    var customLayerID: UUID?
}

private struct AdditionalLayerHoldEditorSheet: View {
    let layer: KeyboardCustomLayer
    let onSave: (_ title: String, _ iconSystemName: String) -> Void
    let onConvert: (_ style: KeyboardCustomLayerStyle, _ title: String, _ iconSystemName: String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var layerName: String
    @State private var selectedIconSystemName: String?

    init(
        layer: KeyboardCustomLayer,
        onSave: @escaping (_ title: String, _ iconSystemName: String) -> Void,
        onConvert: @escaping (_ style: KeyboardCustomLayerStyle, _ title: String, _ iconSystemName: String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.layer = layer
        self.onSave = onSave
        self.onConvert = onConvert
        self.onDelete = onDelete
        _layerName = State(initialValue: layer.title)
        _selectedIconSystemName = State(initialValue: layer.iconSystemName)
    }

    private var conversionTarget: KeyboardCustomLayerStyle {
        layer.style == .row ? .expanded : .row
    }

    private var conversionTitle: String {
        conversionTarget == .row ? "Convert to Row" : "Convert to Expanded"
    }

    private var resolvedIconSystemName: String {
        selectedIconSystemName ?? layer.iconSystemName
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                TextField("Layer Name", text: $layerName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(saveAndDismiss)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Layer Icon")
                        .font(.subheadline.weight(.semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(KeyboardCustomLayer.iconSystemNames, id: \.self) { systemName in
                                let isSelected = resolvedIconSystemName == systemName

                                Button {
                                    withAnimation(.snappy) {
                                        selectedIconSystemName = systemName
                                    }
                                } label: {
                                    Image(systemName: systemName)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .frame(width: 54, height: 54)
                                        .background(
                                            Circle()
                                                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.14))
                                        )
                                        .scaleEffect(isSelected ? 1 : 0.88)
                                }
                                .buttonStyle(.plain)
                                .id(systemName)
                                .accessibilityLabel(Self.iconChoiceLabel(systemName))
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 2)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $selectedIconSystemName, anchor: .center)
                }

                VStack(spacing: 10) {
                    Button {
                        onConvert(conversionTarget, layerName, resolvedIconSystemName)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: conversionTarget == .row ? "rectangle.split.1x2" : "square.grid.3x3")
                            Text(conversionTitle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete Layer", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Additional Layer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: saveAndDismiss)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func saveAndDismiss() {
        onSave(layerName, resolvedIconSystemName)
        dismiss()
    }

    private static func iconChoiceLabel(_ systemName: String) -> String {
        switch systemName {
        case "square.stack.3d.up": "Stack"
        case "curlybraces": "Code"
        case "command": "Command"
        case "number": "Numbers"
        case "textformat": "Text"
        case "keyboard": "Keyboard"
        case "sparkles": "Sparkles"
        case "bolt": "Fast"
        default:
            systemName
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }
}

private struct KeyEditorChoice: Identifiable {
    var id: String { token }
    let token: String
    let title: String
    let systemImage: String?
}

private struct KeyEditorSection: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let choices: [KeyEditorChoice]
}

private struct KeyEditorItem: Identifiable {
    let id = UUID()
    let title: String
    let actionTitle: String
    let initialValue: String
}

private enum KeyEditorModeChangeAction {
    case save(String)
    case delete
}

private struct KeyEditorModeChangeConfirmation: Identifiable {
    let id = UUID()
    let action: KeyEditorModeChangeAction
    let warning: String
}

private struct KeyEditorSheet: View {
    let item: KeyEditorItem
    let sections: [KeyEditorSection]
    let warningForSave: (_ value: String) -> String?
    let warningForDelete: () -> String?
    let onSave: (_ value: String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keyValue: String
    @State private var selectedSectionID: String
    @State private var searchText = ""
    @State private var pendingModeChangeConfirmation: KeyEditorModeChangeConfirmation?

    private enum Field: Hashable { case value, search }
    @FocusState private var focusedField: Field?
    @State private var sheetDetent: PresentationDetent = .large

    init(
        item: KeyEditorItem,
        sections: [KeyEditorSection],
        warningForSave: @escaping (_ value: String) -> String?,
        warningForDelete: @escaping () -> String?,
        onSave: @escaping (_ value: String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.sections = sections
        self.warningForSave = warningForSave
        self.warningForDelete = warningForDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _keyValue = State(initialValue: item.initialValue)
        _selectedSectionID = State(
            initialValue: sections.first(where: { $0.title == "Smart Picks" })?.id
                ?? sections.first?.id
                ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.actionTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Key Value", text: keyValueBinding)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .value)
                        .submitLabel(.done)
                        .onSubmit(saveAndDismiss)
                        .accessibilityIdentifier("key.editor.value")

                    HStack {
                        Text("Key Choices").font(.headline)
                        Spacer()
                        Menu {
                            ForEach(sections) { section in
                                Button {
                                    searchText = ""
                                    selectedSectionID = section.id
                                    focusedField = nil
                                } label: {
                                    if selectedSectionID == section.id {
                                        Label(section.title, systemImage: "checkmark")
                                    } else {
                                        Text(section.title)
                                    }
                                }
                            }
                        } label: {
                            Label(selectedSectionTitle, systemImage: "line.3.horizontal.decrease")
                                .font(.subheadline)
                        }
                        .accessibilityIdentifier("key.editor.category")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search Key Choices", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .search)
                            .accessibilityIdentifier("key.editor.search")
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel("Clear Search")
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    HStack(alignment: .firstTextBaseline) {
                        Text(searchText.isEmpty ? selectedSectionDetail : "Matches across all categories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(visibleChoices.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if visibleChoices.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(visibleChoices) { choice in
                                keyChoiceButton(choice)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        keyValue = ""
                        focusedField = nil
                    } label: {
                        Label("Clear", systemImage: "xmark.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("key.editor.clear")

                    Button(role: .destructive, action: requestDelete) {
                        Label("Delete Key", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("key.editor.delete")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Key Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAndDismiss)
                        .accessibilityIdentifier("key.editor.save")
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .onChange(of: focusedField) { _, field in
            if field != nil { sheetDetent = .large }
        }
        .alert(item: $pendingModeChangeConfirmation) { confirmation in
            Alert(
                title: Text("Mode Change Key"),
                message: Text(confirmation.warning),
                primaryButton: .destructive(Text(confirmation.action.buttonTitle)) {
                    applyModeChangeConfirmation(confirmation)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var selectedSection: KeyEditorSection? {
        sections.first(where: { $0.id == selectedSectionID }) ?? sections.first
    }

    private var selectedSectionTitle: String {
        selectedSection?.title ?? "Key Choices"
    }

    private var selectedSectionDetail: String {
        selectedSection?.detail ?? "Choose a value for this key."
    }

    private var visibleChoices: [KeyEditorChoice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return selectedSection?.choices ?? [] }

        var seen = Set<String>()
        return sections
            .flatMap(\.choices)
            .filter { choice in
                guard seen.insert(choice.token).inserted else { return false }
                return choice.token.localizedCaseInsensitiveContains(query)
                    || choice.title.localizedCaseInsensitiveContains(query)
            }
    }

    private func keyChoiceButton(_ choice: KeyEditorChoice) -> some View {
        let isSelected = keyValue == choice.token
        return Button {
            keyValue = choice.token
            focusedField = nil
        } label: {
            VStack(spacing: 4) {
                if let systemImage = choice.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(choice.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var keyValueBinding: Binding<String> {
        Binding(
            get: { keyValue },
            set: { value in
                keyValue = value
            }
        )
    }

    private func saveAndDismiss() {
        if let warning = warningForSave(keyValue) {
            pendingModeChangeConfirmation = KeyEditorModeChangeConfirmation(
                action: .save(keyValue),
                warning: warning
            )
            return
        }

        onSave(keyValue)
        dismiss()
    }

    private func requestDelete() {
        if let warning = warningForDelete() {
            pendingModeChangeConfirmation = KeyEditorModeChangeConfirmation(
                action: .delete,
                warning: warning
            )
            return
        }

        onDelete()
        dismiss()
    }

    private func applyModeChangeConfirmation(_ confirmation: KeyEditorModeChangeConfirmation) {
        switch confirmation.action {
        case let .save(value):
            onSave(value)
        case .delete:
            onDelete()
        }
        dismiss()
    }
}

private extension KeyEditorModeChangeAction {
    var buttonTitle: String {
        switch self {
        case .save:
            return "Replace Key"
        case .delete:
            return "Delete Key"
        }
    }
}

private struct CustomLayerEditorKeySelection: Equatable {
    var layerID: UUID
    var rowID: UUID
    var keyID: UUID
    var rowIndex: Int
    var keyIndex: Int
}

private enum KeyboardEditActionMode: String, CaseIterable, Identifiable {
    case tap
    case hold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tap:
            return "Tap"
        case .hold:
            return "Hold"
        }
    }
}

private extension KeyboardEditActionMode {
    var navigationMode: HWKKeymapEditorActionMode {
        switch self {
        case .tap:
            return .tap
        case .hold:
            return .hold
        }
    }

    init(_ mode: HWKKeymapEditorActionMode) {
        switch mode {
        case .tap:
            self = .tap
        case .hold:
            self = .hold
        }
    }
}

private struct KeyBlockLibrarySection: Identifiable {
    let title: String
    let detail: String
    let tokens: [String]

    var id: String { title }
}

private struct KeyTokenVisual {
    let text: String?
    let icon: String?
    let label: String?
}

private struct AutocorrectSlotSelection: Identifiable {
    let id: Int
}

private struct AutocorrectTaughtRuleSelection: Identifiable {
    let id: UUID
}

private struct AutocorrectUndoSnapshot {
    let customTextRules: [HWKCustomTextRule]
    let logicBlocks: [KeyboardAutocorrectLogicBlock]
    let logicLanes: [KeyboardAutocorrectLogicLane]
    let recipe: KeyboardAutocorrectLogicRecipe
    let message: String
}

private enum AutocorrectBehaviorOption: String, CaseIterable, Identifiable {
    case off
    case careful
    case balanced
    case savedWordsFirst
    case dictionaryFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "None"
        case .careful:
            return "Careful"
        case .balanced:
            return "Balanced"
        case .savedWordsFirst:
            return "Saved words"
        case .dictionaryFirst:
            return "Dictionary"
        }
    }

    var recipe: KeyboardAutocorrectLogicRecipe? {
        switch self {
        case .off:
            return nil
        case .careful:
            return .strict
        case .balanced:
            return .balanced
        case .savedWordsFirst:
            return .savedWordsFirst
        case .dictionaryFirst:
            return .dictionaryFirst
        }
    }

    var caption: String {
        switch self {
        case .off:
            return "Nothing is corrected automatically."
        case .careful:
            return "Corrects only when very sure."
        case .balanced:
            return "Saved words and dictionary together."
        case .savedWordsFirst:
            return "Trusts your saved words first."
        case .dictionaryFirst:
            return "Trusts the dictionary first."
        }
    }
}

private struct StaticPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct KeyboardEditorLayerSegmentGestureOverlay: UIViewRepresentable {
    var segmentCount: Int
    var tapHandler: (Int) -> Void
    var longPressHandler: (Int) -> Void
    var scrubHandler: (CGPoint, CGSize, UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let longPressRecognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressRecognizer.minimumPressDuration = 0.3
        configure(recognizer: longPressRecognizer)

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        configure(recognizer: tapRecognizer)
        tapRecognizer.require(toFail: longPressRecognizer)

        let panRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        configure(recognizer: panRecognizer)
        tapRecognizer.require(toFail: panRecognizer)

        view.addGestureRecognizer(longPressRecognizer)
        view.addGestureRecognizer(tapRecognizer)
        view.addGestureRecognizer(panRecognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.segmentCount = segmentCount
        context.coordinator.tapHandler = tapHandler
        context.coordinator.longPressHandler = longPressHandler
        context.coordinator.scrubHandler = scrubHandler
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            segmentCount: segmentCount,
            tapHandler: tapHandler,
            longPressHandler: longPressHandler,
            scrubHandler: scrubHandler
        )
    }

    private func configure(recognizer: UIGestureRecognizer) {
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
    }

    final class Coordinator: NSObject {
        var segmentCount: Int
        var tapHandler: (Int) -> Void
        var longPressHandler: (Int) -> Void
        var scrubHandler: (CGPoint, CGSize, UIGestureRecognizer.State) -> Void

        init(
            segmentCount: Int,
            tapHandler: @escaping (Int) -> Void,
            longPressHandler: @escaping (Int) -> Void,
            scrubHandler: @escaping (CGPoint, CGSize, UIGestureRecognizer.State) -> Void
        ) {
            self.segmentCount = segmentCount
            self.tapHandler = tapHandler
            self.longPressHandler = longPressHandler
            self.scrubHandler = scrubHandler
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let index = segmentIndex(for: recognizer) else { return }
            tapHandler(index)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let index = segmentIndex(for: recognizer) else { return }
            longPressHandler(index)
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view,
                  view.bounds.width > 0 else { return }
            scrubHandler(recognizer.location(in: view), view.bounds.size, recognizer.state)
        }

        private func segmentIndex(for recognizer: UIGestureRecognizer) -> Int? {
            guard segmentCount > 0,
                  let view = recognizer.view,
                  view.bounds.width > 0 else { return nil }
            let xPosition = recognizer.location(in: view).x
            let rawIndex = Int((xPosition / view.bounds.width) * CGFloat(segmentCount))
            return min(max(rawIndex, 0), segmentCount - 1)
        }
    }
}

private struct KeyboardEditorAdditionalLayerScrubObserver: UIViewRepresentable {
    var itemCount: Int
    var scrubHandler: (CGPoint, CGSize, UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        context.coordinator.itemCount = itemCount
        context.coordinator.scrubHandler = scrubHandler
        uiView.attachRecognizerToWindow()
    }

    static func dismantleUIView(_ uiView: ObserverView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(itemCount: itemCount, scrubHandler: scrubHandler)
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachRecognizerToWindow()
        }

        func attachRecognizerToWindow() {
            guard let window else { return }
            coordinator?.attach(to: window, coordinateView: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var itemCount: Int
        var scrubHandler: (CGPoint, CGSize, UIGestureRecognizer.State) -> Void
        private weak var observedView: UIView?
        private weak var coordinateView: UIView?
        private var isTrackingGrid = false
        private lazy var recognizer: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        init(itemCount: Int, scrubHandler: @escaping (CGPoint, CGSize, UIGestureRecognizer.State) -> Void) {
            self.itemCount = itemCount
            self.scrubHandler = scrubHandler
        }

        func attach(to view: UIView, coordinateView: UIView) {
            guard observedView !== view else { return }
            detach()
            observedView = view
            self.coordinateView = coordinateView
            view.addGestureRecognizer(recognizer)
        }

        func detach() {
            observedView?.removeGestureRecognizer(recognizer)
            observedView = nil
            coordinateView = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard itemCount > 1, let coordinateView, coordinateView.bounds.width > 0 else { return }
            let point = recognizer.location(in: coordinateView)
            if recognizer.state == .began {
                isTrackingGrid = coordinateView.bounds.contains(point)
            }
            guard isTrackingGrid else { return }
            scrubHandler(point, coordinateView.bounds.size, recognizer.state)
            if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
                isTrackingGrid = false
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

private protocol SettingsModeOption: Hashable, Identifiable {
    var title: String { get }
    var detail: String { get }
}

private enum SettingsMode: String, CaseIterable, SettingsModeOption {
    case standardSoftwareKeyboard
    case standardHardwareKeyboard
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standardSoftwareKeyboard: return "Software"
        case .standardHardwareKeyboard: return "Hardware"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .standardSoftwareKeyboard:
            return "Software defaults for suggestions, keyboard open, and hold timing."
        case .standardHardwareKeyboard:
            return "Hardware defaults for suggestions, keyboard open, and hold timing."
        case .custom:
            return "Open detailed suggestion, launch, and hold controls below."
        }
    }
}

private enum AutocorrectWorkflowChip: String, CaseIterable, Identifiable {
    case autocorrect
    case ranking
    case autocomplete
    case clickToFix
    case rolodex
    case clipboard
    case punctuation
    case caps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autocorrect: return "Autocorrect"
        case .ranking: return "Ranking"
        case .autocomplete: return "Complete"
        case .clickToFix: return "Fix"
        case .rolodex: return "Rolodex"
        case .clipboard: return "Clipboard"
        case .punctuation: return "Period"
        case .caps: return "Caps"
        }
    }

    var systemImage: String {
        switch self {
        case .autocorrect: return "wand.and.stars"
        case .ranking: return "arrow.up.arrow.down"
        case .autocomplete: return "text.append"
        case .clickToFix: return "cursorarrow.click"
        case .rolodex: return "rectangle.stack"
        case .clipboard: return "doc.on.clipboard"
        case .punctuation: return "period"
        case .caps: return "textformat.size"
        }
    }
}

#if HWC_INTERNAL_BUILD
private enum HardwareCalibrationProfile: String, CaseIterable, Identifiable {
    case balanced
    case navigationSafe
    case universal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .navigationSafe:
            return "Nav Safe"
        case .universal:
            return "Universal"
        }
    }

    var detail: String {
        switch self {
        case .balanced:
            return "Use the standard setup when letters, delete, and arrows behave."
        case .navigationSafe:
            return "Keep the wider key-command path on for boards that lose arrows, tab, or modifiers."
        case .universal:
            return "Use broader compatibility and slower hold timing for unusual boards."
        }
    }
}

private enum HardwareCalibrationScanPhase: String {
    case idle
    case raw
    case readyForLive
    case live
    case complete

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .raw:
            return "App Check"
        case .readyForLive:
            return "Ready For Keyboard"
        case .live:
            return "Keyboard Check"
        case .complete:
            return "Scan Done"
        }
    }
}

private enum HardwareCalibrationScanMode: String {
    case quick
    case full

    var title: String {
        switch self {
        case .quick:
            return "Quick"
        case .full:
            return "Full"
        }
    }
}

private let hardwareCalibrationStepDuration: TimeInterval = 10

private struct HardwareCalibrationSummary {
    private static let printableCharacterSet = CharacterSet.alphanumerics
        .union(.punctuationCharacters)
        .union(.symbols)
    private static let symbolCharacterSet = CharacterSet.punctuationCharacters.union(.symbols)

    let events: [KeyEvent]
    let keyDownCount: Int
    let keyUpCount: Int
    let repeatCount: Int
    let sawLetters: Bool
    let sawNumbers: Bool
    let sawSymbols: Bool
    let sawSpace: Bool
    let sawReturn: Bool
    let sawPrintable: Bool
    let sawDelete: Bool
    let sawForwardDelete: Bool
    let sawArrows: Bool
    let sawShift: Bool
    let sawControl: Bool
    let sawOption: Bool
    let sawCommand: Bool
    let sawCapsLock: Bool
    let sawTab: Bool
    let sawEscape: Bool
    let sawHomeEnd: Bool
    let sawPageKeys: Bool
    let sawFunctionKeys: Bool
    let sawKeyCommandSource: Bool
    let firstRepeatDelayMs: Int?
    let recentEventLabels: [String]
    let observedKeyCodes: Set<Int>
    let observedNormalizedCharacters: Set<String>
    let observedModifiers: Set<KeyModifier>

    init(events: [KeyEvent]) {
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        self.events = sortedEvents

        var keyDownCount = 0
        var keyUpCount = 0
        var repeatCount = 0
        var sawLetters = false
        var sawNumbers = false
        var sawSymbols = false
        var sawSpace = false
        var sawReturn = false
        var sawPrintable = false
        var sawDelete = false
        var sawForwardDelete = false
        var sawArrows = false
        var sawShift = false
        var sawControl = false
        var sawOption = false
        var sawCommand = false
        var sawCapsLock = false
        var sawTab = false
        var sawEscape = false
        var sawHomeEnd = false
        var sawPageKeys = false
        var sawFunctionKeys = false
        var sawKeyCommandSource = false
        var firstRepeatDelayMs: Int?
        var initialDownDates = [String: Date]()
        var observedKeyCodes = Set<Int>()
        var observedNormalizedCharacters = Set<String>()
        var observedModifiers = Set<KeyModifier>()

        for event in sortedEvents {
            if let keyCode = event.keyCode {
                observedKeyCodes.insert(keyCode)
            }

            if let value = Self.normalizedCharacters(for: event) {
                observedNormalizedCharacters.insert(value)
            }

            observedModifiers.formUnion(event.modifiers)

            switch event.phase {
            case .down:
                keyDownCount += 1
            case .up:
                keyUpCount += 1
            }

            if event.isRepeat {
                repeatCount += 1
            }

            if event.source == .keyCommand {
                sawKeyCommandSource = true
            }

            if Self.isPrintable(event) {
                sawPrintable = true
            }

            if Self.isLetter(event) {
                sawLetters = true
            }

            if Self.isNumber(event) {
                sawNumbers = true
            }

            if Self.isSymbol(event) {
                sawSymbols = true
            }

            if Self.isSpace(event) {
                sawSpace = true
            }

            if Self.isReturn(event) {
                sawReturn = true
            }

            if Self.isDelete(event) {
                sawDelete = true
            }

            if Self.isForwardDelete(event) {
                sawForwardDelete = true
            }

            if Self.isArrow(event) {
                sawArrows = true
            }

            if Self.isShift(event) {
                sawShift = true
            }

            if Self.isControl(event) {
                sawControl = true
            }

            if Self.isOption(event) {
                sawOption = true
            }

            if Self.isCommand(event) {
                sawCommand = true
            }

            if Self.isCapsLock(event) {
                sawCapsLock = true
            }

            if Self.isTab(event) {
                sawTab = true
            }

            if Self.isEscape(event) {
                sawEscape = true
            }

            if Self.isHomeEnd(event) {
                sawHomeEnd = true
            }

            if Self.isPageKey(event) {
                sawPageKeys = true
            }

            if Self.isFunctionKey(event) {
                sawFunctionKeys = true
            }

            let signature = Self.repeatSignature(for: event)
            if event.phase == .down && !event.isRepeat {
                initialDownDates[signature] = event.timestamp
            }

            if event.isRepeat,
               let initialDownDate = initialDownDates[signature] {
                let delayMs = max(0, Int(event.timestamp.timeIntervalSince(initialDownDate) * 1000))
                if delayMs > 0 {
                    firstRepeatDelayMs = min(firstRepeatDelayMs ?? delayMs, delayMs)
                }
            }
        }

        self.keyDownCount = keyDownCount
        self.keyUpCount = keyUpCount
        self.repeatCount = repeatCount
        self.sawLetters = sawLetters
        self.sawNumbers = sawNumbers
        self.sawSymbols = sawSymbols
        self.sawSpace = sawSpace
        self.sawReturn = sawReturn
        self.sawPrintable = sawPrintable
        self.sawDelete = sawDelete
        self.sawForwardDelete = sawForwardDelete
        self.sawArrows = sawArrows
        self.sawShift = sawShift
        self.sawControl = sawControl
        self.sawOption = sawOption
        self.sawCommand = sawCommand
        self.sawCapsLock = sawCapsLock
        self.sawTab = sawTab
        self.sawEscape = sawEscape
        self.sawHomeEnd = sawHomeEnd
        self.sawPageKeys = sawPageKeys
        self.sawFunctionKeys = sawFunctionKeys
        self.sawKeyCommandSource = sawKeyCommandSource
        self.firstRepeatDelayMs = firstRepeatDelayMs
        self.recentEventLabels = Array(sortedEvents.suffix(8).map(Self.eventLabel))
        self.observedKeyCodes = observedKeyCodes
        self.observedNormalizedCharacters = observedNormalizedCharacters
        self.observedModifiers = observedModifiers
    }

    var eventCount: Int {
        events.count
    }

    var hasSignal: Bool {
        sawPrintable || sawDelete || sawArrows || sawShift || sawControl ||
            sawOption || sawCommand || sawCapsLock || sawTab || sawEscape
    }

    private static func isPrintable(_ event: KeyEvent) -> Bool {
        guard let value = normalizedCharacters(for: event) else { return false }
        guard value != "⇧", value != "⌫" else { return false }
        return value.rangeOfCharacter(from: printableCharacterSet) != nil
    }

    private static func isLetter(_ event: KeyEvent) -> Bool {
        guard let value = normalizedCharacters(for: event) else { return false }
        return value.rangeOfCharacter(from: CharacterSet.letters) != nil
    }

    private static func isNumber(_ event: KeyEvent) -> Bool {
        guard let value = normalizedCharacters(for: event) else { return false }
        return value.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
    }

    private static func isSymbol(_ event: KeyEvent) -> Bool {
        guard let value = normalizedCharacters(for: event) else { return false }
        return value.rangeOfCharacter(from: symbolCharacterSet) != nil
    }

    private static func isSpace(_ event: KeyEvent) -> Bool {
        event.keyCode == Int(UIKeyboardHIDUsage.keyboardSpacebar.rawValue) ||
        event.characters == " "
    }

    private static func isReturn(_ event: KeyEvent) -> Bool {
        event.keyCode == Int(UIKeyboardHIDUsage.keyboardReturnOrEnter.rawValue) ||
        event.characters == "\n"
    }

    private static func isDelete(_ event: KeyEvent) -> Bool {
        event.keyCode == Int(UIKeyboardHIDUsage.keyboardDeleteOrBackspace.rawValue) ||
        event.characters == "⌫"
    }

    private static func isForwardDelete(_ event: KeyEvent) -> Bool {
        event.keyCode == Int(UIKeyboardHIDUsage.keyboardDeleteForward.rawValue)
    }

    private static func isArrow(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardLeftArrow.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightArrow.rawValue),
             Int(UIKeyboardHIDUsage.keyboardUpArrow.rawValue),
             Int(UIKeyboardHIDUsage.keyboardDownArrow.rawValue):
            return true
        default:
            return false
        }
    }

    private static func isShift(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardLeftShift.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightShift.rawValue):
            return true
        default:
            return event.characters == "⇧"
        }
    }

    private static func isControl(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardLeftControl.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightControl.rawValue):
            return true
        default:
            return event.modifiers.contains(.control)
        }
    }

    private static func isOption(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardLeftAlt.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightAlt.rawValue):
            return true
        default:
            return event.modifiers.contains(.option)
        }
    }

    private static func isCommand(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardLeftGUI.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightGUI.rawValue):
            return true
        default:
            return event.modifiers.contains(.command)
        }
    }

    private static func isCapsLock(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardCapsLock.rawValue),
             Int(UIKeyboardHIDUsage.keyboardLockingCapsLock.rawValue):
            return true
        default:
            return event.modifiers.contains(.capsLock) || event.modifiers.contains(.alphaShift)
        }
    }

    private static func isTab(_ event: KeyEvent) -> Bool {
        event.keyCode == Int(UIKeyboardHIDUsage.keyboardTab.rawValue)
    }

    private static func isEscape(_ event: KeyEvent) -> Bool {
        event.keyCode == Int(UIKeyboardHIDUsage.keyboardEscape.rawValue)
    }

    private static func isHomeEnd(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardHome.rawValue),
             Int(UIKeyboardHIDUsage.keyboardEnd.rawValue):
            return true
        default:
            return false
        }
    }

    private static func isPageKey(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardPageUp.rawValue),
             Int(UIKeyboardHIDUsage.keyboardPageDown.rawValue):
            return true
        default:
            return false
        }
    }

    private static func isFunctionKey(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardF1.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF2.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF3.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF4.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF5.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF6.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF7.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF8.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF9.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF10.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF11.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF12.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF13.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF14.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF15.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF16.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF17.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF18.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF19.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF20.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF21.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF22.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF23.rawValue),
             Int(UIKeyboardHIDUsage.keyboardF24.rawValue):
            return true
        default:
            return false
        }
    }

    private static func repeatSignature(for event: KeyEvent) -> String {
        if let keyCode = event.keyCode {
            return "code-\(keyCode)"
        }

        if let value = normalizedCharacters(for: event) {
            return "chars-\(value)"
        }

        return event.id.uuidString
    }

    private static func normalizedCharacters(for event: KeyEvent) -> String? {
        let value = event.charactersIgnoringModifiers ?? event.characters
        guard let value else { return nil }
        guard !value.isEmpty else { return nil }
        return value
    }

    private static func eventLabel(_ event: KeyEvent) -> String {
        let baseLabel: String

        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardLeftArrow.rawValue):
            baseLabel = "Left"
        case Int(UIKeyboardHIDUsage.keyboardRightArrow.rawValue):
            baseLabel = "Right"
        case Int(UIKeyboardHIDUsage.keyboardUpArrow.rawValue):
            baseLabel = "Up"
        case Int(UIKeyboardHIDUsage.keyboardDownArrow.rawValue):
            baseLabel = "Down"
        case Int(UIKeyboardHIDUsage.keyboardDeleteOrBackspace.rawValue):
            baseLabel = "Delete"
        case Int(UIKeyboardHIDUsage.keyboardTab.rawValue):
            baseLabel = "Tab"
        case Int(UIKeyboardHIDUsage.keyboardEscape.rawValue):
            baseLabel = "Escape"
        case Int(UIKeyboardHIDUsage.keyboardReturnOrEnter.rawValue):
            baseLabel = "Return"
        case Int(UIKeyboardHIDUsage.keyboardSpacebar.rawValue):
            baseLabel = "Space"
        case Int(UIKeyboardHIDUsage.keyboardLeftShift.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightShift.rawValue):
            baseLabel = "Shift"
        case Int(UIKeyboardHIDUsage.keyboardLeftControl.rawValue):
            baseLabel = "LCtrl"
        case Int(UIKeyboardHIDUsage.keyboardRightControl.rawValue):
            baseLabel = "RCtrl"
        case Int(UIKeyboardHIDUsage.keyboardLeftAlt.rawValue):
            baseLabel = "LOpt"
        case Int(UIKeyboardHIDUsage.keyboardRightAlt.rawValue):
            baseLabel = "ROpt"
        case Int(UIKeyboardHIDUsage.keyboardLeftGUI.rawValue):
            baseLabel = "LCmd"
        case Int(UIKeyboardHIDUsage.keyboardRightGUI.rawValue):
            baseLabel = "RCmd"
        case Int(UIKeyboardHIDUsage.keyboardCapsLock.rawValue),
             Int(UIKeyboardHIDUsage.keyboardLockingCapsLock.rawValue):
            baseLabel = "Caps"
        default:
            if let value = normalizedCharacters(for: event)?
                .replacingOccurrences(of: "\n", with: "Return")
                .replacingOccurrences(of: "\t", with: "Tab") {
                baseLabel = value
            } else if let keyCode = event.keyCode {
                baseLabel = "Key \(keyCode)"
            } else {
                baseLabel = "Key"
            }
        }

        let phaseLabel: String
        if event.isRepeat {
            phaseLabel = "repeat"
        } else {
            switch event.phase {
            case .down:
                phaseLabel = "down"
            case .up:
                phaseLabel = "up"
            }
        }

        return "\(baseLabel) \(phaseLabel)"
    }
}

private struct HardwareCalibrationToken: Identifiable {
    let title: String
    let keyCodes: Set<Int>
    let modifiers: Set<KeyModifier>
    let characters: Set<String>
    let requiresRepeat: Bool

    var id: String { title }

    init(
        title: String,
        keyCodes: [Int] = [],
        modifiers: Set<KeyModifier> = [],
        characters: [String] = [],
        requiresRepeat: Bool = false
    ) {
        self.title = title
        self.keyCodes = Set(keyCodes)
        self.modifiers = modifiers
        self.characters = Set(characters)
        self.requiresRepeat = requiresRepeat
    }

    func isMatched(in summary: HardwareCalibrationSummary) -> Bool {
        if requiresRepeat {
            return summary.repeatCount > 0
        }

        if !keyCodes.isEmpty && !summary.observedKeyCodes.isDisjoint(with: keyCodes) {
            return true
        }

        if !modifiers.isEmpty && !summary.observedModifiers.isDisjoint(with: modifiers) {
            return true
        }

        if !characters.isEmpty &&
            !summary.observedNormalizedCharacters.isDisjoint(with: characters) {
            return true
        }

        return false
    }
}

private struct HardwareCalibrationFamily: Identifiable {
    let title: String
    let detail: String
    let promptLines: [String]
    let tokens: [HardwareCalibrationToken]
    let isOptional: Bool

    var id: String { title }

    var totalCount: Int { tokens.count }

    func matchedCount(in summary: HardwareCalibrationSummary) -> Int {
        tokens.reduce(into: 0) { partialResult, token in
            if token.isMatched(in: summary) {
                partialResult += 1
            }
        }
    }

    func isComplete(in summary: HardwareCalibrationSummary) -> Bool {
        matchedCount(in: summary) == totalCount
    }

    func missingCount(in summary: HardwareCalibrationSummary) -> Int {
        max(0, totalCount - matchedCount(in: summary))
    }

    func missingTokenTitles(in summary: HardwareCalibrationSummary) -> [String] {
        tokens.compactMap { token in
            token.isMatched(in: summary) ? nil : token.title
        }
    }

    func tokenTitles(matchedIn baseline: HardwareCalibrationSummary, missingIn candidate: HardwareCalibrationSummary) -> [String] {
        tokens.compactMap { token in
            token.isMatched(in: baseline) && !token.isMatched(in: candidate) ? token.title : nil
        }
    }

    private static func code(_ usage: UIKeyboardHIDUsage) -> Int {
        Int(usage.rawValue)
    }

    private static func token(_ title: String, _ usage: UIKeyboardHIDUsage) -> HardwareCalibrationToken {
        HardwareCalibrationToken(title: title, keyCodes: [code(usage)])
    }

    private static func token(
        _ title: String,
        keyCodes: [UIKeyboardHIDUsage]
    ) -> HardwareCalibrationToken {
        HardwareCalibrationToken(title: title, keyCodes: keyCodes.map(code))
    }

    static let quickCases: [HardwareCalibrationFamily] = [
        HardwareCalibrationFamily(
            title: "Type A + 1",
            detail: "Press one letter and one number. That is enough to prove the normal typing path.",
            promptLines: [
                "A   1"
            ],
            tokens: [
                token("A", .keyboardA),
                token("1", .keyboard1)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Delete",
            detail: "Press Delete once.",
            promptLines: [
                "Delete"
            ],
            tokens: [
                token("Delete", .keyboardDeleteOrBackspace)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Shift + Tab + Arrow",
            detail: "Press Shift, then Tab, then any arrow. If your board has no arrows, use Escape or Home/End.",
            promptLines: [
                "Shift   Tab   Any Arrow"
            ],
            tokens: [
                token("Shift", keyCodes: [.keyboardLeftShift, .keyboardRightShift]),
                token("Tab", .keyboardTab),
                token(
                    "Arrow / Esc",
                    keyCodes: [
                        .keyboardLeftArrow,
                        .keyboardRightArrow,
                        .keyboardUpArrow,
                        .keyboardDownArrow,
                        .keyboardEscape,
                        .keyboardHome,
                        .keyboardEnd
                    ]
                )
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Hold A",
            detail: "Optional. Hold one key until it repeats. This helps tune hold timing.",
            promptLines: [
                "Hold A"
            ],
            tokens: [
                HardwareCalibrationToken(title: "Repeat", requiresRepeat: true)
            ],
            isOptional: true
        )
    ]

    static let allCases: [HardwareCalibrationFamily] = [
        HardwareCalibrationFamily(
            title: "Letters A-Z",
            detail: "Press the whole letter board once. Walk left to right. Any physical layout is fine as long as every printed letter key gets tested.",
            promptLines: [
                "QWERTYUIOP",
                "ASDFGHJKL",
                "ZXCVBNM"
            ],
            tokens: [
                token("A", .keyboardA), token("B", .keyboardB), token("C", .keyboardC),
                token("D", .keyboardD), token("E", .keyboardE), token("F", .keyboardF),
                token("G", .keyboardG), token("H", .keyboardH), token("I", .keyboardI),
                token("J", .keyboardJ), token("K", .keyboardK), token("L", .keyboardL),
                token("M", .keyboardM), token("N", .keyboardN), token("O", .keyboardO),
                token("P", .keyboardP), token("Q", .keyboardQ), token("R", .keyboardR),
                token("S", .keyboardS), token("T", .keyboardT), token("U", .keyboardU),
                token("V", .keyboardV), token("W", .keyboardW), token("X", .keyboardX),
                token("Y", .keyboardY), token("Z", .keyboardZ)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Number Row",
            detail: "Press every top-row number key once.",
            promptLines: [
                "1234567890"
            ],
            tokens: [
                token("1", .keyboard1), token("2", .keyboard2), token("3", .keyboard3),
                token("4", .keyboard4), token("5", .keyboard5), token("6", .keyboard6),
                token("7", .keyboard7), token("8", .keyboard8), token("9", .keyboard9),
                token("0", .keyboard0)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Main Symbols",
            detail: "Press the standard punctuation keys around the main alpha block.",
            promptLines: [
                "` - = [ ] \\",
                "; ' , . /"
            ],
            tokens: [
                token("`", .keyboardGraveAccentAndTilde),
                token("-", .keyboardHyphen),
                token("=", .keyboardEqualSign),
                token("[", .keyboardOpenBracket),
                token("]", .keyboardCloseBracket),
                token("\\", .keyboardBackslash),
                token(";", .keyboardSemicolon),
                token("'", .keyboardQuote),
                token(",", .keyboardComma),
                token(".", .keyboardPeriod),
                token("/", .keyboardSlash)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Extra Layout Symbols",
            detail: "Some regional boards add extra symbol keys near Return or left Shift. Skip if your board does not have them.",
            promptLines: [
                "ISO \\   #"
            ],
            tokens: [
                token("#", .keyboardNonUSPound),
                token("ISO \\", .keyboardNonUSBackslash)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Core Edit",
            detail: "Press the core editing keys every keyboard should have.",
            promptLines: [
                "Tab   Space   Return   Delete"
            ],
            tokens: [
                token("Tab", .keyboardTab),
                token("Space", .keyboardSpacebar),
                token("Return", .keyboardReturnOrEnter),
                token("Delete", .keyboardDeleteOrBackspace)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Extra Edit Keys",
            detail: "Forward Delete and Insert are optional on many keyboards. Test them if your board exposes them.",
            promptLines: [
                "FwdDel   Insert"
            ],
            tokens: [
                token("FwdDel", .keyboardDeleteForward),
                token("Insert", .keyboardInsert)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Modifiers Left",
            detail: "Press left-side modifiers one by one. Do not chord them.",
            promptLines: [
                "LShift   LCtrl   LOpt   LCmd"
            ],
            tokens: [
                token("LShift", .keyboardLeftShift),
                token("LCtrl", .keyboardLeftControl),
                token("LOpt", .keyboardLeftAlt),
                token("LCmd", .keyboardLeftGUI)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Caps Lock",
            detail: "Caps is useful to test, but some compact boards omit it or remap it.",
            promptLines: [
                "Caps"
            ],
            tokens: [
                token("Caps", .keyboardCapsLock)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Modifiers Right",
            detail: "Press right-side modifiers too. Many boards expose these differently.",
            promptLines: [
                "RShift   RCtrl   ROpt   RCmd"
            ],
            tokens: [
                token("RShift", .keyboardRightShift),
                token("RCtrl", .keyboardRightControl),
                token("ROpt", .keyboardRightAlt),
                token("RCmd", .keyboardRightGUI)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Arrow Cluster",
            detail: "Press all 4 arrows once.",
            promptLines: [
                "\u{2190}   \u{2191}   \u{2192}   \u{2193}"
            ],
            tokens: [
                token("Left", .keyboardLeftArrow),
                token("Right", .keyboardRightArrow),
                token("Up", .keyboardUpArrow),
                token("Down", .keyboardDownArrow)
            ],
            isOptional: false
        ),
        HardwareCalibrationFamily(
            title: "Nav Cluster",
            detail: "Press Escape, Home, End, Page Up, and Page Down if your keyboard has them.",
            promptLines: [
                "Esc   Home   End",
                "PgUp   PgDn"
            ],
            tokens: [
                token("Esc", .keyboardEscape),
                token("Home", .keyboardHome),
                token("End", .keyboardEnd),
                token("PgUp", .keyboardPageUp),
                token("PgDn", .keyboardPageDown)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Function Row F1-F12",
            detail: "Press the full standard function row.",
            promptLines: [
                "F1 F2 F3 F4",
                "F5 F6 F7 F8",
                "F9 F10 F11 F12"
            ],
            tokens: [
                token("F1", .keyboardF1), token("F2", .keyboardF2), token("F3", .keyboardF3),
                token("F4", .keyboardF4), token("F5", .keyboardF5), token("F6", .keyboardF6),
                token("F7", .keyboardF7), token("F8", .keyboardF8), token("F9", .keyboardF9),
                token("F10", .keyboardF10), token("F11", .keyboardF11), token("F12", .keyboardF12)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Extended F13-F24",
            detail: "Test extra function keys on full-size or pro boards.",
            promptLines: [
                "F13 F14 F15 F16",
                "F17 F18 F19 F20",
                "F21 F22 F23 F24"
            ],
            tokens: [
                token("F13", .keyboardF13), token("F14", .keyboardF14), token("F15", .keyboardF15),
                token("F16", .keyboardF16), token("F17", .keyboardF17), token("F18", .keyboardF18),
                token("F19", .keyboardF19), token("F20", .keyboardF20), token("F21", .keyboardF21),
                token("F22", .keyboardF22), token("F23", .keyboardF23), token("F24", .keyboardF24)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Numpad",
            detail: "If your keyboard has a numpad, press every numpad key once, including operators.",
            promptLines: [
                "7 8 9 /",
                "4 5 6 *",
                "1 2 3 -",
                "0 . Enter +"
            ],
            tokens: [
                token("Num", .keypadNumLock),
                token("KP /", .keypadSlash),
                token("KP *", .keypadAsterisk),
                token("KP -", .keypadHyphen),
                token("KP +", .keypadPlus),
                token("KP Enter", .keypadEnter),
                token("KP 0", .keypad0),
                token("KP 1", .keypad1),
                token("KP 2", .keypad2),
                token("KP 3", .keypad3),
                token("KP 4", .keypad4),
                token("KP 5", .keypad5),
                token("KP 6", .keypad6),
                token("KP 7", .keypad7),
                token("KP 8", .keypad8),
                token("KP 9", .keypad9),
                token("KP .", .keypadPeriod),
                token("KP =", .keypadEqualSign)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "International",
            detail: "Test extra regional or language keys. Skip this row if your board does not have them.",
            promptLines: [
                "Intl1 .. Intl9",
                "Lang1 .. Lang9"
            ],
            tokens: [
                token("Intl1", .keyboardInternational1),
                token("Intl2", .keyboardInternational2),
                token("Intl3", .keyboardInternational3),
                token("Intl4", .keyboardInternational4),
                token("Intl5", .keyboardInternational5),
                token("Intl6", .keyboardInternational6),
                token("Intl7", .keyboardInternational7),
                token("Intl8", .keyboardInternational8),
                token("Intl9", .keyboardInternational9),
                token("Lang1", .keyboardLANG1),
                token("Lang2", .keyboardLANG2),
                token("Lang3", .keyboardLANG3),
                token("Lang4", .keyboardLANG4),
                token("Lang5", .keyboardLANG5),
                token("Lang6", .keyboardLANG6),
                token("Lang7", .keyboardLANG7),
                token("Lang8", .keyboardLANG8),
                token("Lang9", .keyboardLANG9)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "System And Media",
            detail: "Test print, menu, clipboard, and volume keys if your board exposes them to iOS.",
            promptLines: [
                "Print Scroll Pause App Menu",
                "Undo Cut Copy Paste Find",
                "Mute Vol+ Vol-"
            ],
            tokens: [
                token("Print", .keyboardPrintScreen),
                token("Scroll", .keyboardScrollLock),
                token("Pause", .keyboardPause),
                token("App", .keyboardApplication),
                token("Menu", .keyboardMenu),
                token("Help", .keyboardHelp),
                token("Undo", .keyboardUndo),
                token("Cut", .keyboardCut),
                token("Copy", .keyboardCopy),
                token("Paste", .keyboardPaste),
                token("Again", .keyboardAgain),
                token("Find", .keyboardFind),
                token("Mute", .keyboardMute),
                token("Vol+", .keyboardVolumeUp),
                token("Vol-", .keyboardVolumeDown)
            ],
            isOptional: true
        ),
        HardwareCalibrationFamily(
            title: "Held Repeat",
            detail: "Hold Delete until repeat starts. If Delete does not repeat on your board, try an arrow key after.",
            promptLines: [
                "Hold Delete"
            ],
            tokens: [
                HardwareCalibrationToken(title: "Repeat", requiresRepeat: true)
            ],
            isOptional: false
        )
    ]
}
#endif

private extension View {
    func hwcOnChange<Value: Equatable>(
        of value: Value,
        _ action: @escaping () -> Void
    ) -> some View {
        onChange(of: value) {
            action()
        }
    }

    func hwcOnChange<Value: Equatable>(
        of value: Value,
        _ action: @escaping (Value, Value) -> Void
    ) -> some View {
        onChange(of: value) { oldValue, newValue in
            action(oldValue, newValue)
        }
    }

    @ViewBuilder
    func hwcDarkNavigationChrome() -> some View {
        if #available(iOS 16.0, *) {
            self
                .toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            self
        }
    }
}

private struct InfoDisclosureHeaderView: View {
    let title: String
    let detail: String
    let isExpanded: Bool
    let titleSize: CGFloat
    let titleWeight: Font.Weight
    let detailSize: CGFloat
    let titleColor: Color
    let detailColor: Color
    let iconColor: Color
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 6 : 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: titleSize, weight: titleWeight))
                    .foregroundColor(titleColor)

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                        .font(.system(size: max(13, titleSize - 1), weight: .semibold))
                        .foregroundColor(iconColor)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(StaticPressButtonStyle())
                .accessibilityLabel(isExpanded ? "Hide details for \(title)" : "Show details for \(title)")
            }

            if isExpanded {
                Text(detail)
                    .font(.system(size: detailSize, weight: .regular))
                    .foregroundColor(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct PreviewToolbarMenuMorphLine: Shape {
    enum Segment {
        case top
        case middle
        case bottom
    }

    var progress: CGFloat
    let segment: Segment

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let collapseProgress = min(max(progress / 0.42, 0), 1)
        let splitProgress = min(max((progress - 0.42) / 0.58, 0), 1)

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let expandedHalfWidth = rect.width * 0.28
        let collapsedHalfWidth = rect.width * 0.18
        let topY = rect.height * 0.28
        let bottomY = rect.height * 0.72
        let chevronAngle = CGFloat.pi / 6
        let chevronApex = CGPoint(x: center.x, y: rect.height * 0.68)
        let chevronLength = rect.width * 0.26
        let chevronReach = cos(chevronAngle) * chevronLength
        let chevronLift = sin(chevronAngle) * chevronLength

        let hamburgerLine: (start: CGPoint, end: CGPoint)
        let collapsedLine: (start: CGPoint, end: CGPoint)
        let finalLine: (start: CGPoint, end: CGPoint)

        switch segment {
        case .top:
            hamburgerLine = (
                CGPoint(x: center.x - expandedHalfWidth, y: topY),
                CGPoint(x: center.x + expandedHalfWidth, y: topY)
            )
            collapsedLine = (
                CGPoint(x: center.x - collapsedHalfWidth, y: center.y),
                CGPoint(x: center.x + collapsedHalfWidth, y: center.y)
            )
            finalLine = (
                CGPoint(x: chevronApex.x - chevronReach, y: chevronApex.y - chevronLift),
                chevronApex
            )
        case .middle:
            hamburgerLine = (
                CGPoint(x: center.x - expandedHalfWidth, y: center.y),
                CGPoint(x: center.x + expandedHalfWidth, y: center.y)
            )
            collapsedLine = (center, center)
            finalLine = (center, center)
        case .bottom:
            hamburgerLine = (
                CGPoint(x: center.x - expandedHalfWidth, y: bottomY),
                CGPoint(x: center.x + expandedHalfWidth, y: bottomY)
            )
            collapsedLine = (
                CGPoint(x: center.x - collapsedHalfWidth, y: center.y),
                CGPoint(x: center.x + collapsedHalfWidth, y: center.y)
            )
            finalLine = (
                chevronApex,
                CGPoint(x: chevronApex.x + chevronReach, y: chevronApex.y - chevronLift)
            )
        }

        let collapseLine = (
            interpolate(from: hamburgerLine.start, to: collapsedLine.start, progress: collapseProgress),
            interpolate(from: hamburgerLine.end, to: collapsedLine.end, progress: collapseProgress)
        )
        let resolvedLine = (
            interpolate(from: collapseLine.0, to: finalLine.start, progress: splitProgress),
            interpolate(from: collapseLine.1, to: finalLine.end, progress: splitProgress)
        )

        var path = Path()
        path.move(to: resolvedLine.0)
        path.addLine(to: resolvedLine.1)
        return path
    }

    private func interpolate(from: CGPoint, to: CGPoint, progress: CGFloat) -> CGPoint {
        return CGPoint(
            x: from.x + ((to.x - from.x) * progress),
            y: from.y + ((to.y - from.y) * progress)
        )
    }
}

private struct PreviewToolbarMenuMorphIcon: View {
    var isExpanded: Bool
    var color: Color
    var lineWidth: CGFloat

    private var progress: CGFloat {
        isExpanded ? 1 : 0
    }

    private var middleOpacity: CGFloat {
        max(0, 1 - min(max(progress / 0.42, 0), 1))
    }

    var body: some View {
        ZStack {
            PreviewToolbarMenuMorphLine(progress: progress, segment: .top)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

            PreviewToolbarMenuMorphLine(progress: progress, segment: .middle)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .opacity(middleOpacity)

            PreviewToolbarMenuMorphLine(progress: progress, segment: .bottom)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.timingCurve(0.25, 0.88, 0.24, 1, duration: 0.24), value: isExpanded)
    }
}

private struct PendingModeChangeKeyEdit: Identifiable {
    let id = UUID()
    let row: KeyboardRowKind
    let slotIndex: Int
    let replacementValue: String
    let removesSlot: Bool
    let warning: String
}

private struct HWCWordDropletShape: Shape {
    var flow: CGFloat

    var animatableData: CGFloat {
        get { flow }
        set { flow = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let rounding = min(rect.height * 0.50, rect.width * 0.24)
        let tail = rect.height * (0.10 + abs(flow) * 0.08)
        let wave = flow * rect.height * 0.10
        let top = CGPoint(x: rect.midX + wave, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.midY + wave * 0.28)
        let bottom = CGPoint(x: rect.midX - wave * 0.65, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.midY - wave * 0.22)

        var path = Path()
        path.move(to: top)
        path.addCurve(
            to: right,
            control1: CGPoint(x: rect.maxX - rounding * 1.35, y: rect.minY - wave * 0.12),
            control2: CGPoint(x: rect.maxX + wave * 0.08, y: right.y - rounding)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.maxX - wave * 0.06, y: right.y + rounding),
            control2: CGPoint(x: rect.maxX - rounding * 1.20, y: rect.maxY + wave * 0.10)
        )
        path.addCurve(
            to: left,
            control1: CGPoint(x: rect.minX + rounding * 1.25, y: rect.maxY - wave * 0.08),
            control2: CGPoint(x: rect.minX - wave * 0.08, y: left.y + rounding)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: rect.minX + tail * 0.20, y: left.y - rounding),
            control2: CGPoint(x: rect.minX + rounding + tail, y: rect.minY + wave * 0.06)
        )
        path.closeSubpath()
        return path
    }
}

private struct HWCWaterMotionValues {
    var stretchX: CGFloat = 1.0
    var squashY: CGFloat = 1.0
    var tilt: Double = 0
    var lagX: CGFloat = 0
    var liftY: CGFloat = 0
    var flow: CGFloat = 0
}

private struct HWCWaterOsmosisValues {
    var progress: CGFloat = 0
    var cohesion: CGFloat = 1
    var opacity: CGFloat = 1
}

private struct HWCSelectedLayerAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct HWCAdditionalLayerTrashFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct HWCBackupRestoreRequest: Identifiable {
    let id: UUID
    let createdAt: Date
}

private struct HWCEncryptedBackupHistoryView: View {
    @ObservedObject var controller: HWCEncryptedCloudSnapshotController
    @State private var pendingRestoreRequest: HWCBackupRestoreRequest?

    var body: some View {
        List {
            Section("Encrypted iCloud Backup") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.state.title)
                        .font(.headline)
                    Text(controller.state.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if controller.reconcileActivity.phase != .idle {
                        Text(controller.reconcileActivity.summary)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Back Up Now") {
                    controller.reconcileNow()
                }

                Button("Open iOS Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }

            Section {
                Text("History is immutable. Inspect a generation, restore it as the current working copy, edit HWC normally, then back up to create another successor. HWC never derives the encryption key from device hardware.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Recovery Generations") {
                if controller.historyLoadState == .waiting {
                    Text("Waiting for the active backup attempt to finish before loading history. Your existing backups have not been checked yet.")
                        .foregroundStyle(.secondary)
                } else if controller.historyIsLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading encrypted history…")
                        Spacer()
                    }
                    Text(controller.historyActivity.summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if controller.historyLoadState == .failed {
                    Text("Backup history could not be loaded. This does not mean your backups are missing. Try Refresh Backup History again.")
                        .foregroundStyle(.orange)
                } else if controller.historyLoadState == .idle {
                    Text("Backup history has not been checked yet.")
                        .foregroundStyle(.secondary)
                } else if controller.history.isEmpty,
                          controller.historyOmittedGenerationCount > 0 {
                    Text(
                        "Cloud history contains \(controller.historyOmittedGenerationCount) unusable encrypted generation\(controller.historyOmittedGenerationCount == 1 ? "" : "s"). Existing cloud data and local pending snapshots remain preserved."
                    )
                    .foregroundStyle(.orange)
                } else if controller.history.isEmpty {
                    Text("No cloud generations are available yet. Local encrypted pending snapshots remain preserved.")
                        .foregroundStyle(.secondary)
                } else {
                    if controller.historyOmittedGenerationCount > 0 {
                        Text(
                            "\(controller.historyOmittedGenerationCount) unusable encrypted generation\(controller.historyOmittedGenerationCount == 1 ? " was" : "s were") hidden. Valid authenticated generations remain available below."
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                    ForEach(controller.history, id: \.snapshotID) { generation in
                        generationRow(generation)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Encrypted Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    controller.refreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(controller.historyIsLoading)
                .accessibilityLabel("Refresh Backup History")
            }
        }
        .onAppear {
            controller.refreshHistory()
        }
        .alert(item: $pendingRestoreRequest) { request in
            Alert(
                title: Text("Restore as New Snapshot?"),
                message: Text("This authenticated generation from \(request.createdAt.formatted(date: .abbreviated, time: .shortened)) becomes the current HWC working copy. Existing cloud generations stay unchanged."),
                primaryButton: .destructive(Text("Restore")) {
                    controller.restoreHistoryGeneration(snapshotID: request.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private func generationRow(
        _ generation: HWCCloudSnapshotGenerationMetadata
    ) -> some View {
        let createdAt = Date(
            timeIntervalSince1970: Double(generation.createdAtMilliseconds) / 1_000
        )
        let inspection = controller.inspectedGeneration?.snapshotID == generation.snapshotID
            ? controller.inspectedGeneration
            : nil

        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Text("Encrypted generation \(generation.snapshotID.uuidString.prefix(8))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if inspection != nil {
                    Label("Authenticated", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if let inspection {
                Text("\(inspection.storeIDs.count) stores · \(inspection.entryCount) entries · \(inspection.retainedConflictCount) retained conflicts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restore as New Snapshot") {
                    pendingRestoreRequest = HWCBackupRestoreRequest(
                        id: generation.snapshotID,
                        createdAt: createdAt
                    )
                }
                .disabled(controller.restoringHistorySnapshotID != nil)
            } else {
                Button {
                    controller.inspectHistoryGeneration(snapshotID: generation.snapshotID)
                } label: {
                    if controller.inspectingHistorySnapshotID == generation.snapshotID {
                        ProgressView()
                    } else {
                        Label("Authenticate & Inspect", systemImage: "lock.shield")
                    }
                }
                .disabled(controller.inspectingHistorySnapshotID != nil)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CompanionHomeView: View {
    @Binding private var setupDeepLinkRequestAt: Double
    @Binding private var hardwareLabDeepLinkRequestAt: Double
    @Binding private var pendingKeymapImportURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Namespace private var liveEditorLayerGlassNamespace
    @StateObject private var settings = CompanionSettingsStore()
    @StateObject private var cloudSnapshot = HWCEncryptedCloudSnapshotController.shared
    @StateObject private var languageBrain = HWKLanguageBrainCoordinator()
    @StateObject private var abcUnlockStore = ABCUnlockStore()
    @StateObject private var hardwarePremiumStore = HardwarePremiumUnlockStore()
    @StateObject private var additionalLayersStore = AdditionalLayersUnlockStore()
    @StateObject private var supportDeveloperStore = SupportDeveloperUnlockStore()
    #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
    @StateObject private var monitor = KeyMonitor()
    #endif
    @State private var selectedExpandedLayer: ExpandedKeymapLayer = .symbols1
    @State private var selectedCustomLayerID: UUID?
    @State private var previousKeyboardEditorLayerSelectionID: String?
    @State private var layerDropletFingerLocation: CGPoint?
    @State private var draggedCustomLayerID: UUID?
    @State private var additionalLayerDragLocation: CGPoint?
    @State private var additionalLayerTrashFrame: CGRect = .zero
    @State private var additionalLayerPurchasePrompt = HWCAdditionalLayerPurchasePromptState()
    @State private var selectedCustomLayerKeySelection: CustomLayerEditorKeySelection?
    @State private var selectedEditActionMode: KeyboardEditActionMode = .tap
    @State private var isKeyboardEditorExpanded = false
    @State private var selectedEditableRow: KeyboardRowKind = .toolbar
    @State private var selectedSlotIndex = 0
    @State private var isKeyShelfExpanded = false
    @State private var selectedKeyShelfSectionID = ""
    @State private var selectedKeyShelfTokenPage = 0
    @State private var keyShelfSearchText = ""
    @State private var isABCLayerUnlocked = false
    @State private var showsABCUnlockPrompt = false
    @State private var showsClipboardSettings = false
    @State private var showsHideKeyboardAgreement = false
    @State private var clipboardSnippetCount = 0
    @State private var hadProtectedABCLayer = false
    @State private var expandedInfoIDs = Set<String>()
    /// Persisted so an explicit Custom choice survives relaunch and view
    /// recreation: the mode is otherwise derived from the toggles, and a
    /// custom configuration that happens to match a preset would silently
    /// re-label itself Hardware/Software. Cleared only by explicitly
    /// choosing a preset in the mode picker.
    @AppStorage("companion.settingsMode.customSelected") private var usesCustomSettingsMode = false
    @State private var pendingModeChangeKeyEdit: PendingModeChangeKeyEdit?
    @State private var pendingCustomLayerHoldPrompt: KeyboardEditorLayerOption?
    @State private var pendingKeyEditor: KeyEditorItem?
    @State private var showsCreateSavedPresetPrompt = false
    @State private var pendingSavedPresetRenameID: UUID?
    @State private var savedPresetName = ""
    @State private var selectedTab = 0
    @State private var handledSetupDeepLinkRequestAt = 0.0
    @State private var handledHardwareLabDeepLinkRequestAt = 0.0
    @State private var keyboardReloadStatusMessage: String?
    @State private var showsKeymapFileImporter = false
    @State private var keymapTransferSheet: HWCKeymapTransferSheetDestination?
    @State private var keymapExportFileDocument: HWCKeymapTransferFileDocument?
    @State private var showsKeymapFileExporter = false
    @State private var keymapExportFilename = "hwc-layer"
    @State private var showsKeymapImportResult = false
    @State private var keymapImportResultTitle = "Keymap Import"
    @State private var keymapImportResultMessage = ""
    @State private var templateLibraryError: String?
    @State private var editingTemplateID: UUID?
    @State private var editingTemplateSurface: KeyboardRowSurface = .mainRow
    @State private var editingTemplateLayerID: UUID?
    @State private var assistiveTouchSettingsStatusMessage: String?
    @State private var selectedAutocorrectSlot: AutocorrectSlotSelection?
    @State private var selectedAutocorrectTaughtRule: AutocorrectTaughtRuleSelection?
    @State private var autocorrectRuleText = ""
    @State private var isCompilingAutocorrectRule = false
    @State private var typedTextRuleGenerationMessage: String?
    @State private var autocorrectUndoSnapshot: AutocorrectUndoSnapshot?
    private let setupFlowStepMinimumHeight: CGFloat = 156
    @State private var hardwareKeyboardTestText = ""
    #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
    private static let hardwareLabEventMatchWindow: TimeInterval = 0.65
    @State private var previousHardwareKeyboardTestText = ""
    @State private var hardwareLabCapturedEvents = [KeyEvent]()
    @State private var hardwareLabConsumedEventIDs = Set<UUID>()
    @State private var hardwareLabExportMessage: String?
    @State private var hardwareLabCaptureFocusRequestAt = 0.0
    #endif
    #if HWC_INTERNAL_BUILD
    @State private var showsAdvancedHardwareCalibration = false
    @State private var isRawHardwareCalibrationActive = false
    @State private var rawHardwareCalibrationEvents = [KeyEvent]()
    @State private var liveHardwareCalibrationStartedAt: Date?
    @State private var hardwareCalibrationScanPhase: HardwareCalibrationScanPhase = .idle
    @State private var hardwareCalibrationScanMode: HardwareCalibrationScanMode = .quick
    @State private var hardwareCalibrationScanStepIndex = 0
    @State private var hardwareCalibrationStepStartedAt: Date?
    @State private var hardwareCalibrationStepDeadline: Date?
    @State private var hardwareCalibrationClock = Date()
    @State private var appliedHardwareCalibrationProfile: HardwareCalibrationProfile?
    @State private var hardwareCalibrationAppliedMessage: String?
    @State private var lastAutoAppliedHardwareCalibrationFingerprint: String?
    #endif
    private let presetLibrary = KeyboardLayoutPreset.allCases.filter { $0 != .custom }
    #if HWC_INTERNAL_BUILD
    private let m16HardwareLabSeed = 1603
    private let hardwareCalibrationTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    #endif

    init(
        setupDeepLinkRequestAt: Binding<Double> = .constant(0.0),
        hardwareLabDeepLinkRequestAt: Binding<Double> = .constant(0.0),
        pendingKeymapImportURL: Binding<URL?> = .constant(nil)
    ) {
        _setupDeepLinkRequestAt = setupDeepLinkRequestAt
        _hardwareLabDeepLinkRequestAt = hardwareLabDeepLinkRequestAt
        _pendingKeymapImportURL = pendingKeymapImportURL
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationView {
                    settingsTab
                        .background(HWKDuoHingeObserver())
                        .navigationBarTitle("Settings", displayMode: .inline)
                        .hwcDarkNavigationChrome()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tag(0)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }

                NavigationView {
                    autocorrectTab
                        .navigationBarTitle("Autocorrect", displayMode: .inline)
                        .hwcDarkNavigationChrome()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tag(1)
                .tabItem {
                    Label("Autocorrect", systemImage: "text.badge.checkmark")
                }

                NavigationView {
                    keymapTab
                        .navigationBarTitle("Keymap", displayMode: .inline)
                        .hwcDarkNavigationChrome()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tag(keymapTabIndex)
                .tabItem {
                    Label("Keymap", systemImage: "keyboard")
                }

                NavigationView {
                    themesTab
                        .navigationBarTitle("Themes", displayMode: .inline)
                        .hwcDarkNavigationChrome()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tag(3)
                .tabItem {
                    Label("Themes", systemImage: "sparkles.rectangle.stack")
                }

                NavigationView {
                    aboutTab
                        .navigationBarTitle("About", displayMode: .inline)
                        .hwcDarkNavigationChrome()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tag(aboutTabIndex)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: settings.autocorrectEnabled)

            if shouldShowSetupSplash {
                firstTimeSetupSplash
            }

            if let prompt = supportDeveloperStore.thankYouPrompt {
                SupportDeveloperThankYouModal(prompt: prompt) {
                    supportDeveloperStore.dismissThankYouPrompt()
                }
                .zIndex(20)
            }
        }
        .accentColor(tabAccentColor)
        .task {
            await languageBrain.consolidate()
        }
        .onAppear {
            KeyboardSettingsSnapshot.disableLiveClipboardSavingAfterPastePermissionFailure()
            settings.refreshKeyboardStatus()
            hadProtectedABCLayer = hasProtectedABCLayer
            refreshClipboardSnippetCount()
            handleSetupDeepLinkIfNeeded()
            handleHardwareLabDeepLinkIfNeeded()
            handleKeymapImportIfNeeded()
            enforceHardwarePremiumAccess()
            reportSupportAccessDiagnostics()
            #if HWC_INTERNAL_BUILD
            syncHardwareKeyMonitor()
            recordCompanionHardwareDiagnostic(.appVisible)
            #endif
        }
        .hwcOnChange(of: protectedABCLayerStateID) {
            syncABCLayerProtectionState()
        }
        .hwcOnChange(of: setupDeepLinkRequestAt) {
            handleSetupDeepLinkIfNeeded()
        }
        .hwcOnChange(of: hardwareLabDeepLinkRequestAt) {
            handleHardwareLabDeepLinkIfNeeded()
        }
        .hwcOnChange(of: pendingKeymapImportURL) {
            handleKeymapImportIfNeeded()
        }
        .hwcOnChange(of: settings.signalRelayEnabled) {
            enforceHardwarePremiumAccess()
            #if HWC_INTERNAL_BUILD
            syncHardwareKeyMonitor()
            recordCompanionHardwareDiagnostic(.captureChanged)
            #endif
        }
        .hwcOnChange(of: hardwarePremiumStore.isUnlocked) {
            enforceHardwarePremiumAccess()
            #if HWC_INTERNAL_BUILD
            syncHardwareKeyMonitor()
            #endif
        }
        .hwcOnChange(of: supportDeveloperStore.isUnlocked) {
            enforceHardwarePremiumAccess()
            enforceAdditionalLayerAccess()
            reportSupportAccessDiagnostics()
            #if HWC_INTERNAL_BUILD
            syncHardwareKeyMonitor()
            #endif
        }
        .hwcOnChange(of: additionalLayersStore.purchasedLayerCount) {
            additionalLayerPurchasePrompt.reset()
            enforceAdditionalLayerAccess()
        }
        #if HWC_HARDWARE_CAPTURE && !HWC_INTERNAL_BUILD
        .hwcOnChange(of: hardwareKeyboardTestText) { _, newValue in
            handleHardwareLabTextChange(newValue)
        }
        #endif
        #if HWC_INTERNAL_BUILD
        .hwcOnChange(of: hardwareKeyboardTestText) { _, newValue in
            handleHardwareLabTextChange(newValue)
        }
        .hwcOnChange(of: hardwareCalibrationAutoApplyFingerprint) {
            autoApplyHardwareCalibrationIfNeeded()
        }
        .onReceive(hardwareCalibrationTimer) { now in
            guard isHardwareCalibrationTimedFlowActive else { return }
            hardwareCalibrationClock = now
            advanceHardwareCalibrationTimedFlowIfNeeded(now: now)
        }
        #endif
        .hwcOnChange(of: scenePhase) { _, newPhase in
            #if HWC_INTERNAL_BUILD
            syncHardwareKeyMonitor()
            #endif
            if newPhase == .active {
                Task {
                    await languageBrain.consolidate()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            settings.refreshKeyboardStatus()
            refreshClipboardSnippetCount()
        }
        .hwcOnChange(of: showsClipboardSettings) { _, isPresented in
            if isPresented {
                refreshClipboardSnippetCount()
            }
        }
        .sheet(isPresented: $showsClipboardSettings) {
            NavigationView {
                HWKClipboardSettingsView(
                    snippetCount: clipboardSnippetCount,
                    isSuggestionsEnabled: !settings.clipboardDisabled,
                    addSnippetAction: addClipboardSnippetFromPasteboard,
                    clearAllSnippetsAction: clearClipboardSnippets
                )
                .navigationBarTitle("Clipboard Settings", displayMode: .inline)
                .hwcDarkNavigationChrome()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showsClipboardSettings = false
                        }
                    }
                }
                .onAppear {
                    refreshClipboardSnippetCount()
                }
            }
            .navigationViewStyle(.stack)
        }
        .fileImporter(
            isPresented: $showsKeymapFileImporter,
            allowedContentTypes: [.hwcKeymapLayer]
        ) { result in
            switch result {
            case .success(let url):
                prepareKeymapImport(from: url)
            case .failure(let error):
                presentKeymapTransferError(error, title: "Import Failed", operation: .importTransfer)
            }
        }
        .sheet(item: $keymapTransferSheet) { destination in
            switch destination {
            case .importPreview(let preview):
                HWCKeymapImportPreviewSheet(
                    preview: preview,
                    accessMessage: pendingKeymapImportAccessMessage,
                    canImport: canImportKeymapLayer,
                    onImport: applyKeymapImport
                )
            case .exportPreview(let preview):
                HWCKeymapExportPreviewSheet(
                    preview: preview,
                    onExport: beginKeymapExport
                )
            }
        }
        .fileExporter(
            isPresented: $showsKeymapFileExporter,
            document: keymapExportFileDocument,
            contentType: .hwcKeymapLayer,
            defaultFilename: keymapExportFilename
        ) { result in
            handleKeymapExportResult(result)
        }
        .alert(item: $pendingModeChangeKeyEdit) { edit in
            Alert(
                title: Text("Mode Change Key"),
                message: Text(edit.warning),
                primaryButton: .destructive(Text(edit.removesSlot ? "Delete Key" : "Replace Key")) {
                    applyPendingModeChangeKeyEdit(edit)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showsHideKeyboardAgreement) {
            Alert(
                title: Text("Hide Keyboard"),
                message: Text("I agree to not blame the developer and confirm that another keyboard is selected in iOS settings"),
                primaryButton: .destructive(Text("Yes")) {
                    settings.hideKeyboardEnabled = true
                },
                secondaryButton: .cancel(Text("No")) {
                    settings.hideKeyboardEnabled = false
                }
            )
        }
        .sheet(item: $pendingCustomLayerHoldPrompt) { option in
            if let layerID = option.customLayerID,
               let layer = settings.customKeymapLayers.first(where: { $0.id == layerID }) {
                AdditionalLayerHoldEditorSheet(
                    layer: layer,
                    onSave: { title, iconSystemName in
                        saveCustomLayerEdits(
                            layerID: layerID,
                            title: title,
                            iconSystemName: iconSystemName
                        )
                    },
                    onConvert: { style, title, iconSystemName in
                        saveCustomLayerEdits(
                            layerID: layerID,
                            title: title,
                            iconSystemName: iconSystemName
                        )
                        convertCustomLayerFromPrompt(option, to: style)
                    },
                    onDelete: {
                        deleteCustomLayerFromPrompt(option)
                    }
                )
            }
        }
        .sheet(item: $pendingKeyEditor) { item in
            KeyEditorSheet(
                item: item,
                sections: keyEditorSections,
                warningForSave: { value in
                    selectedKeyModeChangeWarning(for: value)
                },
                warningForDelete: {
                    selectedKeyModeChangeWarning
                },
                onSave: { value in
                    setSelectedKeyValueWithoutModeChangeWarning(value)
                },
                onDelete: {
                    deleteSelectedKeyWithoutModeChangeWarning()
                }
            )
        }
        .alert("Save Preset", isPresented: $showsCreateSavedPresetPrompt) {
            TextField("Preset Name", text: $savedPresetName)
            Button("Create") {
                _ = settings.createSavedPreset(title: savedPresetName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the complete current keymap as a reusable preset.")
        }
        .alert("Rename Preset", isPresented: pendingSavedPresetRenameBinding) {
            TextField("Preset Name", text: $savedPresetName)
            Button("Save") {
                if let id = pendingSavedPresetRenameID {
                    settings.renameSavedPreset(id: id, title: savedPresetName)
                }
                pendingSavedPresetRenameID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSavedPresetRenameID = nil
            }
        } message: {
            Text("Rename this saved preset.")
        }
        .alert(keymapImportResultTitle, isPresented: $showsKeymapImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keymapImportResultMessage)
        }
    }

    private var hideKeyboardAgreementBinding: Binding<Bool> {
        Binding(
            get: {
                settings.hideKeyboardEnabled
            },
            set: { newValue in
                if newValue {
                    showsHideKeyboardAgreement = true
                } else {
                    settings.hideKeyboardEnabled = false
                }
            }
        )
    }

    private var pendingSavedPresetRenameBinding: Binding<Bool> {
        Binding(
            get: { pendingSavedPresetRenameID != nil },
            set: { if !$0 { pendingSavedPresetRenameID = nil } }
        )
    }

    private func refreshClipboardSnippetCount() {
        let sharedDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard
        let groupCount = HWKEncryptedClipboardStore.snippetCount(from: sharedDefaults)
        let standardCount = HWKEncryptedClipboardStore.snippetCount(from: .standard)
        clipboardSnippetCount = max(groupCount, standardCount)
    }

    private func addClipboardSnippetFromPasteboard() {
        guard !settings.clipboardDisabled else { return }
        guard let value = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }

        let sharedDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard
        do {
            try HWKEncryptedClipboardStore.autoCaptureSnippet(value, to: sharedDefaults)
            refreshClipboardSnippetCount()
        } catch {
            // Store errors are non-fatal for the app action path.
        }
    }

    private func clearClipboardSnippets() {
        let sharedDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard
        HWKEncryptedClipboardStore.deleteAllSnippets(in: sharedDefaults)
        HWKEncryptedClipboardStore.deleteAllSnippets(in: .standard)
        refreshClipboardSnippetCount()
    }

    private var settingsTab: some View {
        ScrollView {
            tabContentStack {
                settingsDirectTogglesCard
                settingsModePanelCard
                settingsCustomDetails
            }
            .padding(16)
        }
        .background(backgroundColor.ignoresSafeArea())
        .hwcOnChange(of: settingsMode) { _, mode in
            // Ratchet: once the configuration reads as Custom (explicitly
            // chosen or drifted from a preset), stay Custom until the user
            // explicitly picks a preset again.
            if mode == .custom, !usesCustomSettingsMode {
                usesCustomSettingsMode = true
            }
        }
    }

    private var settingsModePanelCard: some View {
        sectionCard(title: "Mode") {
            VStack(spacing: 14) {
                settingsModePickerRow(
                    selection: settingsModeBinding,
                    options: SettingsMode.allCases
                )
            }
        }
    }

    @ViewBuilder
    private var settingsCustomDetails: some View {
        if settingsMode == .custom {
            wordSuggestionsCard
            behaviorCard
            holdActionsCard
        }
    }

    private var settingsDirectTogglesCard: some View {
        sectionCard(title: "Main") {
            VStack(spacing: 14) {
                outlineButton("Open iOS Settings") {
                    openAppSettings()
                }
                toggleRow(
                    title: "Vibration",
                    detail: "Play haptic feedback on key presses. Requires Allow Full Access for the keyboard.",
                    isOn: $settings.vibrationEnabled
                )
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Vibration Strength")
                    Picker("Vibration Strength", selection: $settings.feedbackLevel) {
                        ForEach(KeyboardFeedbackLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(!settings.vibrationEnabled)
                }
                solidButton("Test Vibration", disabled: !settings.vibrationEnabled) {
                    settings.previewFeedback()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(cloudSnapshot.state.title)
                        .font(.headline)
                    Text(cloudSnapshot.state.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if cloudSnapshot.reconcileActivity.phase != .idle {
                        Text(cloudSnapshot.reconcileActivity.summary)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("Managed by iOS Settings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                solidButton("Back Up Now") {
                    cloudSnapshot.reconcileNow()
                }
                NavigationLink {
                    HWCEncryptedBackupHistoryView(controller: cloudSnapshot)
                } label: {
                    HStack {
                        Image(systemName: "externaldrive.badge.icloud")
                        Text("Manage & Restore Backups")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func settingsModePickerRow<Mode: SettingsModeOption>(
        selection: Binding<Mode>,
        options: [Mode]
    ) -> some View {
        let currentMode = selection.wrappedValue

        return Picker("Mode", selection: selection) {
                ForEach(options) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mode. \(currentMode.title)")
    }

    private var settingsMode: SettingsMode {
        if usesCustomSettingsMode {
            return .custom
        }
        let suggestionMode = inferredSuggestionMode
        let keyboardOpenMode = inferredKeyboardOpenMode
        let holdBehaviorMode = inferredHoldBehaviorMode
        if suggestionMode == .standardSoftwareKeyboard &&
            keyboardOpenMode == .standardSoftwareKeyboard &&
            holdBehaviorMode == .standardSoftwareKeyboard {
            return .standardSoftwareKeyboard
        }
        if suggestionMode == .standardHardwareKeyboard &&
            keyboardOpenMode == .standardHardwareKeyboard &&
            holdBehaviorMode == .standardHardwareKeyboard {
            return .standardHardwareKeyboard
        }
        return .custom
    }

    private var settingsModeBinding: Binding<SettingsMode> {
        Binding(
            get: { settingsMode },
            set: { mode in
                applySettingsMode(mode)
            }
        )
    }

    private var inferredSuggestionMode: SettingsMode {
        if settings.autocorrectEnabled &&
            settings.clickToFixEnabled &&
            settings.autocompleteEnabled &&
            settings.suggestionSwipeUpAction == .laneWord &&
            settings.suggestionSwipeDownAction == .rolodex &&
            settings.suggestionSwipeLeftDeleteEnabled &&
            settings.suggestionSwipeRightSpaceEnabled &&
            settings.suggestionHoldForRolodexEnabled &&
            !settings.clipboardDisabled {
            return .standardSoftwareKeyboard
        }
        if settings.autocorrectEnabled &&
            settings.clickToFixEnabled &&
            settings.autocompleteEnabled &&
            settings.suggestionSwipeUpAction == .rolodex &&
            settings.suggestionSwipeDownAction == .hideExpanded &&
            settings.suggestionSwipeLeftDeleteEnabled &&
            settings.suggestionSwipeRightSpaceEnabled &&
            settings.suggestionHoldForRolodexEnabled &&
            !settings.clipboardDisabled {
            return .standardHardwareKeyboard
        }
        return .custom
    }

    private var inferredKeyboardOpenMode: SettingsMode {
        if settings.startExpanded &&
            !settings.defaultSymbolLayer &&
            !settings.hideKeyboardEnabled {
            return .standardSoftwareKeyboard
        }
        if !settings.startExpanded &&
            settings.defaultSymbolLayer &&
            !settings.hideKeyboardEnabled {
            return .standardHardwareKeyboard
        }
        return .custom
    }

    private var inferredHoldBehaviorMode: SettingsMode {
        if settings.capsHoldToLockEnabled &&
            settings.capsHoldDurationMs == 200 &&
            settings.menuHoldToLatchEnabled &&
            settings.menuHoldDurationMs == 200 &&
            settings.keyHoldDurationMs == 200 &&
            settings.menuTapLockWindowMs == 0 &&
            settings.deleteHoldEnabled &&
            settings.deleteHoldWordsBeforeSentence == 5 {
            return .standardSoftwareKeyboard
        }
        if settings.capsHoldToLockEnabled &&
            settings.capsHoldDurationMs == 200 &&
            settings.menuHoldToLatchEnabled &&
            settings.menuHoldDurationMs == 200 &&
            settings.keyHoldDurationMs == 200 &&
            settings.menuTapLockWindowMs == 400 &&
            settings.deleteHoldEnabled &&
            settings.deleteHoldWordsBeforeSentence == 5 {
            return .standardHardwareKeyboard
        }
        return .custom
    }

    private func applySettingsMode(_ mode: SettingsMode) {
        guard mode != .custom else {
            usesCustomSettingsMode = true
            return
        }

        usesCustomSettingsMode = false
        settings.applyTransaction { settings in
            let holdDurationMs = 200
            switch mode {
            case .standardSoftwareKeyboard:
                settings.autocorrectEnabled = true
                settings.clickToFixEnabled = true
                settings.autocompleteEnabled = true
                settings.suggestionSwipeUpAction = .laneWord
                settings.suggestionSwipeDownAction = .rolodex
                settings.suggestionSwipeLeftDeleteEnabled = true
                settings.suggestionSwipeRightSpaceEnabled = true
                settings.suggestionHoldForRolodexEnabled = true
                settings.clipboardDisabled = false
                settings.startExpanded = true
                settings.defaultSymbolLayer = false
                settings.doubleSpacePeriodEnabled = true
                settings.capitalizeFirstLetterEnabled = true
                settings.hideKeyboardEnabled = false
                settings.capsHoldToLockEnabled = true
                settings.capsHoldDurationMs = holdDurationMs
                settings.menuHoldToLatchEnabled = true
                settings.menuHoldDurationMs = holdDurationMs
                settings.keyHoldDurationMs = holdDurationMs
                settings.menuTapLockWindowMs = 0
                settings.deleteHoldEnabled = true
                settings.deleteHoldWordsBeforeSentence = 5
            case .standardHardwareKeyboard:
                settings.autocorrectEnabled = true
                settings.clickToFixEnabled = true
                settings.autocompleteEnabled = true
                settings.suggestionSwipeUpAction = .rolodex
                settings.suggestionSwipeDownAction = .hideExpanded
                settings.suggestionSwipeLeftDeleteEnabled = true
                settings.suggestionSwipeRightSpaceEnabled = true
                settings.suggestionHoldForRolodexEnabled = true
                settings.clipboardDisabled = false
                settings.startExpanded = false
                settings.defaultSymbolLayer = true
                settings.doubleSpacePeriodEnabled = true
                settings.capitalizeFirstLetterEnabled = true
                settings.hideKeyboardEnabled = false
                settings.capsHoldToLockEnabled = true
                settings.capsHoldDurationMs = holdDurationMs
                settings.menuHoldToLatchEnabled = true
                settings.menuHoldDurationMs = holdDurationMs
                settings.keyHoldDurationMs = holdDurationMs
                settings.menuTapLockWindowMs = 400
                settings.deleteHoldEnabled = true
                settings.deleteHoldWordsBeforeSentence = 5
            case .custom:
                break
            }
        }
    }

    private var autocorrectTab: some View {
        ScrollView {
            tabContentStack {
                autobotCard
                autocorrectSuggestionBarCard
                hardwareKeyboardCard
            }
            .padding(16)
        }
        .background(backgroundColor.ignoresSafeArea())
        .sheet(item: $selectedAutocorrectSlot) { selection in
            AutocorrectSlotSheet(
                settings: settings,
                laneID: selection.id,
                slotTitle: autocorrectLanePositionTitle(selection.id),
                customTextRules: settings.customTextRules
            )
        }
        .sheet(item: $selectedAutocorrectTaughtRule) { selection in
            if let rule = settings.customTextRules.first(where: { $0.id == selection.id }) {
                AutocorrectTaughtRuleSheet(
                    settings: settings,
                    rule: rule,
                    sourceCode: customTextRuleCodeBinding(rule.id),
                    isInLane: { laneID in
                        settings.autocorrectLogicLanes
                            .first { $0.id == laneID }?
                            .blocks.contains { $0.customTextRuleID == rule.id } ?? false
                    },
                    setInLane: { laneID, isOn in
                        if isOn {
                            addCustomTextRuleBlock(rule, laneID: laneID)
                        } else {
                            removeCustomTextRuleBlock(rule.id, laneID: laneID)
                        }
                    },
                    onDelete: {
                        removeCustomTextRule(id: rule.id)
                        selectedAutocorrectTaughtRule = nil
                    }
                )
            }
        }
    }

    private var hardwareKeyboardCard: some View {
        sectionCard(
            title: "Hardware Keyboard Reading removed",
            detail: "We’re sorry. Hardware Keyboard Reading is no longer available in HWC, and we know this disrupts people who relied on it."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your saved keyboard layouts, settings, and purchase records are preserved. If you purchased Reader or supported HWC for this feature, please contact support about your purchase.")
                    .fixedSize(horizontal: false, vertical: true)
                Link("Contact HWC Support", destination: URL(string: "https://hwkc.tech/support/")!)
                outlineButton(hardwarePremiumStore.isRestoring ? "Restoring..." : "Restore Previous Reader Purchase") {
                    hardwarePremiumStore.restorePurchases()
                }
                .disabled(hardwarePremiumStore.isBusy)
                if let message = hardwarePremiumStore.statusMessage {
                    Text(message).fixedSize(horizontal: false, vertical: true)
                }
                if let error = hardwarePremiumStore.errorMessage {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("hardware.reading.retired")
    }

    private var hardwareKeyboardControlsCard: some View {
        sectionCard(
            title: "Hardware Keyboard",
            detail: "Read connected hardware-keyboard input and use arrow-key chords to choose autocorrect words while HWC Keyboard is active."
        ) {
            VStack(spacing: 14) {
                if isHardwarePremiumLocked {
                    hardwarePremiumLockedPurchaseWarning
                } else {
                    toggleRow(
                        title: "Reading",
                        detail: "Use hardware keyboard input while HWC Keyboard is active.",
                        isOn: hardwareKeypressReadingBinding
                    )
                    .accessibilityIdentifier("hardware.reading.toggle")

                    toggleRow(
                        title: "Selector",
                        detail: "Use hardware arrow keys and a modifier to choose autocorrect words.",
                        isOn: hardwareAutocorrectSelectorBinding
                    )

                    hardwareAutocorrectSelectorControls
                        .disabled(!settings.hardwareAutocorrectSelectorEnabled)
                        .opacity(settings.hardwareAutocorrectSelectorEnabled ? 1 : 0.55)

                    physicalReturnBehaviorControl
                }

                hardwareKeyboardSetupInstructions

                VStack(alignment: .leading, spacing: 8) {
                    canvasRowHeader(
                        title: "Hardware Keyboard Test",
                        detail: hardwareKeyboardTestEnabled
                            ? "The onscreen keyboard opens, but only connected hardware keyboard typing is accepted."
                            : "Turn on Reading before testing the connected hardware keyboard."
                    )
                    hardwareKeyboardTestField
                        .opacity(hardwareKeyboardTestEnabled ? 1 : 0.55)
                }
            }
        }
    }

    private var hardwareAutocorrectSelectorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Initiation Key", selection: $settings.hardwareAutocorrectSelectorInitiationKey) {
                ForEach(KeyboardHardwareAutocorrectSelectorInitiationKey.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            Picker("Select Key", selection: $settings.hardwareAutocorrectSelectorSelectionKey) {
                ForEach(KeyboardHardwareAutocorrectSelectorSelectionKey.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            featureBullet("Hold the initiation key and press an arrow to start choosing — arrows stop moving the cursor while you choose.")
            featureBullet("Up/Down picks the middle word and rolls more choices. Left/Right picks the side words.")
            featureBullet("The select key inserts the highlighted word. Esc or typing goes back to normal.")
        }
    }

    private var physicalReturnBehaviorControl: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker("Physical Return", selection: $settings.physicalReturnBehavior) {
                ForEach(KeyboardPhysicalReturnBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }
            .pickerStyle(.menu)

            Text(settings.physicalReturnBehavior.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Software Return remains host-labelled Return and inserts a newline. It cannot invoke a generic Send action.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var autobotCard: some View {
        sectionCard(title: "Autobot", detail: "One private local brain for learned logic and My Rules.") {
            VStack(alignment: .leading, spacing: 14) {
                autobotLogicContent

                Rectangle()
                    .fill(previewTileBorder.opacity(0.65))
                    .frame(height: 0.5)

                sectionLabel("My Rules")
                autobotRulesContent
            }
        }
    }

    private var autobotLogicContent: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tabAccentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(languageBrain.status.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text(languageBrain.snapshot.source == .onDeviceFoundationModel
                            ? "Apple on-device model"
                            : "Private local fallback")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(subtleTextColor)
                    }

                    Spacer()

                    Text("LOCAL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(tabAccentColor)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(buttonSurface(fill: tabAccentColor.opacity(0.10)))
                }

                Rectangle()
                    .fill(previewTileBorder.opacity(0.55))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Intent")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(tabAccentColor)
                        .textCase(.uppercase)
                    Text(languageBrain.snapshot.policies.first?.intent
                        ?? "Understand what you meant from corrections you accept and undo.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Decision")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(tabAccentColor)
                        .textCase(.uppercase)
                    Text(languageBrain.snapshot.policies.first?.decision
                        ?? "Keep the baseline until one behavior has at least three matching decisions.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(subtleTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Text("\(languageBrain.observedDecisionCount) local decision\(languageBrain.observedDecisionCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(subtleTextColor)

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        settings.resetAutocorrectLearning()
                        languageBrain.reset()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                    }
                    .hwcCompanionActionStyle(.destructive, tint: tabAccentColor)
                    .accessibilityLabel("Reset learned typing")
                }
        }
    }

    private var autobotRulesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
                autobotRuleHypothesisList
                autobotRomanizedHypothesisList

                if languageBrain.snapshot.policies.isEmpty &&
                    autobotRuleHypothesisStore.pendingHypotheses().isEmpty &&
                    autobotRomanizedHypothesisStore.pendingHypotheses().isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(tabAccentColor)
                            .padding(.top, 1)
                        Text("Nothing to configure. HWC creates a rule only after the same choice happens at least three times.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(subtleTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(languageBrain.snapshot.policies) { policy in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Image(systemName: languageBrainPolicyIcon(policy.kind))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(tabAccentColor)
                                Text(languageBrainPolicyTitle(policy.kind))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(Int(policy.confidence * 100))%")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(subtleTextColor)
                                Button(role: .destructive) {
                                    languageBrain.forget(policyID: policy.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color.red.opacity(0.75))
                                }
                                .buttonStyle(StaticPressButtonStyle())
                                .accessibilityLabel("Forget learned rule")
                            }

                            Text(policy.intent)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(policy.decision)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(subtleTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Based on \(policy.evidenceCount) matching decisions")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(subtleTextColor.opacity(0.85))
                        }
                        .padding(11)
                        .background(buttonSurface(fill: Color.white.opacity(0.035)))

                        if policy.id != languageBrain.snapshot.policies.last?.id {
                            Rectangle()
                                .fill(previewTileBorder.opacity(0.45))
                                .frame(height: 0.5)
                        }
                    }
                }
        }
    }

    private var autobotRuleHypothesisStore: HWKAutobotRuleHypothesisStore {
        HWKAutobotRuleHypothesisStore()
    }

    private var autobotRomanizedHypothesisStore: HWKAutobotRomanizedHypothesisStore {
        HWKAutobotRomanizedHypothesisStore()
    }

    private var autobotRuleHypothesisList: some View {
        let hypotheses = autobotRuleHypothesisStore.pendingHypotheses()
        return Group {
            if !hypotheses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Autobot hypotheses")
                    ForEach(hypotheses) { hypothesis in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.max.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(tabAccentColor)
                                Text("\(hypothesis.source) → \(hypothesis.replacement)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(Int(hypothesis.confidence * 100))%")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(subtleTextColor)
                            }

                            Text(hypothesis.explanation)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(subtleTextColor)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                Button("Teach rule") {
                                    teachAutobotRuleHypothesis(hypothesis)
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(StaticPressButtonStyle())
                                .foregroundColor(tabAccentColor)

                                Button("Not for me", role: .destructive) {
                                    rejectAutobotRuleHypothesis(hypothesis)
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(StaticPressButtonStyle())
                            }
                        }
                        .padding(11)
                        .background(buttonSurface(fill: Color.white.opacity(0.035)))
                    }
                }
            }
        }
    }

    private func teachAutobotRuleHypothesis(_ hypothesis: HWKAutobotRuleHypothesis) {
        guard let rule = HWKNaturalLanguageRuleModel.customTextRule(
            source: hypothesis.source,
            replacement: hypothesis.replacement
        ) else {
            typedTextRuleGenerationMessage = "This hypothesis needs more review before it can become a rule."
            return
        }
        autocorrectUndoSnapshot = AutocorrectUndoSnapshot(
            customTextRules: settings.customTextRules,
            logicBlocks: settings.autocorrectLogicBlocks,
            logicLanes: settings.autocorrectLogicLanes,
            recipe: settings.autocorrectLogicRecipe,
            message: "Autobot rule taught."
        )
        addCustomTextRule(rule)
        _ = autobotRuleHypothesisStore.confirm(id: hypothesis.id)
        typedTextRuleGenerationMessage = "Taught as a suggestion-only My Rule."
    }

    private func rejectAutobotRuleHypothesis(_ hypothesis: HWKAutobotRuleHypothesis) {
        guard autobotRuleHypothesisStore.reject(id: hypothesis.id) else { return }
        typedTextRuleGenerationMessage = "Hypothesis dismissed. Autobot needs three new matching decisions before asking again."
    }

    private var autobotRomanizedHypothesisList: some View {
        let hypotheses = autobotRomanizedHypothesisStore.pendingHypotheses()
        return Group {
            if !hypotheses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Romanized-language hypotheses")
                    ForEach(hypotheses) { hypothesis in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "character.book.closed.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(tabAccentColor)
                                Text("\(hypothesis.romanizedText) → \(hypothesis.nativeScriptText)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(Int(hypothesis.confidence * 100))%")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(subtleTextColor)
                            }

                            Text(hypothesis.explanation)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(subtleTextColor)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                Button("Teach suggestion") {
                                    teachAutobotRomanizedHypothesis(hypothesis)
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(StaticPressButtonStyle())
                                .foregroundColor(tabAccentColor)

                                Button("Not for me", role: .destructive) {
                                    rejectAutobotRomanizedHypothesis(hypothesis)
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(StaticPressButtonStyle())
                            }
                        }
                        .padding(11)
                        .background(buttonSurface(fill: Color.white.opacity(0.035)))
                    }
                }
            }
        }
    }

    private func teachAutobotRomanizedHypothesis(
        _ hypothesis: HWKAutobotRomanizedHypothesis
    ) {
        guard let rule = HWKNaturalLanguageRuleModel.customTextRule(
            source: hypothesis.romanizedText,
            replacement: hypothesis.nativeScriptText
        ) else {
            typedTextRuleGenerationMessage = "This romanized-language hypothesis needs more review."
            return
        }
        autocorrectUndoSnapshot = AutocorrectUndoSnapshot(
            customTextRules: settings.customTextRules,
            logicBlocks: settings.autocorrectLogicBlocks,
            logicLanes: settings.autocorrectLogicLanes,
            recipe: settings.autocorrectLogicRecipe,
            message: "Romanized-language suggestion taught."
        )
        addCustomTextRule(rule)
        _ = autobotRomanizedHypothesisStore.confirm(id: hypothesis.id)
        typedTextRuleGenerationMessage = "Taught as a suggestion-only My Rule."
    }

    private func rejectAutobotRomanizedHypothesis(
        _ hypothesis: HWKAutobotRomanizedHypothesis
    ) {
        guard autobotRomanizedHypothesisStore.reject(id: hypothesis.id) else { return }
        typedTextRuleGenerationMessage = "Romanized-language hypothesis dismissed. Three new matching choices are required."
    }

    private func languageBrainPolicyTitle(_ kind: HWKLanguageBrainPolicyKind) -> String {
        switch kind {
        case .preferReplacement: return "Prefer correction"
        case .suppressReplacement: return "Stop correction"
        case .protectTerm: return "Protect term"
        }
    }

    private func languageBrainPolicyIcon(_ kind: HWKLanguageBrainPolicyKind) -> String {
        switch kind {
        case .preferReplacement: return "checkmark.circle.fill"
        case .suppressReplacement: return "hand.raised.fill"
        case .protectTerm: return "lock.fill"
        }
    }

    private var autocorrectSuggestionBarCard: some View {
        sectionCard(title: "Suggestion Bar") {
            VStack(alignment: .leading, spacing: 14) {
                autocorrectSuggestionBarPreview

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Visible Suggestions")
                    Picker("Visible Suggestions", selection: $settings.suggestionVisibleWordCount) {
                        ForEach(KeyboardLayoutBounds.suggestionVisibleWordCounts, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                }

            }
        }
    }

    private var autocorrectNaturalLanguageComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Write one rule in plain English. It stays on this device.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(subtleTextColor)

            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $autocorrectRuleText,
                    prompt: Text("Example: replace brb with be right back")
                        .foregroundColor(subtleTextColor.opacity(0.82))
                )
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .onSubmit { compileAutocorrectRuleFromText() }

                if isCompilingAutocorrectRule {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Button {
                        compileAutocorrectRuleFromText()
                    } label: {
                        Label("Add rule", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(canCompileAutocorrectRule ? tabAccentColor : subtleTextColor.opacity(0.5))
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                            .background(buttonSurface(fill: canCompileAutocorrectRule ? tabAccentColor.opacity(0.12) : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(StaticPressButtonStyle())
                    .disabled(!canCompileAutocorrectRule)
                    .accessibilityLabel("Add rule")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(buttonSurface(fill: buttonBackgroundFill.opacity(0.85)))
            .overlay(buttonSurfaceStroke(previewTileBorder.opacity(0.7)))

            HStack(spacing: 8) {
                Button {
                    generateCustomRulesFromTypedTextSamples()
                } label: {
                    Label("Learn from typing", systemImage: "text.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tabAccentColor)
                }
                .buttonStyle(StaticPressButtonStyle())

                Spacer()

                Text("\(settings.customTextRules.count) saved")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(subtleTextColor)
            }

            if let snapshot = autocorrectUndoSnapshot {
                HStack(spacing: 5) {
                    Text(snapshot.message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(subtleTextColor)

                    Button {
                        undoAutocorrectChange()
                    } label: {
                        Text("Undo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(tabAccentColor)
                    }
                    .buttonStyle(StaticPressButtonStyle())
                }
            }

            if let typedTextRuleGenerationMessage {
                Text(typedTextRuleGenerationMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(subtleTextColor)
            }
        }
    }

    private var canCompileAutocorrectRule: Bool {
        !autocorrectRuleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCompilingAutocorrectRule
    }

    private var customTextRuleList: some View {
        Group {
            if !settings.customTextRules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Taught rules")

                    VStack(spacing: 0) {
                        ForEach(settings.customTextRules) { rule in
                            customTextRuleRow(rule)

                            if rule.id != settings.customTextRules.last?.id {
                                Rectangle()
                                    .fill(previewTileBorder.opacity(0.55))
                                    .frame(height: 0.5)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .background(buttonSurface(fill: buttonBackgroundFill.opacity(0.6)))
                    .overlay(buttonSurfaceStroke(previewTileBorder.opacity(0.6)))
                }
            }
        }
    }

    private func customTextRuleRow(_ rule: HWKCustomTextRule) -> some View {
        let needsRecipe = rule.sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            selectedAutocorrectTaughtRule = AutocorrectTaughtRuleSelection(id: rule.id)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                if needsRecipe {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.94, green: 0.69, blue: 0.18))
                        .accessibilityLabel("Needs attention")
                }

                Text(HWKNaturalLanguageRuleModel.customTextRuleSummary(rule))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(subtleTextColor.opacity(0.7))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StaticPressButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                removeCustomTextRule(id: rule.id)
            } label: {
                Label("Delete rule", systemImage: "trash")
            }
        }
    }

    private var autocorrectModeMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Mode")
            autocorrectBehaviorPicker
        }
    }

    private var autocorrectBehaviorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                ForEach(AutocorrectBehaviorOption.allCases) { option in
                    Button {
                        selectAutocorrectBehavior(option)
                    } label: {
                        if currentAutocorrectBehavior == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(currentAutocorrectBehavior?.title ?? "Custom")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(subtleTextColor)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(buttonSurface(fill: buttonBackgroundFill.opacity(0.72)))
                .overlay(buttonSurfaceStroke(previewTileBorder.opacity(0.65)))
            }
            .buttonStyle(StaticPressButtonStyle())

            Text(autocorrectBehaviorCaption)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(subtleTextColor)
        }
    }

    private var currentAutocorrectBehavior: AutocorrectBehaviorOption? {
        guard settings.autocorrectEnabled else { return .off }
        switch settings.autocorrectLogicRecipe {
        case .strict:
            return .careful
        case .balanced:
            return .balanced
        case .savedWordsFirst:
            return .savedWordsFirst
        case .dictionaryFirst:
            return .dictionaryFirst
        case .custom:
            return nil
        }
    }

    private var autocorrectBehaviorCaption: String {
        currentAutocorrectBehavior?.caption ?? "Tuned by hand. Pick a preset to start over."
    }

    private func selectAutocorrectBehavior(_ option: AutocorrectBehaviorOption) {
        if option == .off {
            settings.autocorrectEnabled = false
            return
        }
        settings.autocorrectEnabled = true
        if let recipe = option.recipe {
            applyAutocorrectLogicRecipe(recipe)
        }
    }

    private var autocorrectSuggestionBarPreview: some View {
        let lanes = settings.autocorrectLogicLanes
            .sorted { $0.id < $1.id }
            .prefix(settings.suggestionVisibleWordCount)
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lanes) { lane in
                        autocorrectSlotButton(lane)
                            .frame(width: autocorrectSuggestionPreviewSlotWidth)
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 48)

            Text("Tap a slot to change what it shows.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(subtleTextColor)
        }
    }

    private var autocorrectSuggestionPreviewSlotWidth: CGFloat { 112 }

    private func autocorrectSlotButton(_ lane: KeyboardAutocorrectLogicLane) -> some View {
        Button {
            selectedAutocorrectSlot = AutocorrectSlotSelection(id: lane.id)
        } label: {
            VStack(spacing: 3) {
                Text(autocorrectSlotSampleWord(for: lane))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text(lane.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(subtleTextColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StaticPressButtonStyle())
        .background(buttonSurface(fill: previewTileFill))
        .overlay(buttonSurfaceStroke(previewTileBorder.opacity(0.7)))
        .accessibilityLabel("\(autocorrectLanePositionTitle(lane.id)). Shows \(lane.title)")
    }

    private func autocorrectSlotSampleWord(for lane: KeyboardAutocorrectLogicLane) -> String {
        ["next", "the", "keyboard", "word", "their", "saved", "phrase", "typed", "more"]
            .indices.contains(lane.id)
            ? ["next", "the", "keyboard", "word", "their", "saved", "phrase", "typed", "more"][lane.id]
            : "word"
    }

    private func customTextRuleCodeBinding(_ ruleID: UUID) -> Binding<String> {
        Binding(
            get: {
                settings.customTextRules.first { $0.id == ruleID }?.sourceCode ?? ""
            },
            set: { newCode in
                guard let index = settings.customTextRules.firstIndex(where: { $0.id == ruleID }) else {
                    return
                }
                var rules = settings.customTextRules
                if let script = try? HWKRuleScriptCodeCodec.parse(newCode) {
                    rules[index] = rules[index].replacingSourceCode(newCode, script: script)
                } else {
                    rules[index].sourceCode = newCode
                }
                settings.customTextRules = rules
            }
        )
    }

    private func compileAutocorrectRuleFromText() {
        let text = autocorrectRuleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isCompilingAutocorrectRule else { return }
        isCompilingAutocorrectRule = true
        typedTextRuleGenerationMessage = nil
        Task {
            let result = await HWKNaturalLanguageRuleModel().draft(from: text)
            await MainActor.run {
                isCompilingAutocorrectRule = false
                applyAutocorrectDraft(result.draft)
                autocorrectRuleText = ""
            }
        }
    }

    private func generateCustomRulesFromTypedTextSamples() {
        let generatedRules = HWKNaturalLanguageRuleModel.generatedCustomTextRules()
        guard !generatedRules.isEmpty else {
            typedTextRuleGenerationMessage = "No local typing patterns ready yet."
            return
        }

        let existingNames = Set(settings.customTextRules.map { $0.name.lowercased() })
        var added = 0
        for rule in generatedRules where !existingNames.contains(rule.name.lowercased()) {
            addCustomTextRule(rule)
            added += 1
        }
        typedTextRuleGenerationMessage = added == 0
            ? "Typing patterns already saved."
            : "Generated \(added) saved rule\(added == 1 ? "" : "s") from typing."
    }

    private func applyAutocorrectDraft(_ draft: HWKNaturalLanguageRuleModel.Draft) {
        let message: String
        switch draft {
        case .autocorrect:
            message = "Correction rules updated."
        case .customText:
            message = "Rule added."
        }

        autocorrectUndoSnapshot = AutocorrectUndoSnapshot(
            customTextRules: settings.customTextRules,
            logicBlocks: settings.autocorrectLogicBlocks,
            logicLanes: settings.autocorrectLogicLanes,
            recipe: settings.autocorrectLogicRecipe,
            message: message
        )

        switch draft {
        case .autocorrect(let autocorrectDraft):
            let blocks = HWKAutocorrectRuleCompiler.blocks(for: autocorrectDraft)
            assignAutocorrectLogicBlocks(blocks)
            settings.autocorrectLogicRecipe = .custom
        case .customText(let rule):
            addCustomTextRule(rule)
        }
    }

    private func undoAutocorrectChange() {
        guard let snapshot = autocorrectUndoSnapshot else { return }
        settings.customTextRules = snapshot.customTextRules
        settings.autocorrectLogicBlocks = snapshot.logicBlocks
        settings.autocorrectLogicLanes = snapshot.logicLanes
        settings.autocorrectLogicRecipe = snapshot.recipe
        autocorrectUndoSnapshot = nil
    }

    private func addCustomTextRule(_ rule: HWKCustomTextRule) {
        var rules = settings.customTextRules
        guard !rules.contains(where: { $0.id == rule.id || $0.name.caseInsensitiveCompare(rule.name) == .orderedSame }) else {
            return
        }
        rules.append(rule)
        settings.customTextRules = rules
        addCustomTextRuleBlock(rule)
    }

    private func removeCustomTextRule(id: UUID) {
        settings.customTextRules = settings.customTextRules.filter { $0.id != id }
        settings.autocorrectLogicLanes = settings.autocorrectLogicLanes.map { lane in
            var copy = lane
            copy.blocks.removeAll { $0.customTextRuleID == id }
            return copy
        }
    }

    private func addCustomTextRuleBlock(_ rule: HWKCustomTextRule) {
        let laneID = customTextRuleLaneID(for: rule)
        addCustomTextRuleBlock(rule, laneID: laneID)
    }

    private func addCustomTextRuleBlock(_ rule: HWKCustomTextRule, laneID: Int) {
        guard let laneIndex = settings.autocorrectLogicLanes.firstIndex(where: { $0.id == laneID }) else {
            return
        }
        var lane = settings.autocorrectLogicLanes[laneIndex].replacingLaneIntent(with: .correctionLane)
        if !lane.blocks.contains(where: { $0.customTextRuleID == rule.id }) {
            lane.blocks.append(
                newAutocorrectLogicBlock(
                    .customTextRule,
                    rankPriority: lane.blocks.count,
                    fallbackTargetID: lane.blocks.first { $0.role == .gate }?.id,
                    customTextRuleID: rule.id
                )
            )
        }
        assignAutocorrectLogicBlocks(lane.blocks, laneID: laneID)
        settings.autocorrectLogicRecipe = .custom
    }

    private func customTextRuleLaneID(for rule: HWKCustomTextRule) -> Int {
        switch rule.trigger {
        case .onWordCommit, .onSentenceEnd:
            return 1
        case .onManualInvoke:
            return 2
        }
    }

    private func removeCustomTextRuleBlock(_ ruleID: UUID, laneID: Int) {
        guard let lane = settings.autocorrectLogicLanes.first(where: { $0.id == laneID }) else { return }
        let remaining = lane.blocks.filter { $0.customTextRuleID != ruleID }
        assignAutocorrectLogicBlocks(remaining, laneID: laneID)
    }

    private func autocorrectLanePositionTitle(_ laneID: Int) -> String {
        return "Slot \(laneID + 1)"
    }

    private func assignAutocorrectLogicBlocks(_ blocks: [KeyboardAutocorrectLogicBlock]) {
        let firstGateID = blocks.first { $0.role == .gate }?.id
        let rankedBlocks = blocks.sorted { lhs, rhs in
            if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.rankPriority < rhs.rankPriority
        }
        settings.autocorrectLogicBlocks = Array(rankedBlocks.prefix(12)).enumerated().map { index, block in
            KeyboardAutocorrectLogicBlock(
                id: block.id,
                kind: block.kind,
                rankPriority: index,
                fallbackEnabled: block.fallbackEnabled || block.role == .fallback,
                dictionaryWeight: min(max(block.dictionaryWeight, 0), 1),
                savedWordsWeight: min(max(block.savedWordsWeight, 0), 1),
                acceptanceThreshold: min(max(block.acceptanceThreshold, 0), 1),
                fallbackTargetID: block.fallbackTargetID ?? (block.role == .fallback ? firstGateID : nil),
                chipColor: block.chipColor,
                customTextRuleID: block.customTextRuleID
            )
        }
    }

    private func assignAutocorrectLogicBlocks(_ blocks: [KeyboardAutocorrectLogicBlock], laneID: Int) {
        guard let laneIndex = settings.autocorrectLogicLanes.firstIndex(where: { $0.id == laneID }) else {
            return
        }
        let firstGateID = blocks.first { $0.role == .gate }?.id
        let rankedBlocks = blocks.sorted { lhs, rhs in
            if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.rankPriority < rhs.rankPriority
        }
        var lanes = settings.autocorrectLogicLanes
        lanes[laneIndex].blocks = Array(rankedBlocks.prefix(12)).enumerated().map { index, block in
            KeyboardAutocorrectLogicBlock(
                id: block.id,
                kind: block.kind,
                rankPriority: index,
                fallbackEnabled: block.fallbackEnabled || block.role == .fallback,
                dictionaryWeight: min(max(block.dictionaryWeight, 0), 1),
                savedWordsWeight: min(max(block.savedWordsWeight, 0), 1),
                acceptanceThreshold: min(max(block.acceptanceThreshold, 0), 1),
                fallbackTargetID: block.fallbackTargetID ?? (block.role == .fallback ? firstGateID : nil),
                chipColor: block.chipColor,
                customTextRuleID: block.customTextRuleID
            )
        }
        settings.autocorrectLogicLanes = lanes
    }

    private func applyAutocorrectLogicRecipe(_ recipe: KeyboardAutocorrectLogicRecipe) {
        settings.autocorrectLogicRecipe = recipe
        guard recipe != .custom else { return }
        let blocks = autocorrectLogicBlocks(for: recipe)
        assignAutocorrectLogicBlocks(blocks)
        settings.autocorrectLogicLanes = autocorrectLogicLanes(for: recipe)
    }

    private func autocorrectLogicLanes(for recipe: KeyboardAutocorrectLogicRecipe) -> [KeyboardAutocorrectLogicLane] {
        KeyboardAutocorrectLogicLane.defaultLanes.map { lane in
            KeyboardAutocorrectLogicLane(
                id: lane.id,
                title: lane.title,
                family: lane.family,
                reason: lane.reason,
                blocks: autocorrectLogicBlocks(for: recipe, lane: lane)
            )
        }
    }

    private func autocorrectLogicBlocks(
        for recipe: KeyboardAutocorrectLogicRecipe,
        lane: KeyboardAutocorrectLogicLane
    ) -> [KeyboardAutocorrectLogicBlock] {
        switch lane.effectiveFamily {
        case .previousWord:
            return lane.blocks
        case .correction:
            switch recipe {
            case .strict:
                return autocorrectCorrectionBlocks(threshold: 0.92)
            case .dictionaryFirst:
                return autocorrectCorrectionBlocks(threshold: 0.82)
            case .savedWordsFirst:
                return autocorrectCorrectionBlocks(threshold: 0.82)
            case .balanced, .custom:
                return lane.blocks
            }
        case .completion:
            switch recipe {
            case .savedWordsFirst:
                return autocorrectCompletionBlocks(savedWordsWeight: 0.75, dictionaryWeight: 0.25, threshold: 0.78, dictionaryFirst: false)
            case .dictionaryFirst:
                return autocorrectCompletionBlocks(savedWordsWeight: 0.25, dictionaryWeight: 0.75, threshold: 0.78, dictionaryFirst: true)
            case .strict:
                return autocorrectCompletionBlocks(savedWordsWeight: 0.35, dictionaryWeight: 0.65, threshold: 0.92, dictionaryFirst: true)
            case .balanced, .custom:
                return lane.blocks
            }
        }
    }

    private func autocorrectCorrectionBlocks(threshold: Double) -> [KeyboardAutocorrectLogicBlock] {
        let gateID = UUID()
        return [
            newAutocorrectLogicBlock(.correctionLane, rankPriority: 0, fallbackTargetID: nil),
            newAutocorrectLogicBlock(.nativeSpellChecker, rankPriority: 1, fallbackTargetID: nil),
            newAutocorrectLogicBlock(.coreML, rankPriority: 2, fallbackTargetID: nil),
            KeyboardAutocorrectLogicBlock(
                id: gateID,
                kind: .confidenceGate,
                rankPriority: 3,
                acceptanceThreshold: threshold
            ),
            KeyboardAutocorrectLogicBlock(
                kind: .highlightTypedWord,
                rankPriority: 4
            ),
            KeyboardAutocorrectLogicBlock(
                kind: .strictFallback,
                rankPriority: 5,
                fallbackEnabled: true,
                fallbackTargetID: gateID
            ),
        ]
    }

    private func autocorrectCompletionBlocks(
        savedWordsWeight: Double,
        dictionaryWeight: Double,
        threshold: Double,
        dictionaryFirst: Bool
    ) -> [KeyboardAutocorrectLogicBlock] {
        [
            newAutocorrectLogicBlock(.completionLane, rankPriority: 0, fallbackTargetID: nil),
        ] + shiftedAutocorrectBlocks(
            autocorrectLogicPreset(
                savedWordsWeight: savedWordsWeight,
                dictionaryWeight: dictionaryWeight,
                threshold: threshold,
                dictionaryFirst: dictionaryFirst
            ),
            by: 1
        )
    }

    private func shiftedAutocorrectBlocks(
        _ blocks: [KeyboardAutocorrectLogicBlock],
        by offset: Int
    ) -> [KeyboardAutocorrectLogicBlock] {
        blocks.map { block in
            KeyboardAutocorrectLogicBlock(
                id: block.id,
                kind: block.kind,
                rankPriority: block.rankPriority + offset,
                fallbackEnabled: block.fallbackEnabled,
                dictionaryWeight: block.dictionaryWeight,
                savedWordsWeight: block.savedWordsWeight,
                acceptanceThreshold: block.acceptanceThreshold,
                fallbackTargetID: block.fallbackTargetID,
                chipColor: block.chipColor
            )
        }
    }

    private func autocorrectLogicBlocks(for recipe: KeyboardAutocorrectLogicRecipe) -> [KeyboardAutocorrectLogicBlock] {
        switch recipe {
        case .balanced, .custom:
            return KeyboardAutocorrectLogicBlock.defaultPipeline
        case .savedWordsFirst:
            return autocorrectLogicPreset(savedWordsWeight: 0.75, dictionaryWeight: 0.25, threshold: 0.78, dictionaryFirst: false)
        case .dictionaryFirst:
            return autocorrectLogicPreset(savedWordsWeight: 0.25, dictionaryWeight: 0.75, threshold: 0.78, dictionaryFirst: true)
        case .strict:
            return autocorrectLogicPreset(savedWordsWeight: 0.35, dictionaryWeight: 0.65, threshold: 0.92, dictionaryFirst: true)
        }
    }

    private func autocorrectLogicPreset(
        savedWordsWeight: Double,
        dictionaryWeight: Double,
        threshold: Double,
        dictionaryFirst: Bool
    ) -> [KeyboardAutocorrectLogicBlock] {
        let gateID = UUID()
        let sourceKinds: [KeyboardAutocorrectLogicBlockKind] = dictionaryFirst ? [.dictionary, .savedWords] : [.savedWords, .dictionary]
        var blocks = sourceKinds.enumerated().map { index, kind in
            newAutocorrectLogicBlock(kind, rankPriority: index, fallbackTargetID: nil)
        }
        blocks.append(
            KeyboardAutocorrectLogicBlock(
                kind: .weightedRanker,
                rankPriority: 2,
                dictionaryWeight: dictionaryWeight,
                savedWordsWeight: savedWordsWeight
            )
        )
        blocks.append(
            KeyboardAutocorrectLogicBlock(
                id: gateID,
                kind: .confidenceGate,
                rankPriority: 3,
                acceptanceThreshold: threshold
            )
        )
        blocks.append(
            KeyboardAutocorrectLogicBlock(
                kind: .strictFallback,
                rankPriority: 4,
                fallbackEnabled: true,
                fallbackTargetID: gateID
            )
        )
        return blocks
    }

    private func newAutocorrectLogicBlock(
        _ kind: KeyboardAutocorrectLogicBlockKind,
        rankPriority: Int,
        fallbackTargetID: UUID?,
        customTextRuleID: UUID? = nil
    ) -> KeyboardAutocorrectLogicBlock {
        KeyboardAutocorrectLogicBlock(
            kind: kind,
            rankPriority: rankPriority,
            fallbackEnabled: kind.defaultRole == .fallback,
            dictionaryWeight: kind == .weightedRanker ? 0.55 : 0.5,
            savedWordsWeight: kind == .weightedRanker ? 0.45 : 0.5,
            acceptanceThreshold: kind == .confidenceGate ? 0.82 : 0.8,
            fallbackTargetID: kind.defaultRole == .fallback ? fallbackTargetID : nil,
            customTextRuleID: customTextRuleID
        )
    }

    private struct AutocorrectSlotSheet: View {
        @ObservedObject var settings: CompanionSettingsStore
        let laneID: Int
        let slotTitle: String
        let customTextRules: [HWKCustomTextRule]
        @Environment(\.dismiss) private var dismiss

        private static let addableSourceKinds: [KeyboardAutocorrectLogicBlockKind] = [
            .savedWords, .dictionary, .nativeSpellChecker, .coreML
        ]

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("This slot shows")) {
                        purposeRow(.previousWord, title: "The word that comes next")
                        purposeRow(.correction, title: "A fix for what you typed")
                        purposeRow(.completion, title: "The rest of the word")
                    }

                    Section(
                        header: Text("Where suggestions come from"),
                        footer: Text("Top source wins. Drag to reorder, swipe to remove.")
                    ) {
                        ForEach(sourceBlocks) { block in
                            Text(sourceTitle(for: block))
                        }
                        .onMove(perform: moveSources)
                        .onDelete(perform: deleteSources)

                        if !addableKinds.isEmpty || !addableCustomRules.isEmpty {
                            Menu("Add source") {
                                ForEach(addableKinds) { kind in
                                    Button(Self.sourceKindTitle(kind)) {
                                        addSource(kind: kind, customTextRuleID: nil)
                                    }
                                }
                                ForEach(addableCustomRules) { rule in
                                    Button(HWKNaturalLanguageRuleModel.customTextRuleSummary(rule)) {
                                        addSource(kind: .customTextRule, customTextRuleID: rule.id)
                                    }
                                }
                            }
                        }
                    }

                    Section(
                        header: Text("When to fix"),
                        footer: Text("Higher means fewer automatic replacements.")
                    ) {
                        HStack {
                            Text("Only fix when sure")
                            Spacer()
                            Text("\(Int(gateThreshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: gateThresholdBinding, in: 0...1)
                            .accessibilityLabel("Only fix when sure")

                        Toggle("Never replace, only suggest", isOn: suggestOnlyBinding)
                    }
                }
                .navigationBarTitle(slotTitle, displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }

        private var laneIndex: Int? {
            settings.autocorrectLogicLanes.firstIndex { $0.id == laneID }
        }

        private var lane: KeyboardAutocorrectLogicLane? {
            laneIndex.map { settings.autocorrectLogicLanes[$0] }
        }

        private var orderedBlocks: [KeyboardAutocorrectLogicBlock] {
            Self.ordered(lane?.blocks ?? [])
        }

        private var sourceBlocks: [KeyboardAutocorrectLogicBlock] {
            orderedBlocks.filter { $0.role == .source }
        }

        private var addableKinds: [KeyboardAutocorrectLogicBlockKind] {
            Self.addableSourceKinds.filter { kind in
                !sourceBlocks.contains { $0.kind == kind }
            }
        }

        private var addableCustomRules: [HWKCustomTextRule] {
            customTextRules.filter { rule in
                !sourceBlocks.contains { $0.customTextRuleID == rule.id }
            }
        }

        private var gateThreshold: Double {
            orderedBlocks.first { $0.role == .gate }?.acceptanceThreshold ?? 0.82
        }

        private var gateThresholdBinding: Binding<Double> {
            Binding(
                get: { gateThreshold },
                set: { newValue in
                    updateLane { blocks in
                        if let index = blocks.firstIndex(where: { $0.role == .gate }) {
                            blocks[index].acceptanceThreshold = newValue
                        } else {
                            blocks.append(
                                KeyboardAutocorrectLogicBlock(
                                    kind: .confidenceGate,
                                    rankPriority: blocks.count,
                                    acceptanceThreshold: newValue
                                )
                            )
                        }
                    }
                }
            )
        }

        private var suggestOnlyBinding: Binding<Bool> {
            Binding(
                get: { lane?.blocks.contains { $0.kind == .softFallback } ?? false },
                set: { suggestOnly in
                    updateLane { blocks in
                        let gateID = blocks.first { $0.role == .gate }?.id
                        blocks.removeAll { $0.kind == .softFallback || $0.kind == .strictFallback }
                        blocks.append(
                            KeyboardAutocorrectLogicBlock(
                                kind: suggestOnly ? .softFallback : .strictFallback,
                                rankPriority: blocks.count,
                                fallbackEnabled: true,
                                fallbackTargetID: gateID
                            )
                        )
                    }
                }
            )
        }

        private func purposeRow(
            _ family: KeyboardAutocorrectLogicLaneFamily,
            title: String
        ) -> some View {
            Button {
                setPurpose(family)
            } label: {
                HStack {
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    if lane?.effectiveFamily == family {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }
        }

        private func setPurpose(_ family: KeyboardAutocorrectLogicLaneFamily) {
            guard let laneIndex else { return }
            let kind: KeyboardAutocorrectLogicBlockKind
            switch family {
            case .previousWord:
                kind = .previousWordLane
            case .correction:
                kind = .correctionLane
            case .completion:
                kind = .completionLane
            }
            var lanes = settings.autocorrectLogicLanes
            lanes[laneIndex] = lanes[laneIndex].replacingLaneIntent(with: kind)
            settings.autocorrectLogicLanes = lanes
            settings.autocorrectLogicRecipe = .custom
        }

        private func moveSources(from offsets: IndexSet, to destination: Int) {
            var sources = sourceBlocks
            sources.move(fromOffsets: offsets, toOffset: destination)
            rebuildBlocks(sources: sources)
        }

        private func deleteSources(at offsets: IndexSet) {
            var sources = sourceBlocks
            sources.remove(atOffsets: offsets)
            rebuildBlocks(sources: sources)
        }

        private func addSource(kind: KeyboardAutocorrectLogicBlockKind, customTextRuleID: UUID?) {
            var sources = sourceBlocks
            sources.append(
                KeyboardAutocorrectLogicBlock(
                    kind: kind,
                    rankPriority: sources.count,
                    customTextRuleID: customTextRuleID
                )
            )
            rebuildBlocks(sources: sources)
        }

        private func rebuildBlocks(sources: [KeyboardAutocorrectLogicBlock]) {
            updateLane { blocks in
                let ordered = Self.ordered(blocks)
                let laneIntent = ordered.filter { $0.role == .lane }
                let rest = ordered.filter { $0.role != .lane && $0.role != .source }
                blocks = laneIntent + sources + rest
            }
        }

        private func updateLane(_ transform: (inout [KeyboardAutocorrectLogicBlock]) -> Void) {
            guard let laneIndex else { return }
            var lanes = settings.autocorrectLogicLanes
            var blocks = lanes[laneIndex].blocks
            transform(&blocks)
            lanes[laneIndex].blocks = Self.renumbered(blocks)
            settings.autocorrectLogicLanes = lanes
            settings.autocorrectLogicRecipe = .custom
        }

        private func sourceTitle(for block: KeyboardAutocorrectLogicBlock) -> String {
            if block.kind == .customTextRule {
                if let rule = customTextRules.first(where: { $0.id == block.customTextRuleID }) {
                    return HWKNaturalLanguageRuleModel.customTextRuleSummary(rule)
                }
                return "Taught rule"
            }
            return Self.sourceKindTitle(block.kind)
        }

        private static func sourceKindTitle(_ kind: KeyboardAutocorrectLogicBlockKind) -> String {
            switch kind {
            case .savedWords:
                return "Your saved words"
            case .dictionary:
                return "Dictionary"
            case .nativeSpellChecker:
                return "Spell check"
            case .coreML:
                return "Learned patterns"
            default:
                return kind.title
            }
        }

        private static func ordered(_ blocks: [KeyboardAutocorrectLogicBlock]) -> [KeyboardAutocorrectLogicBlock] {
            blocks.sorted { lhs, rhs in
                if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.rankPriority < rhs.rankPriority
            }
        }

        private static func renumbered(_ blocks: [KeyboardAutocorrectLogicBlock]) -> [KeyboardAutocorrectLogicBlock] {
            blocks.enumerated().map { index, block in
                var copy = block
                copy.rankPriority = index
                return copy
            }
        }
    }

    private struct AutocorrectTaughtRuleSheet: View {
        @ObservedObject var settings: CompanionSettingsStore
        let rule: HWKCustomTextRule
        let sourceCode: Binding<String>
        let isInLane: (Int) -> Bool
        let setInLane: (Int, Bool) -> Void
        let onDelete: () -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationView {
                Form {
                    Section(footer: Text(HWKNaturalLanguageRuleModel.customTextRuleDetail(rule))) {
                        Text(HWKNaturalLanguageRuleModel.customTextRuleSummary(rule))
                    }

                    Section(header: Text("Shows in")) {
                        laneToggle(0, title: "Left slot")
                        laneToggle(1, title: "Middle slot")
                        laneToggle(2, title: "Right slot")
                    }

                    if !rule.sourceText.isEmpty {
                        Section(header: Text("You said")) {
                            Text(rule.sourceText)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section(
                        header: Text("Edit as text"),
                        footer: needsRecipe
                            ? Text("This rule is empty, so it can't run yet. Write it here.")
                            : Text("Editing this changes what the rule does.")
                    ) {
                        TextEditor(text: sourceCode)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 120)
                            .accessibilityLabel("Rule recipe")
                    }

                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete rule")
                        }
                    }
                }
                .navigationBarTitle("Taught rule", displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }

        private var needsRecipe: Bool {
            sourceCode.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private func laneToggle(_ laneID: Int, title: String) -> some View {
            Toggle(
                title,
                isOn: Binding(
                    get: { isInLane(laneID) },
                    set: { setInLane(laneID, $0) }
                )
            )
        }
    }

    private var keymapTab: AnyView {
        AnyView(
            ScrollView {
                tabContentStack {
                    keyboardCanvasCard
                    presetCard
                    layoutSizingCard
                }
                .padding(16)
            }
            .background(backgroundColor.ignoresSafeArea())
            .hwcOnChange(of: settings.toolbarKeyCount) {
                clampSelectedSlotIndex()
            }
            .hwcOnChange(of: settings.symbolTopRowKeyCount) {
                clampSelectedSlotIndex()
            }
            .hwcOnChange(of: settings.symbolMiddleRowKeyCount) {
                clampSelectedSlotIndex()
            }
            .hwcOnChange(of: settings.symbolBottomRowKeyCount) {
                clampSelectedSlotIndex()
            }
            .hwcOnChange(of: settings.letterTopRowKeyCount) {
                clampSelectedSlotIndex()
            }
            .hwcOnChange(of: settings.letterMiddleRowKeyCount) {
                clampSelectedSlotIndex()
            }
            .hwcOnChange(of: settings.letterBottomRowKeyCount) {
                clampSelectedSlotIndex()
            }
            .hwcOnChange(of: selectedEditActionMode) { _, newMode in
                let selection = HWKKeymapEditorNavigation.rowAfterChangingActionMode(
                    to: newMode.navigationMode,
                    currentRow: selectedEditableRow,
                    expandedLayer: isKeyboardEditorExpanded ? selectedExpandedLayer.navigationLayer : nil
                )
                let resolvedMode = KeyboardEditActionMode(selection.mode)
                if selectedEditActionMode != resolvedMode {
                    selectedEditActionMode = resolvedMode
                }
                selectedEditableRow = selection.row
                clampSelectedSlotIndex()
                syncKeyShelfSectionSelection()
            }
            .hwcOnChange(of: selectedEditableRow) {
                clampSelectedSlotIndex()
                syncKeyShelfSectionSelection()
            }
            .hwcOnChange(of: abcUnlockStore.isUnlocked) { _, isUnlocked in
                if !isUnlocked {
                    isABCLayerUnlocked = false
                    showsABCUnlockPrompt = false
                }
            }
            .hwcOnChange(of: settings.defaultSymbolLayer) { _, newValue in
                if !isKeyboardEditorExpanded {
                    selectedExpandedLayer = newValue ? .symbols1 : .letters
                }
            }
            .onAppear {
                setKeyboardEditorSurface(settings.defaultSymbolLayer ? .symbols1 : .letters)
                syncKeyShelfSectionSelection()
            }
        )
    }

    private var themesTab: some View {
        ScrollView {
            tabContentStack {
                themeIntroCard
                themeSelectionCard
                customThemeControlsCard
                colorOptionsCard
                appearanceCard
            }
            .padding(16)
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    private var aboutTab: some View {
        ScrollView {
            tabContentStack {
                aboutOverviewCard
                resetCard
                supportDeveloperAccessCard
            }
            .padding(16)
            .padding(.bottom, 96)
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    private var aboutOverviewCard: some View {
        sectionCard(
            title: "Hardware Keyboard: Companion",
            detail: "Build editable on-screen keyboard layers around the way you type."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(tabAccentColor)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 8) {
                        aboutHeroClaim("Desktop rows. iPhone speed.")
                        Text("Built for people who type on iOS like it is their main machine.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(subtleTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    aboutProofPoint(
                        icon: "checkmark.circle.fill",
                        title: "Control without clutter",
                        detail: "Command, modifier, and layout behavior stay close to the keyboard surface."
                    )
                    aboutProofPoint(
                        icon: "checkmark.circle.fill",
                        title: "Make it yours",
                        detail: "Edit the keymap, add layers, and tune every key to match how you type."
                    )
                    aboutProofPoint(
                        icon: "checkmark.circle.fill",
                        title: "Privacy without ceremony",
                        detail: "Typed text is not collected by the companion app."
                    )
                }
            }
        }
    }

    private func aboutHeroClaim(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func aboutProofPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(subtleTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var supportDeveloperAccessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            supportYearlyAccessCard
            supportTipAccessCard
        }
        .hwcOnChange(of: supportDeveloperStore.thankYouPulse) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    private var supportYearlyAccessCard: some View {
        sectionCard(
            title: "Support the Developer",
            detail: "One yearly plan for the full support bundle."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                supportDeveloperMessages

                if supportDeveloperStore.isUnlocked {
                    if supportDeveloperStore.statusMessage == nil {
                        Text("Yearly support active")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tabAccentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    supportSectionLabel("Included")
                    featureBullet("ABC Unlock")
                    featureBullet("Unlimited Layers")
                }

                Divider()
                    .overlay(subtleTextColor.opacity(0.22))

                VStack(alignment: .leading, spacing: 8) {
                    supportSectionLabel("Subscription")
                    supportDeveloperSubscriptionDisclosure
                    supportDeveloperLegalLinks
                }

                if !supportDeveloperStore.isUnlocked {
                    solidButton(
                        supportDeveloperStore.purchaseButtonTitle(
                            for: "dev.moni11811.hwkbcompanion.support_developer_yearly_v4",
                            displayTitle: "Support yearly"
                        ),
                        disabled: supportDeveloperStore.isBusy
                    ) {
                        supportDeveloperStore.purchaseUnlock(productIdentifier: "dev.moni11811.hwkbcompanion.support_developer_yearly_v4")
                    }

                    outlineButton(supportDeveloperStore.isRestoring ? "Restoring..." : "Restore Purchase") {
                        supportDeveloperStore.restorePurchases()
                    }

                    if supportDeveloperStore.errorMessage != nil {
                        outlineButton("Retry App Store Load") {
                            supportDeveloperStore.refreshProduct()
                        }
                    }
                }
            }
        }
    }

    private var supportDeveloperSubscriptionDisclosure: some View {
        Text("Subscription length: 1 year | Price: \(supportDeveloperYearlyPriceText)/year")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(subtleTextColor)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var supportDeveloperLegalLinks: some View {
        HStack(spacing: 14) {
            Link("Privacy Policy", destination: URL(string: "https://hwkc.tech/privacy-policy/")!)
            Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tabAccentColor)
    }

    private func supportSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(subtleTextColor)
            .accessibilityAddTraits(.isHeader)
    }

    private var supportDeveloperYearlyPriceText: String {
        let price = supportDeveloperStore.priceLabel(for: "dev.moni11811.hwkbcompanion.support_developer_yearly_v4")
        return price.isEmpty ? "loading from App Store" : price
    }

    private var supportTipAccessCard: some View {
        sectionCard(
            title: "Buy me a coffee or burger",
            detail: "Available with or without a subscription. Coffee gives an easter egg hint; burger adds 2 layer credits."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                solidButton(
                    supportDeveloperStore.purchaseButtonTitle(
                        for: "dev.moni11811.hwkbcompanion.buycoffee_v3",
                        displayTitle: "Buy me coffee"
                    ),
                    disabled: supportDeveloperStore.isBusy
                ) {
                    supportDeveloperStore.purchaseUnlock(productIdentifier: "dev.moni11811.hwkbcompanion.buycoffee_v3")
                }
                .accessibilityIdentifier("support.tip.coffee")

                solidButton(
                    supportDeveloperStore.purchaseButtonTitle(
                        for: "dev.moni11811.hwkbcompanion.buyburger_v3",
                        displayTitle: "Buy me a burger"
                    ),
                    disabled: supportDeveloperStore.isBusy
                ) {
                    supportDeveloperStore.purchaseUnlock(productIdentifier: "dev.moni11811.hwkbcompanion.buyburger_v3")
                }
                .accessibilityIdentifier("support.tip.burger")

                if supportDeveloperStore.errorMessage != nil {
                    outlineButton("Retry App Store Load") {
                        supportDeveloperStore.refreshProduct()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var supportDeveloperMessages: some View {
        if let message = supportDeveloperStore.statusMessage {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tabAccentColor)
        }

        if let error = supportDeveloperStore.errorMessage {
            Text(error)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.58))
        }
    }


    @ViewBuilder
    private func tabContentStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
    }

    private var shouldShowSetupSplash: Bool {
        !settings.isSetupGateComplete && settings.setupSplashDismissedAt == nil
    }

    private var aboutTabIndex: Int {
        4
    }

    private var keymapTabIndex: Int {
        2
    }

    private var hardwareTabIndex: Int {
        1
    }

    private func handleSetupDeepLinkIfNeeded() {
        guard setupDeepLinkRequestAt > 0 else { return }
        guard setupDeepLinkRequestAt != handledSetupDeepLinkRequestAt else { return }
        handledSetupDeepLinkRequestAt = setupDeepLinkRequestAt

        settings.refreshKeyboardStatus()
        if !shouldShowSetupSplash {
            selectedTab = aboutTabIndex
        }
    }

    private func handleHardwareLabDeepLinkIfNeeded() {
        guard hardwareLabDeepLinkRequestAt > 0 else { return }
        guard hardwareLabDeepLinkRequestAt != handledHardwareLabDeepLinkRequestAt else { return }
        handledHardwareLabDeepLinkRequestAt = hardwareLabDeepLinkRequestAt

        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        selectedTab = hardwareTabIndex
        hardwareLabCaptureFocusRequestAt = hardwareLabDeepLinkRequestAt
        #endif
    }

    private func handleKeymapImportIfNeeded() {
        guard let url = pendingKeymapImportURL else { return }
        pendingKeymapImportURL = nil

        prepareKeymapImport(from: url)
    }

    private func prepareKeymapImport(from url: URL) {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try HWKKeymapTransferFileLoader.load(from: url)
            keymapTransferSheet = .importPreview(
                try HWCKeymapTransferPreview(
                    data: data,
                    sourceFilename: url.lastPathComponent
                )
            )
            selectedTab = keymapTabIndex
        } catch {
            presentKeymapTransferError(error, title: "Import Failed", operation: .importTransfer)
        }
    }

    private func applyKeymapImport(_ data: Data) {
        do {
            let layer = try settings.importKeymapTransferData(data)
            selectedTab = keymapTabIndex
            setKeyboardEditorLayerSelection(
                KeyboardEditorLayerOption.customIDPrefix + layer.id.uuidString
            )
            keymapImportResultTitle = "Layer Imported"
            keymapImportResultMessage = "\(layer.title) was added to Live Keyboard Editor. Existing layers and My Presets were not changed."
        } catch {
            presentKeymapTransferError(error, title: "Import Failed", operation: .importTransfer)
            return
        }
        showsKeymapImportResult = true
    }

    private var canImportKeymapLayer: Bool {
        !isAdditionalLayersLocked
    }

    private var pendingKeymapImportAccessMessage: String {
        canImportKeymapLayer
            ? "This adds a new Live Keyboard Editor layer without changing existing layers or My Presets."
            : "Additional Layer access is required before importing another live layer."
    }

    private func prepareSelectedLayerExport() {
        do {
            let data: Data
            if let selectedCustomLayerID {
                data = try settings.exportKeymapTransferData(forCustomLayerID: selectedCustomLayerID)
            } else {
                data = try settings.exportKeymapTransferData(
                    surface: keyboardEditorSurface.rowSurface,
                    title: keyboardEditorLayerTitle
                )
            }
            keymapTransferSheet = .exportPreview(
                try HWCKeymapTransferPreview(data: data)
            )
        } catch {
            presentKeymapTransferError(error, title: "Export Failed", operation: .exportTransfer)
        }
    }

    private func beginKeymapExport(_ preview: HWCKeymapTransferPreview) {
        do {
            keymapExportFileDocument = try HWCKeymapTransferFileDocument(data: preview.data)
            keymapExportFilename = preview.suggestedFilename
            DispatchQueue.main.async {
                showsKeymapFileExporter = true
            }
        } catch {
            presentKeymapTransferError(error, title: "Export Failed", operation: .exportTransfer)
        }
    }

    private func handleKeymapExportResult(_ result: Result<URL, Error>) {
        defer { keymapExportFileDocument = nil }
        switch result {
        case .success(let url):
            keymapImportResultTitle = "Layer Exported"
            keymapImportResultMessage = "Saved \(url.lastPathComponent)."
            showsKeymapImportResult = true
        case .failure(let error):
            presentKeymapTransferError(error, title: "Export Failed", operation: .exportTransfer)
        }
    }

    private func presentKeymapTransferError(
        _ error: Error,
        title: String,
        operation: HWCKeymapTransferErrorPresentation.Operation
    ) {
        guard let message = HWCKeymapTransferErrorPresentation.message(
            for: error,
            operation: operation
        ) else { return }
        keymapImportResultTitle = title
        keymapImportResultMessage = message
        showsKeymapImportResult = true
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func openAssistiveTouchSettings() {
        assistiveTouchSettingsStatusMessage = nil
        if #available(iOS 26.0, *) {
            Task { @MainActor in
                do {
                    try await AccessibilitySettings.openSettings(for: .assistiveTouch)
                } catch {
                    openAssistiveTouchSettingsFallback()
                }
            }
        } else {
            openAssistiveTouchSettingsFallback()
        }
    }

    @MainActor
    private func openAssistiveTouchSettingsFallback() {
        assistiveTouchSettingsStatusMessage = "If Settings did not open AssistiveTouch, use Settings > Accessibility > Touch > AssistiveTouch."
        openAppSettings()
    }

    @ViewBuilder
    private var assistiveTouchSettingsStatusText: some View {
        if let assistiveTouchSettingsStatusMessage {
            Text(assistiveTouchSettingsStatusMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tabAccentColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var firstTimeSetupSplash: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    firstTimeSetupWelcomeHeader

                    HStack(alignment: .top, spacing: 14) {
                        Text("Finish Setup")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)

                        Spacer(minLength: 12)

                        compactOutlineButton("Skip Setup", systemImage: "xmark") {
                            settings.dismissSetupSplash()
                        }
                    }

                    Text("Complete keyboard setup below. HWC unlocks after Full Access is confirmed.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(subtleTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Keyboard Setup")
                        HStack(spacing: 10) {
                            Text("On-screen keyboard setup")
                                .font(.headline)
                                .foregroundColor(previewTextColor)
                        }
                    }

                    if !supportDeveloperStore.isUnlocked {
                        setupSubscriptionUpsell
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        setupFlowStepCard(
                            number: "1",
                            systemImage: "keyboard",
                            title: "Open HWC Settings",
                            detail: "Turn on Keyboard + Full Access.",
                            status: settings.isSetupFullAccessComplete ? "Full Access passed" : "Waiting for keyboard activation"
                        ) {
                            solidButton("Open Settings") {
                                openAppSettings()
                            }
                            setupKeyboardActivationField
                        }

                    }
                    .animation(setupHardwareStepsAnimation, value: settings.setupSelectedMode)

                    VStack(spacing: 10) {
                        solidButton("Unlock HWC") {
                            finishSetupGateIfReady()
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: 520, alignment: .leading)
                .background(cardBackground)
                .overlay(cardBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            refreshSetupGateStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.assistiveTouchStatusDidChangeNotification)) { _ in
            refreshSetupGateStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshSetupGateStatus()
        }
        .transition(.opacity)
    }

    private var firstTimeSetupWelcomeHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(tabAccentColor)
                .frame(width: 52, height: 52)
                .background(tabAccentColor.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your keyboard. Your way.")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Welcome to Hardware Keyboard: Companion. Complete setup below.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(subtleTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hardwareOnlySetupSteps: some View {
        Group {
            setupFlowStepCard(
                number: "2",
                systemImage: "accessibility",
                title: "Open AssistiveTouch",
                detail: "Turn on + On-Screen Keyboard.",
                status: settings.isSetupAssistiveTouchComplete ? "AssistiveTouch detected" : "Complete in Settings"
            ) {
                outlineButton("Open in Settings") {
                    openAssistiveTouchSettings()
                }
                assistiveTouchSettingsStatusText
            }

            setupFlowStepCard(
                number: "3",
                systemImage: "restart.circle",
                title: "Then restart iPhone",
                detail: "Restart after Full Access has passed.",
                status: settings.isSetupRestartComplete ? "Restart detected" : "Restart pending"
            ) {
                Text(
                    settings.isSetupRestartComplete
                        ? "HWC saw the new boot session."
                        : "After restarting, reopen HWC and tap Unlock HWC once this step passes."
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(subtleTextColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var setupHardwareStepsTransition: AnyTransition {
        guard !accessibilityReduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .move(edge: .top))
        )
    }

    private var setupHardwareStepsAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.15)
    }

    private var setupSubscriptionUpsell: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .foregroundColor(tabAccentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock more with yearly support")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("ABC Unlock + Unlimited Layers")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(subtleTextColor)
                }
            }

            supportDeveloperSubscriptionDisclosure
            supportDeveloperLegalLinks

            solidButton(
                supportDeveloperStore.purchaseButtonTitle(
                    for: "dev.moni11811.hwkbcompanion.support_developer_yearly_v4",
                    displayTitle: "Support yearly"
                ),
                disabled: supportDeveloperStore.isBusy
            ) {
                supportDeveloperStore.purchaseUnlock(productIdentifier: "dev.moni11811.hwkbcompanion.support_developer_yearly_v4")
            }
        }
        .padding(12)
        .background(secondaryCardFill.opacity(0.72))
        .overlay(cardBorder)
    }

    @ViewBuilder
    private var setupKeyboardActivationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tap here, then pick HWC Keyboard", text: $settings.setupKeyboardActivationText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(buttonBackgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(previewTileBorder, lineWidth: 1)
                )
                .hwcOnChange(of: settings.setupKeyboardActivationText) {
                    refreshSetupGateStatus()
                }
            Text("Open HWC Keyboard here once. Full Access is detected immediately; no typing is required.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(subtleTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setupFlowStepCard<Content: View>(
        number: String,
        systemImage: String,
        title: String,
        detail: String,
        status: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tabAccentColor.opacity(0.18))
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(tabAccentColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(number). \(title)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(subtleTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                    setupStatusLine(status)
                }
            }

            content()
        }
        .padding(14)
        .frame(minHeight: setupFlowStepMinimumHeight, alignment: .topLeading)
        .background(secondaryCardFill.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(previewTileBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func setupStatusLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tabAccentColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func refreshSetupGateStatus() {
        settings.refreshKeyboardStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            settings.refreshKeyboardStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            settings.refreshKeyboardStatus()
        }
    }

    @ViewBuilder
    private var setupFullAccessStatusText: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Full Access")
            Text(
                settings.isSetupFullAccessComplete
                    ? "Full Access passed. HWC Keyboard checked in."
                    : "Full Access pending. Enable Allow Full Access, then open HWC Keyboard once."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(subtleTextColor)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var setupAssistiveTouchStatusText: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("AssistiveTouch")
            Text(
                settings.isSetupAssistiveTouchComplete
                    ? "AssistiveTouch detected."
                    : "Turn on AssistiveTouch and On-Screen Keyboard. If iOS does not report it here, continue after completing that Settings step."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(subtleTextColor)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var setupRestartStatusText: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Restart iPhone")
            Text(
                settings.isSetupRestartComplete
                    ? "Restart detected."
                    : "Restart after Full Access has passed. HWC detects the reboot automatically."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(subtleTextColor)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setupModeButton(_ mode: SettingsMode) -> some View {
        let title = "\(mode.title) Mode"

        return Button {
            settings.setupSelectedMode = mode.rawValue
            applySettingsMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(secondaryCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(settings.setupSelectedMode == mode.rawValue ? tabAccentColor : previewTileBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private func finishSetupGateIfReady() {
        refreshSetupGateStatus()
        settings.completeSetupGateIfReady()
        refreshSetupGateStatus()
    }

    private var themeIntroCard: some View {
        sectionCard(title: "Theme & Accent") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                }
            }
        }
    }

    private var themeSelectionCard: some View {
        sectionCard(title: "Theme Selection", detail: "Choose the base look for the companion and live previews.") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(CompanionAppTheme.allCases) { theme in
                        themeButton(for: theme)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var customThemeControlsCard: some View {
        if settings.appTheme == .custom {
            sectionCard(title: "Custom Keys", detail: "Shape the key surface directly.") {
                VStack(alignment: .leading, spacing: 14) {
                    customThemePreview

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Key Fill")
                        Picker("Key Fill", selection: customKeyFillBinding) {
                            ForEach(KeyboardCustomKeyFill.allCases) { fill in
                                Text(fill.title).tag(fill)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }

                    toggleRow(
                        title: "Follow App",
                        detail: "Let Adaptive fill follow the app's light or dark appearance.",
                        isOn: customKeyStyleBoolBinding(\.followsHostAppearance),
                        disabled: settings.customKeyStyle.keyFill != .adaptive
                    )

                    numericSliderRow(
                        title: "Text",
                        detail: "Set legend brightness on custom keys.",
                        value: customKeyStyleIntBinding(\.textBrightness),
                        range: 45...100,
                        step: 1,
                        suffix: "%"
                    )

                    numericSliderRow(
                        title: "Border",
                        detail: "Set the key outline strength.",
                        value: customKeyStyleIntBinding(\.borderStrength),
                        range: 0...100,
                        step: 1,
                        suffix: "%"
                    )

                    numericSliderRow(
                        title: "Roundness",
                        detail: "Set corner radius from flat to soft.",
                        value: customKeyStyleIntBinding(\.cornerRadius),
                        range: 0...14,
                        step: 1,
                        suffix: "pt"
                    )

                    numericSliderRow(
                        title: "Depth",
                        detail: "Set key shadow depth.",
                        value: customKeyStyleIntBinding(\.shadowDepth),
                        range: 0...8,
                        step: 1,
                        suffix: "pt"
                    )

                    numericSliderRow(
                        title: "Key Distance",
                        detail: "Set spacing between keys.",
                        value: customKeyStyleIntBinding(\.keyDistance),
                        range: 0...10,
                        step: 1,
                        suffix: "pt"
                    )
                }
            }
        }
    }

    private var colorOptionsCard: some View {
        sectionCard(title: "Accent Mixer", detail: "Pick up to 3 base colors. First leads. Second deepens. Third adds glow.") {
            VStack(alignment: .leading, spacing: 14) {
                accentMixerPreview

                sectionLabel("Base Colors")

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(KeyboardAccentTone.allCases) { tone in
                        accentToneButton(for: tone)
                    }
                }

                Text("Tap selected extra colors again to remove them. When all 3 slots are full, a new pick swaps the glow slot.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(subtleTextColor)
            }
        }
    }

    private var presetCard: some View {
        sectionCard(title: "Preset Library", detail: "Edit or clone presets. Edited copies appear alongside imported presets; built-in originals remain available.") {
            VStack(alignment: .leading, spacing: 14) {
                keymapTemplateLibrary

                Divider().overlay(Color.white.opacity(0.08))

                HStack {
                    sectionLabel("My Presets")
                    Spacer()
                    outlineButton("Save Current", role: .primary) {
                        savedPresetName = "Preset \(settings.savedKeymapPresets.count + 1)"
                        showsCreateSavedPresetPrompt = true
                    }
                }

                if settings.savedKeymapPresets.isEmpty {
                    Text("No saved presets yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(subtleTextColor)
                } else {
                    ForEach(settings.savedKeymapPresets) { preset in
                        Menu {
                            Button("Edit") {
                                editManagedTemplate(preset.id)
                            }
                            Button("Clone") {
                                cloneManagedTemplate(preset.id)
                            }
                            Button("Apply") {
                                applySavedPresetToSelectedLayer(preset.id)
                            }
                            Button("Update") {
                                do {
                                    try settings.saveEditedPreset(
                                        id: preset.id,
                                        from: selectedPresetTargetSurface,
                                        customLayerID: selectedCustomLayerID
                                    )
                                    templateLibraryError = nil
                                } catch {
                                    presentTemplateError("Template changes could not be saved. Your previous saved version is still available.")
                                }
                            }
                            Button("Rename") {
                                savedPresetName = preset.title
                                pendingSavedPresetRenameID = preset.id
                            }
                            Button("Delete", role: .destructive) {
                                settings.deleteSavedPreset(id: preset.id)
                            }
                        } label: {
                            presetLibraryRow(title: preset.title)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("keymap.preset.\(preset.id.uuidString)")
                        .accessibilityLabel(preset.title)
                        .accessibilityHint("Edit, clone, apply, update, rename, or delete this preset")
                    }
                }

                Divider().overlay(Color.white.opacity(0.12))

                keymapTransferActions
            }
        }
    }

    private var feedbackCard: some View {
        sectionCard(title: "Feedback", detail: "Haptic options for key presses.") {
            VStack(spacing: 14) {
                toggleRow(
                    title: "Vibration",
                    detail: "Requires Allow Full Access for the keyboard.",
                    isOn: $settings.vibrationEnabled
                )

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Vibration Strength")
                    Picker("Vibration Strength", selection: $settings.feedbackLevel) {
                        ForEach(KeyboardFeedbackLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(!settings.vibrationEnabled)
                }

                solidButton("Test Vibration", disabled: !settings.vibrationEnabled) {
                    settings.previewFeedback()
                }
            }
        }
    }

    private var textImprovementBinding: Binding<Bool> {
        Binding(
            get: {
                settings.autocorrectEnabled &&
                    settings.clickToFixEnabled &&
                    settings.autocompleteEnabled
            },
            set: { isEnabled in
                settings.autocorrectEnabled = isEnabled
                settings.clickToFixEnabled = isEnabled
                settings.autocompleteEnabled = isEnabled
                if !isEnabled && selectedTab == 1 {
                    selectedTab = 0
                }
            }
        )
    }

    private var wordSuggestionsCard: some View {
        sectionCard(title: "Text Behaviour", detail: "Control correction, completion, punctuation, and sentence caps.") {
            VStack(spacing: 14) {
                toggleRow(
                    title: "Autocorrect",
                    detail: "Turn autocorrect, click-to-fix, and autocomplete on or off together.",
                    isOn: textImprovementBinding
                )
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Swipe Up on Keyboard")
                    Picker("Swipe Up on Keyboard", selection: $settings.suggestionSwipeUpAction) {
                        ForEach(KeyboardSuggestionSwipeUpAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Swipe Down on Keyboard")
                    Picker("Swipe Down on Keyboard", selection: $settings.suggestionSwipeDownAction) {
                        ForEach(KeyboardSuggestionSwipeDownAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                edgeSwipeSettings(rowMode: false)
                edgeSwipeSettings(rowMode: true)
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Two-Finger Swipe Out")
                    Picker("Two-Finger Swipe Out", selection: $settings.semiFoldEnabled) {
                        Text("Off").tag(false)
                        Text("On").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .accessibilityIdentifier("keyboard.semiFold")
                    Text("Swipe two fingers apart to split the keyboard. Swipe them together to join it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                toggleRow(
                    title: "Swipe Left: Delete",
                    detail: "Swipe left across the keyboard to delete one character.",
                    isOn: $settings.suggestionSwipeLeftDeleteEnabled
                )
                toggleRow(
                    title: "Swipe Right: Space",
                    detail: "Swipe right across the keyboard to insert a space.",
                    isOn: $settings.suggestionSwipeRightSpaceEnabled
                )
                toggleRow(
                    title: "Double Space Period",
                    detail: "Turn a second space after a word into period-space. Off by default.",
                    isOn: $settings.doubleSpacePeriodEnabled
                )
                toggleRow(
                    title: "Capitalize First Letter",
                    detail: "Prime Caps automatically at the start of a new sentence, while still letting the Caps key override it.",
                    isOn: $settings.capitalizeFirstLetterEnabled
                )
                toggleRow(
                    title: "Clipboard Suggestions",
                    detail: "Use your encrypted clipboard snippets as language-aware completion ideas while editing.",
                    isOn: Binding(
                        get: { !settings.clipboardDisabled },
                        set: { settings.clipboardDisabled = !$0 }
                    )
                )
                actionRow(
                    title: "Clipboard Snippets",
                    detail: "Review secure snippet storage state and manage saved suggestions.",
                    actionTitle: "Manage"
                ) {
                    showsClipboardSettings = true
                }
            }
        }
    }

    private func edgeSwipeSettings(rowMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(rowMode ? "Row Mode Edge Swipes" : "Full Keyboard Edge Swipes")
            Text(rowMode
                 ? "Swipe inward from an edge. Layer choices are limited to custom row layers."
                 : "Swipe inward from an edge to open Clipboard or slide to a layer.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(KeyboardSwipeEdge.allCases) { edge in
                let destinations = edgeSwipeChoices(edge, rowMode: rowMode)
                let layers = destinations.filter(\.isLayer)
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel(edge.title)
                    Picker(edge.title, selection: edgeSwipeActionBinding(edge, rowMode: rowMode)) {
                        Text("Off").tag(EdgeSwipeAction.off)
                        if destinations.contains(.clipboard) {
                            Text("Clipboard").tag(EdgeSwipeAction.clipboard)
                        }
                        if !layers.isEmpty {
                            Text("Layer").tag(EdgeSwipeAction.layer)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(destinations.count == 1)
                    .accessibilityIdentifier("keyboard.edgeSwipe.\(rowMode ? "row" : "expanded").\(edge.rawValue)")

                    if edgeSwipeBinding(edge, rowMode: rowMode).wrappedValue.isLayer {
                        Picker("Layer", selection: edgeSwipeBinding(edge, rowMode: rowMode)) {
                            ForEach(layers) { destination in
                                Text(destination.title(in: settings.keymap)).tag(destination)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("keyboard.edgeSwipe.\(rowMode ? "row" : "expanded").\(edge.rawValue).layer")
                    }
                }
            }
            if rowMode && !accessibleCustomKeymapLayers.contains(where: { $0.style == .row }) {
                Text("Add a custom row layer in Keymap to use Layer here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private enum EdgeSwipeAction: Hashable {
        case off, clipboard, layer
    }

    private func edgeSwipeActionBinding(_ edge: KeyboardSwipeEdge, rowMode: Bool) -> Binding<EdgeSwipeAction> {
        let destination = edgeSwipeBinding(edge, rowMode: rowMode)
        return Binding(
            get: {
                if destination.wrappedValue == .clipboard { return .clipboard }
                return destination.wrappedValue.isLayer ? .layer : .off
            },
            set: { action in
                switch action {
                case .off: destination.wrappedValue = .off
                case .clipboard: destination.wrappedValue = .clipboard
                case .layer:
                    if !destination.wrappedValue.isLayer,
                       let layer = edgeSwipeChoices(edge, rowMode: rowMode).first(where: \.isLayer) {
                        destination.wrappedValue = layer
                    }
                }
            }
        )
    }

    private func edgeSwipeBinding(_ edge: KeyboardSwipeEdge, rowMode: Bool) -> Binding<KeyboardEdgeSwipeDestination> {
        Binding(
            get: { settings.edgeSwipeConfiguration.normalized(for: settings.keymap)[edge, rowMode] },
            set: { destination in
                var configuration = settings.edgeSwipeConfiguration.normalized(for: settings.keymap)
                configuration[edge, rowMode] = destination
                settings.edgeSwipeConfiguration = configuration.normalized(for: settings.keymap)
            }
        )
    }

    private func edgeSwipeChoices(_ edge: KeyboardSwipeEdge, rowMode: Bool) -> [KeyboardEdgeSwipeDestination] {
        let configuration = settings.edgeSwipeConfiguration.normalized(for: settings.keymap)
        let other = configuration[edge == .left ? .right : .left, rowMode]
        let builtIns: [KeyboardEdgeSwipeDestination] = rowMode ? [] : KeyboardEdgeSwipeDestination.builtInLayers
        let custom = accessibleCustomKeymapLayers
            .filter { !rowMode || $0.style == .row }
            .map { KeyboardEdgeSwipeDestination.custom($0.id) }
        var seen = Set<KeyboardEdgeSwipeDestination>()
        return ([.off, .clipboard] + builtIns + custom).filter {
            seen.insert($0).inserted && ($0 == .off || $0 != other)
        }
    }

    private var behaviorCard: some View {
        sectionCard(title: "Keyboard Behavior", detail: "How HWC opens and which layer appears first.") {
            VStack(spacing: 14) {
                toggleRow(
                    title: "Start Expanded",
                    detail: "Open with the extra symbol layer already visible.",
                    isOn: $settings.startExpanded
                )
                toggleRow(
                    title: "Default To Symbols",
                    detail: "Use symbols as the primary expanded layer instead of letters.",
                    isOn: $settings.defaultSymbolLayer
                )
                toggleRow(
                    title: "Hide Keyboard",
                    detail: "Suggestion bar stays visible; key body hides.",
                    isOn: hideKeyboardAgreementBinding
                )
            }
        }
    }

    private var holdActionsCard: some View {
        sectionCard(title: "Hold Behaviour", detail: "Timing for keys, Rolodex selection, Caps, More, and Delete holds.") {
            VStack(spacing: 14) {
                numericSliderRow(
                    title: "Key Hold Time",
                    detail: "How long keys must be held before their hold action fires, including opening Rolodex.",
                    value: $settings.keyHoldDurationMs,
                    range: KeyboardLayoutBounds.holdActivationDurationRangeMs,
                    step: 25,
                    suffix: "ms"
                )

                numericSliderRow(
                    title: "Rolodex Select Hold Time",
                    detail: "How long to hold the active Rolodex word before selecting it.",
                    value: $settings.rolodexSelectHoldDurationMs,
                    range: KeyboardLayoutBounds.rolodexSelectHoldDurationRangeMs,
                    step: 10,
                    suffix: "ms"
                )

                toggleRow(
                    title: "Hold Caps For Lock",
                    detail: "Tap Caps for a one-key sticky shift. Hold it to latch full Caps Lock.",
                    isOn: $settings.capsHoldToLockEnabled
                )

                numericSliderRow(
                    title: "Caps Hold Time",
                    detail: "How long Caps must be held before it switches from one-key shift to full lock.",
                    value: $settings.capsHoldDurationMs,
                    range: KeyboardLayoutBounds.holdActivationDurationRangeMs,
                    step: 25,
                    suffix: "ms"
                )
                .disabled(!settings.capsHoldToLockEnabled)
                .opacity(settings.capsHoldToLockEnabled ? 1 : 0.55)

                toggleRow(
                    title: "Hold Menu To Latch",
                    detail: "Tap More for a one-key expanded layer. Hold it to keep the expanded layer open for multiple keys.",
                    isOn: $settings.menuHoldToLatchEnabled
                )

                numericSliderRow(
                    title: "Menu Hold Time",
                    detail: "How long More must be held before the expanded layer stays latched open.",
                    value: $settings.menuHoldDurationMs,
                    range: KeyboardLayoutBounds.holdActivationDurationRangeMs,
                    step: 25,
                    suffix: "ms"
                )
                .disabled(!settings.menuHoldToLatchEnabled)
                .opacity(settings.menuHoldToLatchEnabled ? 1 : 0.55)

                numericSliderRow(
                    title: "Menu Tap Lock Window",
                    detail: "After the first expanded key from a Menu tap, the expanded layer waits this long for a second expanded key before closing. If that second key arrives in time, Menu latches open. Set it to 0 ms for no timeout.",
                    value: $settings.menuTapLockWindowMs,
                    range: KeyboardLayoutBounds.menuTapLockWindowRangeMs,
                    step: 25,
                    suffix: "ms"
                )

                toggleRow(
                    title: "Hold Delete To Accelerate",
                    detail: "Hold Delete to remove the current word character by character, then step backward in words, and finally in full sentences.",
                    isOn: $settings.deleteHoldEnabled
                )

                numericSliderRow(
                    title: "Words Before Sentences",
                    detail: "After the first word is cleared one character at a time, Delete switches to sentence-sized removals after this many full-word steps.",
                    value: $settings.deleteHoldWordsBeforeSentence,
                    range: KeyboardLayoutBounds.deleteHoldWordCountRange,
                    step: 1,
                    suffix: "words"
                )
                .disabled(!settings.deleteHoldEnabled)
                .opacity(settings.deleteHoldEnabled ? 1 : 0.55)
            }
        }
    }

    #if HWC_INTERNAL_BUILD
    private var hardwareCalibrationTimedControlCard: some View {
        EmptyView()
    }

    private var hardwareCalibrationGuideCard: some View {
        EmptyView()
    }

    private func hardwareCalibrationEventStrip(_ labels: [String]) -> some View {
        EmptyView()
    }

    private var hardwareKeyboardCalibrationCard: some View {
        sectionCard(
            title: "Hardware Keyboard Calibration",
            detail: "Mac-like quick setup. Press a few buttons in the app, repeat them with HWC Keyboard selected, and HWC chooses the safest profile."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if let recommendedHardwareCalibrationProfile {
                    }
                    if let appliedHardwareCalibrationProfile {
                    }
                }

                hardwareCalibrationTimedControlCard

                sectionLabel("Timed Setup")
                hardwareCalibrationGuideCard

                sectionLabel("1. App Check")
                keyboardCanvasSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        canvasRowHeader(
                            title: "App Check Pad",
                            detail: "Tap Start App Check, then press the short sample from the step card above. This shows which buttons the companion can see."
                        )

                        hardwareCalibrationCapturePad
                        hardwareCalibrationSummaryGrid(rawHardwareCalibrationSummary)

                        if !rawHardwareCalibrationSummary.recentEventLabels.isEmpty {
                            hardwareCalibrationEventStrip(rawHardwareCalibrationSummary.recentEventLabels)
                        }

                        HStack(spacing: 10) {
                            outlineButton(isRawHardwareCalibrationActive ? "Stop App Check" : "Start App Check") {
                                isRawHardwareCalibrationActive
                                    ? stopRawHardwareCalibration()
                                    : startRawHardwareCalibration()
                            }

                            outlineButton(
                                "Clear App",
                                disabled: rawHardwareCalibrationEvents.isEmpty
                            ) {
                                clearRawHardwareCalibration()
                            }
                        }
                    }
                }

                sectionLabel("2. Keyboard Check")
                keyboardCanvasSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        canvasRowHeader(
                            title: "HWC Keyboard Check",
                            detail: "Tap Start Keyboard Check, tap the field, keep HWC Keyboard selected, then press the same short sample again."
                        )

                        hardwareCalibrationSummaryGrid(liveHardwareCalibrationSummary)

                        if !liveHardwareCalibrationSummary.recentEventLabels.isEmpty {
                            hardwareCalibrationEventStrip(liveHardwareCalibrationSummary.recentEventLabels)
                        }

                        HStack(spacing: 10) {
                            outlineButton(
                                "Start Keyboard Check",
                                disabled: isHardwarePremiumLocked
                            ) {
                                startLiveHardwareCalibration()
                            }

                            outlineButton(
                                "Clear Keyboard",
                                disabled: liveHardwareCalibrationSummary.eventCount == 0
                            ) {
                                clearLiveHardwareCalibration()
                            }
                        }

                        hardwareKeyboardTestField
                    }
                }

                if let calibrationHeadline = hardwareCalibrationHeadline {
                    sectionLabel("3. Recommendation")

                    VStack(alignment: .leading, spacing: 12) {
                        Text(calibrationHeadline)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        if let calibrationDetail = hardwareCalibrationDetail {
                            Text(calibrationDetail)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(subtleTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !hardwareCalibrationFindings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(hardwareCalibrationFindings, id: \.self) { finding in
                                    hardwareCalibrationFindingRow(finding)
                                }
                            }
                        }

                        if let recommendedHardwareCalibrationProfile {
                            let settings = hardwareCalibrationSettings(for: recommendedHardwareCalibrationProfile)

                            HStack(spacing: 10) {
                            }

                            solidButton(
                                "Use \(recommendedHardwareCalibrationProfile.title) Again",
                                disabled: isHardwarePremiumLocked
                            ) {
                                applyHardwareCalibration(recommendedHardwareCalibrationProfile)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Profile Choices")

                            ForEach(HardwareCalibrationProfile.allCases) { profile in
                                compactOutlineButton(
                                    "Use \(profile.title)",
                                    systemImage: profile == recommendedHardwareCalibrationProfile
                                        ? "checkmark.circle.fill"
                                        : "slider.horizontal.3",
                                    disabled: isHardwarePremiumLocked
                                ) {
                                    applyHardwareCalibration(profile)
                                }
                            }
                        }

                        if let hardwareCalibrationAppliedMessage {
                            Text(hardwareCalibrationAppliedMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(tabAccentColor)
                        }
                    }
                }
            }
        }
    }
    #endif

    private var hardwareKeyboardSetupInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Setup & Troubleshooting")
            featureBullet("Restart your device if Shift or Caps Lock stops reading; iOS often restores modifier events after a reboot.")
            featureBullet("After reinstall, confirm Allow Full Access is enabled for HWC Keyboard.")
            featureBullet("Go to Accessibility > Enable AssistiveTouch > Disable/re-enable Show Onscreen Keyboard.")
            featureBullet("Leave iOS Hardware Keyboard settings at their default or off state.")
        }
    }

    private var hardwarePremiumLockedPurchaseWarning: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Connection Warning")
            featureBullet("Hardware Keyboard Reading stays off until Premium is unlocked.")

            if let message = hardwarePremiumStore.statusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(tabAccentColor)
            }

            if let error = hardwarePremiumStore.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.58))
            }

            HStack(spacing: 10) {
                outlineButton(hardwarePremiumStore.isRestoring ? "Restoring..." : "Restore Purchase") {
                    hardwarePremiumStore.restorePurchases()
                }

                solidButton(
                    hardwarePremiumStore.purchaseButtonTitle,
                    disabled: hardwarePremiumStore.isBusy
                ) {
                    hardwarePremiumStore.purchaseUnlock()
                }
            }
        }
    }

    private var hardwarePremiumAccessCard: some View {
        sectionCard(
            title: HWCBuildFlavor.hardwareKeypressPaidFeatureTitle,
            detail: HWCBuildFlavor.hardwareKeypressPaidFeatureDetail
        ) {
            VStack(alignment: .leading, spacing: 14) {
                featureBullet("Enables Hardware Keyboard Reading.")
                featureBullet("Included with yearly support.")

                if let message = hardwarePremiumStore.statusMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(tabAccentColor)
                }

                if let error = hardwarePremiumStore.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.58))
                }

                if isHardwarePremiumLocked {
                    HStack(spacing: 10) {
                        outlineButton(hardwarePremiumStore.isRestoring ? "Restoring..." : "Restore Purchase") {
                            hardwarePremiumStore.restorePurchases()
                        }

                        solidButton(
                            hardwarePremiumStore.purchaseButtonTitle,
                            disabled: hardwarePremiumStore.isBusy
                        ) {
                            hardwarePremiumStore.purchaseUnlock()
                        }
                    }
                }

            }
        }
    }

    private var additionalLayersAccessCard: some View {
        sectionCard(
            title: "Additional Layers",
            detail: "Unlock extra Live Keymap editor layers."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if supportDeveloperStore.isUnlocked {
                    featureBullet("Unlimited Layers included.")
                } else {
                    featureBullet("Purchased layers: \(additionalLayersStore.purchasedLayerCount)")
                }

                if let message = additionalLayersStore.statusMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(tabAccentColor)
                }

                if let error = additionalLayersStore.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.58))
                }

                if !supportDeveloperStore.isUnlocked {
                    HStack(spacing: 10) {
                        outlineButton(additionalLayersStore.isRestoring ? "Restoring..." : "Restore Layer Purchases") {
                            additionalLayersStore.restorePurchases()
                        }

                        solidButton(
                            additionalLayersStore.purchaseButtonTitle,
                            disabled: additionalLayersStore.isBusy
                        ) {
                            additionalLayersStore.purchaseUnlock()
                        }
                    }
                }
            }
        }
    }

    private var appearanceCard: some View {
        sectionCard(title: "Appearance", detail: "Visual tweaks for contrast and labels.") {
            VStack(spacing: 14) {
                toggleRow(
                    title: "High Contrast Keys",
                    detail: "Increase text and border contrast for the block-style keyboard.",
                    isOn: $settings.highContrastKeys
                )
                toggleRow(
                    title: "Large Legends",
                    detail: "Increase symbol and toolbar label size for faster scanning.",
                    isOn: $settings.largeLegends
                )
                toggleRow(
                    title: "Show Labels",
                    detail: "Add text captions on control keys like Shift, Return, Delete, and Space.",
                    isOn: $settings.showControlLabels
                )
            }
        }
    }

    private var layoutSizingCard: some View {
        sectionCard(title: "Layout & Sizing", detail: "Adjust row heights.") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 14) {
                    topRowHeightControl(
                        detail: "Adjust the visible height of the one-line strip."
                    )
                    numericSliderRow(
                        title: "Expanded Key Height",
                        detail: "Adjust the main symbol and ABC rows after tapping More.",
                        value: $settings.expandedKeyHeight,
                        range: KeyboardLayoutBounds.expandedKeyHeightRange,
                        step: 2,
                        suffix: "pt"
                    )
                    numericSliderRow(
                        title: "Suggestion Row Height",
                        detail: "Resize the autocorrect bar without changing its logic or gestures.",
                        value: $settings.suggestionRowHeight,
                        range: KeyboardLayoutBounds.suggestionRowHeightRange,
                        step: 2,
                        suffix: "pt"
                    )
                }

                if isABCSettingsLocked {
                    abcEditingGatePanel(
                        title: "Expanded ABC Is Locked",
                        detail: "ABC row counts stay tied to the default touch map until you unlock ABC customization. Symbol hold legends on ABC keys stay covered too."
                    )
                }
            }
        }
    }

    private var resetCard: some View {
        sectionCard(title: "Reset & Recovery") {
            VStack(spacing: 10) {
                solidButton("Reset Everything", role: .destructive) {
                    settings.resetToDefaults()
                }
                outlineButton("Reset Editable Keymap", role: .destructive) {
                    settings.resetKeymapToDefaults()
                }
                outlineButton("Restore Default ABC Letters") {
                    settings.restoreABCDefaults()
                }
            }
        }
    }

    private var keymapSummaryCard: some View {
        sectionCard(title: "Editable Keymap", detail: "Edit the main shortcut strip and expanded layout. Delete and More stay fixed.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Language Layout")
                    Picker("Language Layout", selection: layoutLocaleBinding) {
                        ForEach(KeyboardLayoutLocale.allCases) { locale in
                            Text(locale.title).tag(locale)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                outlineButton("Restore Keymap Defaults") {
                    settings.resetKeymapToDefaults()
                }
            }
        }
    }

    private var keymapEditingInstructionsCard: some View {
        sectionCard(title: "Keymap Editing", detail: "Tap any key to select it. Choose a selector category, assign a token, or type a custom value.") {
            VStack(alignment: .leading, spacing: 10) {
                canvasRowHeader(
                    title: "Editing Flow",
                    detail: "Main Row edits the shortcut strip. Symbols and ABC edit expanded rows. Hold mode edits long-press legends. Delete Key removes visible keys when the row can shrink."
                )
                canvasRowHeader(
                    title: "Layers",
                    detail: "New layers are opened by assigning their token from the Layers category to any editable key."
                )
            }
        }
    }

    private var keymapInlineRowCountControlWidth: CGFloat {
        38
    }

    private func keymapInlineRowCountControl(for row: KeyboardRowKind) -> some View {
        keymapInlineRowCountButton(systemName: "plus", row: row, delta: 1)
        .frame(width: keymapInlineRowCountControlWidth, height: keymapInlineRowCountControlHeight(for: row))
    }

    private func keymapInlineRowCountButton(
        systemName: String,
        row: KeyboardRowKind,
        delta: Int
    ) -> some View {
        let canAdjust = canAdjustVisibleKeyCount(for: row, delta: delta)

        return Button {
            adjustVisibleKeyCount(for: row, delta: delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(canAdjust ? .white : subtleTextColor.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(buttonSurface(fill: canAdjust ? buttonBackgroundFill : buttonBackgroundFill.opacity(0.75)))
                .overlay(buttonSurfaceStroke(canAdjust ? previewTileBorder : previewTileBorder.opacity(0.6)))
        }
        .buttonStyle(StaticPressButtonStyle())
        .disabled(!canAdjust)
        .accessibilityLabel("Add key to \(row.tapVariant.title)")
    }

    private func keymapInlineRowCountControlHeight(for row: KeyboardRowKind) -> CGFloat {
        row.tapVariant == .toolbar
            ? CGFloat(settings.toolbarHeight)
            : CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))
    }

    private func customLayerInlineKeyCountControl(for row: KeyboardLayoutRow) -> some View {
        customLayerInlineKeyCountButton(systemName: "plus", row: row, delta: 1)
            .frame(width: keymapInlineRowCountControlWidth, height: 32)
    }

    private func customLayerInlineKeyCountButton(
        systemName: String,
        row: KeyboardLayoutRow,
        delta: Int
    ) -> some View {
        let canAdjust = canAdjustCustomLayerKeyCount(for: row, delta: delta)

        return Button {
            adjustCustomLayerKeyCount(for: row, delta: delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(canAdjust ? .white : subtleTextColor.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(buttonSurface(fill: canAdjust ? buttonBackgroundFill : buttonBackgroundFill.opacity(0.75)))
                .overlay(buttonSurfaceStroke(canAdjust ? previewTileBorder : previewTileBorder.opacity(0.6)))
        }
        .buttonStyle(StaticPressButtonStyle())
        .disabled(!canAdjust)
        .accessibilityLabel("Add key to \(row.kind.title)")
    }

    private func canAdjustVisibleKeyCount(for row: KeyboardRowKind, delta: Int) -> Bool {
        guard let count = visibleKeyCount(for: row),
              let range = visibleKeyCountRange(for: row) else { return false }
        return range.contains(count + delta)
    }

    private func canAdjustCustomLayerKeyCount(for row: KeyboardLayoutRow, delta: Int) -> Bool {
        guard row.customLayerID != nil else { return false }
        return KeyboardLayoutBounds.expandedCountRange.contains(row.keys.count + delta)
    }

    private func visibleKeyCount(for row: KeyboardRowKind) -> Int? {
        switch row.tapVariant {
        case .toolbar:
            return settings.toolbarKeyCount
        case .symbolTop:
            return settings.symbolTopRowKeyCount
        case .symbolMiddle:
            return settings.symbolMiddleRowKeyCount
        case .symbolBottom:
            return settings.symbolBottomRowKeyCount
        case .letterTop:
            return settings.letterTopRowKeyCount
        case .letterMiddle:
            return settings.letterMiddleRowKeyCount
        case .letterBottom:
            return settings.letterBottomRowKeyCount
        default:
            return nil
        }
    }

    private func visibleKeyCountRange(for row: KeyboardRowKind) -> ClosedRange<Int>? {
        switch row.tapVariant {
        case .toolbar:
            return KeyboardLayoutBounds.toolbarCountRange
        case .symbolTop, .symbolMiddle, .symbolBottom, .letterTop, .letterMiddle, .letterBottom:
            return KeyboardLayoutBounds.expandedCountRange
        default:
            return nil
        }
    }

    private func adjustVisibleKeyCount(for row: KeyboardRowKind, delta: Int) {
        guard canAdjustVisibleKeyCount(for: row, delta: delta) else { return }

        switch row.tapVariant {
        case .toolbar:
            settings.toolbarKeyCount = KeyboardLayoutBounds.clampedToolbarCount(settings.toolbarKeyCount + delta)
        case .symbolTop:
            settings.symbolTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolTopRowKeyCount + delta)
        case .symbolMiddle:
            settings.symbolMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolMiddleRowKeyCount + delta)
        case .symbolBottom:
            settings.symbolBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolBottomRowKeyCount + delta)
        case .letterTop:
            settings.letterTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterTopRowKeyCount + delta)
        case .letterMiddle:
            settings.letterMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterMiddleRowKeyCount + delta)
        case .letterBottom:
            settings.letterBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterBottomRowKeyCount + delta)
        default:
            return
        }

        clampSelectedSlotIndex()
    }

    private var topRowEditorCard: some View {
        sectionCard(title: "Top Row", detail: "Edit the main shortcut strip and its trailing controls.") {
            let toolbarValues = displayedValues(for: activeToolbarRow)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                }

                topRowHeightControl(
                    detail: "Adjust the visible height of this shortcut strip.",
                    previewValues: toolbarValues
                )

                HStack(spacing: 6) {
                    ForEach(toolbarValues.indices, id: \.self) { slotIndex in
                        topRowEditorKey(
                            value: toolbarValues[slotIndex],
                            row: activeToolbarRow,
                            slotIndex: slotIndex
                        )
                    }
                }

                toolbarPreview(showLeadingGlobe: false)
            }
        }
    }

    private func adjustCustomLayerKeyCount(for row: KeyboardLayoutRow, delta: Int) {
        guard canAdjustCustomLayerKeyCount(for: row, delta: delta) else { return }
        if delta > 0 {
            settings.insertKeymapTableColumn(after: row.keys.last?.id, rowID: row.id)
        } else if let keyID = row.keys.last?.id {
            settings.removeKeymapTableColumn(keyID: keyID, rowID: row.id)
        }
    }

    private var keyboardCanvasCard: AnyView {
        AnyView(
            sectionCard(
                title: "Live Keyboard Editor",
                detail: "Tap a key to edit its value, browse Key Blocks, or remove it.",
                content: keyboardCanvasCardBody
            )
        )
    }

    private var keyboardCanvasCardBody: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {

                unifiedKeyboardEditorLayerSwitcher

                liveEditorActionSelector

                keyboardCanvasSurface(content: keyboardCanvasSurfaceBody)

                keyboardLayerContextWarning

                if isABCLayerLocked {
                    abcLayerUnlockFooter
                } else if selectedEditActionMode == .hold {
                    canvasRowHeader(
                        title: "Hold Layer",
                        detail: "Hold legends act like a secondary layer. Leave a hold key empty if that key should only use its tap action."
                    )
                } else if !isKeyboardEditorExpanded {
                    canvasRowHeader(
                        title: "Editing Tips",
                        detail: "Use the layer picker to move between Main Row, Symbols, and ABC. Drag one editable key onto another to swap positions."
                    )
                } else if shouldShowABCLayerLockButton {
                    outlineButton("Lock") {
                        lockABCLayer()
                    }
                }
            }
        )
    }

    private var keymapTransferActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Import & Export")

            Text("Move the selected layer with a private .hwclayer file. Import adds a new Live Keyboard Editor layer without changing existing layers.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(subtleTextColor)

            HStack(spacing: 8) {
                outlineButton("Import Layer", role: .primary) {
                    showsKeymapFileImporter = true
                }
                .accessibilityIdentifier("keymap.transfer.import")
                .accessibilityHint("Choose a private HWC layer file and review it before adding")

                outlineButton("Export Layer") {
                    prepareSelectedLayerExport()
                }
                .accessibilityIdentifier("keymap.transfer.export")
                .accessibilityHint("Review and save the selected keymap layer")
            }
        }
    }

    private var keyboardCanvasSurfaceBody: AnyView {
        AnyView(
            ZStack(alignment: .bottom) {
                keyboardEditorBottomStrip
                expandedKeyboardEditorRows
                    .offset(y: -keyboardEditorExpandedRowsLift)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .frame(height: keyboardEditorSurfaceHeight, alignment: .bottom)
            .clipped()
        )
    }

    private var keyboardEditActionModeButtons: some View {
        HStack(spacing: 8) {
            ForEach(KeyboardEditActionMode.allCases) { mode in
                editorSegmentButton(
                    title: mode.title,
                    isSelected: mode == selectedEditActionMode
                ) {
                    selectedEditActionMode = mode
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func editorSegmentButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : subtleTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: keyboardEditorLayerSelectorHeight)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? tabAccentColor.opacity(0.34) : Color(red: 0.15, green: 0.15, blue: 0.17))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? tabAccentColor.opacity(0.75) : previewTileBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
                .buttonStyle(StaticPressButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var keyboardLayerContextWarning: some View {
        if selectedCustomLayerID != nil {
            canvasRowHeader(
                title: "Layer Warning",
                detail: "Additional Layers are expanded ABC or Symbols layers. Assign this layer token to a key so the keyboard has a path into it."
            )
        } else if keyboardEditorSurface == .mainRow {
            canvasRowHeader(
                title: "Main Row Warning",
                detail: "Main Row layers swap the shortcut strip. ABC, Delete, and Menu stay as escape paths."
            )
        } else if selectedExpandedLayer == .letters {
            canvasRowHeader(
                title: "ABC Warning",
                detail: "Default ABC letters drive touch typing. Locked letter keys warn before editing; utility and hold slots stay editable."
            )
        } else {
            canvasRowHeader(
                title: "Symbols Warning",
                detail: "Menu opens Symbols, ABC, and Additional Layers. Keep a Menu path before replacing it."
            )
        }
    }

    private var keyboardEditorBottomStrip: AnyView {
        if selectedCustomLayerID != nil {
            if selectedCustomLayerSurface == .mainRow {
                return AnyView(customLayerToolbarPreviewRow)
            }
            return AnyView(customLayerUtilityPreviewRow)
        }
        return isKeyboardEditorExpanded ? interactiveUtilityPreviewRow : interactiveToolbarPreviewRow
    }

    private var customLayerToolbarPreviewRow: some View {
        let toolbarHeight = keyboardEditorToolbarHeight

        return previewRowSurface {
            if let toolbarRow = selectedCustomLayerToolbarRow {
                HStack(spacing: previewToolbarSpacing) {
                    ForEach(Array(toolbarRow.keys.enumerated()), id: \.element.id) { pair in
                        customLayerCanvasKey(
                            row: toolbarRow,
                            key: pair.element,
                            rowIndex: 0,
                            keyIndex: pair.offset,
                            height: toolbarHeight
                        )
                    }

                    customLayerInlineKeyCountControl(for: toolbarRow)
                }
            }
        }
    }

    private var customLayerUtilityPreviewRow: some View {
        let toolbarHeight = keyboardEditorToolbarHeight

        return previewRowSurface {
            if let utilityRow = selectedCustomLayerUtilityRow {
                HStack(spacing: previewToolbarSpacing) {
                    ForEach(Array(utilityRow.keys.enumerated()), id: \.element.id) { pair in
                        customLayerCanvasKey(
                            row: utilityRow,
                            key: pair.element,
                            rowIndex: selectedCustomLayerPrimaryRows.count,
                            keyIndex: pair.offset,
                            height: toolbarHeight
                        )
                    }
                }
            }
        }
    }

    private var interactiveToolbarPreviewRow: AnyView {
        AnyView(
            previewRowSurface {
                let trailingUtilityValues = displayedValues(for: .trailingUtility)
                let toolbarValues = displayedValues(for: activeToolbarRow)
                let mainRowPrimaryTrailingEditorItems = Array(trailingUtilityValues.indices.prefix(1))
                let mainRowMenuTrailingEditorItems = Array(trailingUtilityValues.indices.dropFirst())

                HStack(spacing: previewToolbarSpacing) {
                    ForEach(toolbarValues.indices, id: \.self) { slotIndex in
                        topRowEditorKey(
                            value: toolbarValues[slotIndex],
                            row: activeToolbarRow,
                            slotIndex: slotIndex
                        )
                    }

                    ForEach(mainRowPrimaryTrailingEditorItems, id: \.self) { slotIndex in
                        topRowEditorKey(
                            value: trailingUtilityValues[slotIndex],
                            row: .trailingUtility,
                            slotIndex: slotIndex
                        )
                    }

                    ForEach(mainRowMenuTrailingEditorItems, id: \.self) { slotIndex in
                        utilityEditorKey(
                            value: trailingUtilityValues[slotIndex],
                            row: .trailingUtility,
                            slotIndex: slotIndex,
                            width: mainRowMenuControlWidth,
                            height: CGFloat(KeyboardLayoutBounds.clampedToolbarHeight(settings.toolbarHeight))
                        )
                    }
                }
            }
        )
    }

    private var keyboardEditorLayerSelectorHeight: CGFloat {
        32
    }

    private var keyboardEditorLayerHoldOverlay: some View {
        let options = keyboardEditorLayerOptions

        return KeyboardEditorLayerSegmentGestureOverlay(
            segmentCount: options.count,
            tapHandler: { index in
                guard options.indices.contains(index) else { return }
                withAnimation(layerDropletSpring) {
                    setKeyboardEditorLayerSelection(options[index].id)
                }
            },
            longPressHandler: { index in
                guard options.indices.contains(index) else { return }
                let option = options[index]
                withAnimation(layerDropletSpring) {
                    setKeyboardEditorLayerSelection(option.id)
                }
                presentCustomLayerHoldPrompt(option)
            },
            scrubHandler: { location, size, state in
                updateKeyboardEditorLayerScrub(
                    at: location,
                    selectorWidth: size.width,
                    state: state
                )
            }
        )
        .frame(height: keyboardEditorLayerSelectorHeight)
        .clipped()
    }

    private func updateKeyboardEditorLayerScrub(
        at location: CGPoint,
        selectorWidth: CGFloat,
        state: UIGestureRecognizer.State
    ) {
        switch state {
        case .began, .changed:
            layerDropletFingerLocation = location
            guard let target = HWCKeymapEditorLayerScrubPolicy.target(
                at: location,
                width: selectorWidth,
                customLayerCount: accessibleCustomKeymapLayers.count
            ) else { return }

            let selectionID: String
            switch target {
            case .main(let index):
                guard keyboardEditorLayerOptions.indices.contains(index) else { return }
                selectionID = keyboardEditorLayerOptions[index].id
            case .additional(let index):
                guard accessibleCustomKeymapLayers.indices.contains(index) else { return }
                selectionID = KeyboardEditorLayerOption.customIDPrefix
                    + accessibleCustomKeymapLayers[index].id.uuidString
            }
            if keyboardEditorLayerSelectionID != selectionID {
                setKeyboardEditorLayerSelection(selectionID)
            }
        case .ended, .cancelled, .failed:
            withAnimation(layerDropletSpring) {
                layerDropletFingerLocation = nil
            }
        default:
            break
        }
    }

    private var keyShelfPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(selectedKeyCardTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(subtleTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 12)

                selectedKeyValueChip(selectedKeyBinding.wrappedValue)

                keyShelfCloseButton
            }

            keyShelfCustomValueField

            keyShelfActionRow

            if let warning = selectedKeyModeChangeWarning {
                canvasRowHeader(title: "Mode Warning", detail: warning)
            }

            keyShelfMenuLibraryPanel
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(secondaryCardFill)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(previewTileBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 4)
        .animation(liveEditorSpring, value: selectedKeyShelfSectionID)
    }

    private var keyShelfCloseButton: some View {
        Button {
            withAnimation(liveEditorSpring) {
                isKeyShelfExpanded = false
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(buttonSurface(fill: buttonBackgroundFill))
                .overlay(buttonSurfaceStroke(previewTileBorder))
        }
        .buttonStyle(StaticPressButtonStyle())
        .accessibilityLabel("Hide Key Shelf")
    }

    private var keyShelfMenuLibraryPanel: some View {
        let sectionTitle = activeKeyShelfSection?.title ?? "Blocks"
        let totalCount = activeKeyShelfTokens.count
        let pageCount = keyShelfPageCount(for: totalCount)
        let currentPage = min(selectedKeyShelfTokenPage, max(0, pageCount - 1))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(subtleTextColor)

                    Text("\(totalCount) keys")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(subtleTextColor.opacity(0.72))
                }

                Spacer(minLength: 8)

                keyShelfCategoryMenu
            }

            keyShelfSearchField

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 52), spacing: 6)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(keyShelfVisibleTokens, id: \.self) { token in
                        keyBlockChip(token)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)

            if pageCount > 1 {
                keyShelfPageControls(pageCount: pageCount, currentPage: currentPage)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(buttonBackgroundFill.opacity(settings.appTheme.usesDarkChrome ? 0.70 : 0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(previewTileBorder.opacity(0.92), lineWidth: 1)
        )
    }

    private var keyShelfSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(subtleTextColor)

            TextField("Search", text: keyShelfSearchBinding)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if !keyShelfSearchText.isEmpty {
                Button {
                    keyShelfSearchBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(subtleTextColor)
                }
                .buttonStyle(StaticPressButtonStyle())
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(buttonBackgroundFill.opacity(settings.appTheme.usesDarkChrome ? 0.78 : 0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(previewTileBorder.opacity(0.85), lineWidth: 1)
        )
    }

    private func keyShelfPageControls(pageCount: Int, currentPage: Int) -> some View {
        HStack(spacing: 8) {
            compactOutlineButton("Prev", systemImage: "chevron.left") {
                selectedKeyShelfTokenPage = max(0, currentPage - 1)
            }
            .disabled(currentPage == 0)

            Spacer(minLength: 8)

            Text("\(currentPage + 1) / \(pageCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(subtleTextColor)

            Spacer(minLength: 8)

            compactOutlineButton("Next", systemImage: "chevron.right") {
                selectedKeyShelfTokenPage = min(pageCount - 1, currentPage + 1)
            }
            .disabled(currentPage >= pageCount - 1)
        }
    }

    private var keyShelfCategoryMenu: some View {
        Menu {
            ForEach(keyBlockSections) { section in
                Button {
                    selectedKeyShelfSectionID = section.id
                    selectedKeyShelfTokenPage = 0
                } label: {
                    Label(
                        section.title,
                        systemImage: section.id == activeKeyShelfSection?.id ? "checkmark" : "square.grid.2x2"
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Menu")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(buttonSurface(fill: buttonBackgroundFill))
            .overlay(buttonSurfaceStroke(previewTileBorder))
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private var keyShelfVisibleTokens: [String] {
        let tokens = activeKeyShelfTokens
        guard tokens.count > keyShelfTokenPageSize else {
            return tokens
        }

        let page = min(selectedKeyShelfTokenPage, max(0, keyShelfPageCount(for: tokens.count) - 1))
        let startIndex = page * keyShelfTokenPageSize
        let endIndex = min(tokens.count, startIndex + keyShelfTokenPageSize)

        return Array(tokens[startIndex..<endIndex])
    }

    private var activeKeyShelfTokens: [String] {
        let tokens = Self.uniqueKeyShelfTokens(activeKeyShelfSection?.tokens ?? paletteTokens)
        let query = keyShelfSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return tokens
        }
        return tokens.filter { value in
            value.localizedCaseInsensitiveContains(query) ||
                tokenLabel(value).localizedCaseInsensitiveContains(query)
        }
    }

    private var keyShelfSearchBinding: Binding<String> {
        Binding(
            get: { keyShelfSearchText },
            set: { newValue in
                keyShelfSearchText = newValue
                selectedKeyShelfTokenPage = 0
            }
        )
    }

    private var keyShelfTokenPageSize: Int {
        180
    }

    private func keyShelfPageCount(for tokenCount: Int) -> Int {
        max(1, Int(ceil(Double(tokenCount) / Double(keyShelfTokenPageSize))))
    }

    private var keyShelfCustomValueField: some View {
        HStack(spacing: 8) {
            TextField(
                selectedKeyFieldPlaceholder(for: selectedKeyBinding.wrappedValue),
                text: selectedKeyDisplayBinding
            )
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(buttonBackgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(previewTileBorder, lineWidth: 1)
                )

            compactOutlineButton("Paste", systemImage: "doc.on.clipboard") {
                pasteClipboardValueIntoSelectedKey()
            }
        }
    }

    private var keyShelfActionRow: some View {
        HStack(spacing: 8) {
            compactOutlineButton("Clear", systemImage: "xmark.square", role: .destructive) {
                setSelectedKeyValueWithModeChangeWarning("")
            }
            compactOutlineButton("Delete", systemImage: "trash", role: .destructive) {
                deleteSelectedKey()
            }
            compactOutlineButton("Restore", systemImage: "arrow.counterclockwise") {
                settings.restoreRow(selectedEditableRow)
            }
        }
    }

    private var keyBlockLibraryCard: some View {
        sectionCard(title: "Key Blocks", detail: "Tap a block to assign it, or drag it onto the live keyboard.") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(keyBlockSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        canvasRowHeader(title: section.title, detail: section.detail)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                            spacing: 8
                        ) {
                            ForEach(section.tokens, id: \.self) { token in
                                keyBlockChip(token)
                            }
                        }
                    }
                }
            }
        }
    }

    private var expandedKeyboardCard: some View {
        sectionCard(
            title: "Expanded Keyboard",
            detail: "Choose Symbols or ABC, then edit that layer. ABC keeps core controls fixed while Symbols keeps direct cursor controls."
        ) {
            let editableRows = expandedRows(for: selectedExpandedLayer)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                }

                Picker("Expanded Layout", selection: expandedLayerBinding) {
                    ForEach(ExpandedKeymapLayer.allCases) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                VStack(spacing: 10) {
                    ForEach(Array(editableRows.enumerated()), id: \.offset) { pair in
                        let rowValues = displayedValues(for: pair.element)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Row \(pair.offset + 1)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)

                            HStack(spacing: 6) {
                                ForEach(rowValues.indices, id: \.self) { slotIndex in
                                    expandedEditorKey(
                                        value: rowValues[slotIndex],
                                        row: pair.element,
                                        slotIndex: slotIndex
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var keymapInspectorCard: some View {
        sectionCard(title: "Selected Key", detail: "Inspect and update the currently selected key.") {
            VStack(alignment: .leading, spacing: 16) {
                canvasRowHeader(
                    title: selectedKeyCardTitle,
                    detail: selectedRowHelp
                )

                keyField(title: "Live Value", binding: selectedKeyGuardedBinding)

                canvasRowHeader(
                    title: "Label Length",
                    detail: "Words and sentences adapt to fit the live keyboard."
                )

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Key Palette")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(paletteTokens, id: \.self) { token in
                            Button(action: {
                                setSelectedKeyValueWithModeChangeWarning(token)
                            }) {
                                editorTokenChip(
                                    token,
                                    fill: buttonBackgroundFill,
                                    border: previewTileBorder,
                                    textColor: .white,
                                    iconColor: previewIconColor,
                                    height: 36,
                                    horizontalPadding: 10,
                                    cornerRadius: 4,
                                    compact: true
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(StaticPressButtonStyle())
                        }
                    }
                }

                HStack(spacing: 10) {
                    outlineButton("Clear Slot") {
                        setSelectedKeyValueWithModeChangeWarning("")
                    }
                    outlineButton("Restore Row") {
                        settings.restoreRow(selectedEditableRow)
                    }
                }
            }
        }
    }

    private func toolbarPreview(showLeadingGlobe: Bool = true) -> some View {
        let toolbarValues = displayedValues(for: activeToolbarRow)
        let trailingUtilityValues = displayedValues(for: .trailingUtility)

        return previewRowSurface {
            HStack(spacing: previewToolbarSpacing) {
                if showLeadingGlobe {
                    previewKey(icon: "globe", height: CGFloat(settings.toolbarHeight))
                }
                ForEach(toolbarValues.indices, id: \.self) { index in
                    previewValueKey(toolbarValues[index], height: CGFloat(settings.toolbarHeight))
                }
                ForEach(trailingUtilityValues.indices, id: \.self) { index in
                    previewValueKey(trailingUtilityValues[index], height: CGFloat(settings.toolbarHeight))
                }
            }
        }
    }

    private var utilityPreviewRow: some View {
        previewRowSurface {
            HStack(spacing: previewRowSpacing) {
                previewUtilityKey(text: settings.defaultSymbolLayer ? "ABC" : "123", width: 48)
                if settings.defaultSymbolLayer {
                    previewUtilityKey(text: "Tab", width: 44)
                    previewUtilityKey(icon: "arrow.left", width: 44)
                    previewUtilityKey(icon: "arrow.right", width: 44)
                    previewUtilityKey(label: previewSpaceLabel)
                } else {
                    previewUtilityKey(icon: "shift.fill", label: previewShiftLabel, width: 42)
                    previewUtilityKey(label: previewSpaceLabel)
                    previewUtilityKey(icon: "delete.backward", label: previewDeleteLabel, width: 42)
                    previewUtilityKey(icon: "chevron.down", width: 34)
                }
                if settings.defaultSymbolLayer {
                    previewUtilityKey(icon: "return.left", label: previewReturnLabel, width: 58)
                }
            }
        }
    }

    private var previewShiftLabel: String? {
        settings.showControlLabels ? "Shift" : nil
    }

    private var previewReturnLabel: String? {
        settings.showControlLabels ? "Return" : nil
    }

    private var previewDeleteLabel: String? {
        settings.showControlLabels ? "Delete" : nil
    }

    private var previewSpaceLabel: String? {
        settings.showControlLabels ? "Space" : nil
    }

    private var interactiveUtilityPreviewRow: AnyView {
        settings.appTheme.usesDarkChrome
            ? AnyView(darkInteractiveUtilityPreviewRow)
            : AnyView(classicInteractiveUtilityPreviewRow)
    }

    private var expandedKeyboardEditorRows: AnyView {
        AnyView(
            VStack(spacing: keyboardEditorExpandedRowSpacing) {
                if selectedCustomLayerID != nil && selectedCustomLayerSurface != .mainRow {
                    ForEach(Array(selectedCustomLayerPrimaryRows.enumerated()), id: \.element.id) { pair in
                        previewRowSurface {
                            HStack(spacing: previewRowSpacing) {
                                ForEach(Array(pair.element.keys.enumerated()), id: \.element.id) { keyPair in
                                    customLayerCanvasKey(
                                        row: pair.element,
                                        key: keyPair.element,
                                        rowIndex: pair.offset,
                                        keyIndex: keyPair.offset,
                                        height: CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))
                                    )
                                }

                                customLayerInlineKeyCountControl(for: pair.element)
                            }
                        }
                    }
                }

                if selectedCustomLayerID != nil {
                    EmptyView()
                } else if selectedExpandedLayer == .letters {
                    let letterRows = expandedRows(for: .letters)
                    let letterTopValues = previewDisplayedValues(for: letterRows[0])
                    let letterMiddleValues = previewDisplayedValues(for: letterRows[1])
                    let letterBottomValues = previewDisplayedValues(for: letterRows[2])
                    if settings.appTheme.usesDarkChrome {
                        darkExpandedEditorLetterRow(
                            values: letterTopValues,
                            row: letterRows[0]
                        )

                        darkExpandedEditorLetterRow(
                            values: letterMiddleValues,
                            row: letterRows[1]
                        )

                        darkExpandedEditorBottomLetterRow(
                            values: letterBottomValues,
                            row: letterRows[2]
                        )
                    } else {
                        classicExpandedEditorLetterRow(
                            values: letterTopValues,
                            row: letterRows[0],
                            horizontalInset: classicPreviewLetterTopInset
                        )

                        classicExpandedEditorLetterRow(
                            values: letterMiddleValues,
                            row: letterRows[1],
                            horizontalInset: classicPreviewLetterMiddleInset
                        )

                        classicExpandedEditorLetterRow(
                            values: letterBottomValues,
                            row: letterRows[2],
                            horizontalInset: classicPreviewBottomInset,
                            showsLeadingDeleteKey: true
                        )
                    }
                } else {
                    ForEach(Array(expandedRows(for: selectedExpandedLayer).enumerated()), id: \.offset) { pair in
                        let rowValues = displayedValues(for: pair.element)

                        previewRowSurface {
                            HStack(spacing: previewRowSpacing) {
                                ForEach(rowValues.indices, id: \.self) { slotIndex in
                                    expandedEditorKey(
                                        value: rowValues[slotIndex],
                                        row: pair.element,
                                        slotIndex: slotIndex
                                    )
                                }

                                keymapInlineRowCountControl(for: pair.element)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .frame(height: keyboardEditorExpandedRowsRevealHeight, alignment: .bottom)
            .clipped()
            .opacity(keyboardEditorExpandedRowsRevealHeight > 0 ? 1 : 0.001)
            .allowsHitTesting(isKeyboardEditorExpanded)
        )
    }

    private var classicPreviewLetterTopInset: CGFloat {
        max(6, min(14, CGFloat(settings.expandedKeyHeight) * 0.20))
    }

    private var classicPreviewLetterMiddleInset: CGFloat {
        max(18, min(32, CGFloat(settings.expandedKeyHeight) * 0.50))
    }

    private var classicPreviewBottomInset: CGFloat {
        max(10, min(20, CGFloat(settings.expandedKeyHeight) * 0.28))
    }

    private func classicPreviewBottomControlWidth(availableWidth: CGFloat) -> CGFloat {
        let bottomValues = displayedValues(for: .letterBottom)
        let letterCount = CGFloat(max(bottomValues.count, 1))
        let totalSpacing = previewRowSpacing * CGFloat(max(bottomValues.count + 1, 0))
        let unitWidth = max(0, (availableWidth - totalSpacing) / max(letterCount + 2.7, 1))
        return max(44, min(62, unitWidth * 1.35))
    }

    private func classicExpandedEditorLetterRow(
        values: [String],
        row: KeyboardRowKind,
        horizontalInset: CGFloat,
        showsLeadingDeleteKey: Bool = false
    ) -> some View {
        let expandedHeight = CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))

        return previewRowSurface {
            GeometryReader { proxy in
                let leadingDeleteWidth = showsLeadingDeleteKey
                    ? classicPreviewBottomControlWidth(availableWidth: proxy.size.width - (horizontalInset * 2))
                    : 0
                let inlineControlWidth = keymapInlineRowCountControlWidth
                let availableWidth = max(
                    0,
                    proxy.size.width
                        - (horizontalInset * 2)
                        - leadingDeleteWidth
                        - (showsLeadingDeleteKey ? previewRowSpacing : 0)
                        - inlineControlWidth
                        - previewRowSpacing
                )
                let widths = previewLetterRowWidths(
                    values: values,
                    row: row,
                    totalWidth: availableWidth,
                    spacing: previewRowSpacing
                )

                HStack(spacing: previewRowSpacing) {
                    if showsLeadingDeleteKey {
                        utilityEditorKey(
                            value: displayedValues(for: .letterBottomLeading).first ?? "",
                            row: .letterBottomLeading,
                            slotIndex: 0,
                            width: leadingDeleteWidth,
                            height: expandedHeight
                        )
                    }

                    ForEach(values.indices, id: \.self) { slotIndex in
                        expandedEditorKey(
                            value: values[slotIndex],
                            row: row,
                            slotIndex: slotIndex
                        )
                        .frame(width: widths[slotIndex])
                    }

                    keymapInlineRowCountControl(for: row)
                        .frame(width: inlineControlWidth)
                }
                .padding(.horizontal, horizontalInset)
            }
            .frame(height: expandedHeight)
        }
    }

    private func darkExpandedEditorLetterRow(
        values: [String],
        row: KeyboardRowKind
    ) -> some View {
        let expandedHeight = CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))

        return previewRowSurface {
            GeometryReader { proxy in
                let inlineControlWidth = keymapInlineRowCountControlWidth
                let contentWidth = max(0, proxy.size.width - inlineControlWidth)
                let widths = previewLetterRowWidths(values: values, row: row, totalWidth: contentWidth)

                HStack(spacing: 0) {
                    ForEach(values.indices, id: \.self) { slotIndex in
                        expandedEditorKey(
                            value: values[slotIndex],
                            row: row,
                            slotIndex: slotIndex
                        )
                        .frame(width: widths[slotIndex])
                    }

                    keymapInlineRowCountControl(for: row)
                        .frame(width: inlineControlWidth)
                }
            }
            .frame(height: expandedHeight)
        }
    }

    private func darkExpandedEditorBottomLetterRow(
        values: [String],
        row: KeyboardRowKind
    ) -> some View {
        let expandedHeight = CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))

        return previewRowSurface {
            GeometryReader { proxy in
                let spans = values.map { previewLetterWidthSpan(for: $0, row: row) }
                let totalUnits = max(1, spans.reduce(CGFloat(1), +))
                let inlineControlWidth = keymapInlineRowCountControlWidth
                let contentWidth = max(0, proxy.size.width - inlineControlWidth)
                let unitWidth = max(0, contentWidth / totalUnits)
                let deleteWidth = unitWidth
                let widths = spans.map { unitWidth * $0 }

                HStack(spacing: 0) {
                    utilityEditorKey(
                        value: displayedValues(for: .letterBottomLeading).first ?? "",
                        row: .letterBottomLeading,
                        slotIndex: 0,
                        width: deleteWidth,
                        height: expandedHeight
                    )

                    ForEach(values.indices, id: \.self) { slotIndex in
                        expandedEditorKey(
                            value: values[slotIndex],
                            row: row,
                            slotIndex: slotIndex
                        )
                        .frame(width: widths[slotIndex])
                    }

                    keymapInlineRowCountControl(for: row)
                        .frame(width: inlineControlWidth)
                }
            }
            .frame(height: expandedHeight)
        }
    }

    private var classicInteractiveUtilityPreviewRow: some View {
        let toolbarHeight = keyboardEditorToolbarHeight

        return previewRowSurface {
            GeometryReader { proxy in
                let spacing = previewToolbarSpacing
                let trailingUtilityRow = activeExpandedTrailingUtilityRow
                let trailingUtilityValues = displayedValues(for: trailingUtilityRow)

                if selectedExpandedLayer == .letters {
                    let controlWidth = classicExpandedLetterUtilityControlWidth(availableWidth: proxy.size.width)
                    let spaceWidth = max(0, proxy.size.width - (controlWidth * 4) - (spacing * 4))
                    let letterUtilityValues = displayedValues(for: .letterUtility)

                    HStack(spacing: spacing) {
                        utilityEditorKey(
                            value: letterUtilityValues[0],
                            row: .letterUtility,
                            slotIndex: 0,
                            width: controlWidth,
                            height: toolbarHeight
                        )
                        utilityEditorKey(
                            value: letterUtilityValues[1],
                            row: .letterUtility,
                            slotIndex: 1,
                            width: controlWidth,
                            height: toolbarHeight
                        )
                        utilityEditorKey(
                            value: letterUtilityValues[2],
                            row: .letterUtility,
                            slotIndex: 2,
                            width: spaceWidth,
                            height: toolbarHeight
                        )
                        utilityEditorKey(
                            value: trailingUtilityValues[0],
                            row: trailingUtilityRow,
                            slotIndex: 0,
                            width: controlWidth,
                            height: toolbarHeight
                        )
                        utilityEditorKey(
                            value: trailingUtilityValues[1],
                            row: trailingUtilityRow,
                            slotIndex: 1,
                            width: controlWidth,
                            height: toolbarHeight
                        )
                    }
                } else {
                    let unitWidth = classicExpandedSymbolUtilityUnitWidth(
                        availableWidth: proxy.size.width,
                        spacing: spacing
                    )
                    let symbolUtilityValues = displayedValues(for: .symbolUtility)

                    HStack(spacing: spacing) {
                        ForEach(symbolUtilityValues.indices, id: \.self) { slotIndex in
                            utilityEditorKey(
                                value: symbolUtilityValues[slotIndex],
                                row: .symbolUtility,
                                slotIndex: slotIndex,
                                width: unitWidth,
                                height: toolbarHeight
                            )
                        }
                        ForEach(trailingUtilityValues.indices, id: \.self) { slotIndex in
                            utilityEditorKey(
                                value: trailingUtilityValues[slotIndex],
                                row: trailingUtilityRow,
                                slotIndex: slotIndex,
                                width: unitWidth,
                                height: toolbarHeight
                            )
                        }
                    }
                }
            }
            .frame(height: toolbarHeight)
        }
    }

    private var darkInteractiveUtilityPreviewRow: some View {
        let toolbarHeight = keyboardEditorToolbarHeight
        let trailingUtilityRow = activeExpandedTrailingUtilityRow
        let trailingUtilityValues = displayedValues(for: trailingUtilityRow)

        return previewRowSurface {
            HStack(spacing: 0) {
                GeometryReader { proxy in
                    if selectedExpandedLayer == .letters {
                        let letterControlUnitWidth = max(0, proxy.size.width / 5)
                        let letterUtilityValues = displayedValues(for: .letterUtility)

                        HStack(spacing: 0) {
                            utilityEditorKey(
                                value: letterUtilityValues[0],
                                row: .letterUtility,
                                slotIndex: 0,
                                width: letterControlUnitWidth,
                                height: toolbarHeight
                            )
                            utilityEditorKey(
                                value: letterUtilityValues[1],
                                row: .letterUtility,
                                slotIndex: 1,
                                width: letterControlUnitWidth,
                                height: toolbarHeight
                            )
                            utilityEditorKey(
                                value: letterUtilityValues[2],
                                row: .letterUtility,
                                slotIndex: 2,
                                width: letterControlUnitWidth * 3,
                                height: toolbarHeight
                            )
                        }
                    } else {
                        let symbolUtilityValues = displayedValues(for: .symbolUtility)

                        HStack(spacing: 0) {
                            ForEach(symbolUtilityValues.indices, id: \.self) { slotIndex in
                                utilityEditorKey(
                                    value: symbolUtilityValues[slotIndex],
                                    row: .symbolUtility,
                                    slotIndex: slotIndex,
                                    height: toolbarHeight
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                ForEach(trailingUtilityValues.indices, id: \.self) { slotIndex in
                    utilityEditorKey(
                        value: trailingUtilityValues[slotIndex],
                        row: trailingUtilityRow,
                        slotIndex: slotIndex,
                        width: darkPreviewBottomTrailingWidth,
                        height: toolbarHeight
                    )
                }
            }
            .frame(height: toolbarHeight)
        }
    }

    private func classicExpandedLetterUtilityControlWidth(availableWidth: CGFloat) -> CGFloat {
        let totalSpacing = previewToolbarSpacing * 4
        return max(34, min(44, (availableWidth - totalSpacing) / 7))
    }

    private func classicExpandedSymbolUtilityUnitWidth(availableWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        let totalUnits = CGFloat(8)
        let totalSpacing = spacing * 7
        return max(0, (availableWidth - totalSpacing) / totalUnits)
    }

    private var abcLayerUnlockFooter: some View {
        abcEditingGatePanel(
            title: isABCPurchaseLocked ? "Unlock ABC Customization" : "Edit ABC Layout",
            detail: isABCPurchaseLocked
                ? "Unlock ABC customization to remap the default letter keys. Symbol slots and hold legends stay editable either way."
                : "ABC customization is available. Editing the default letters replaces the protected ABC touch map."
        )
    }

    @ViewBuilder
    private func abcEditingGatePanel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text(detail)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(subtleTextColor)
                .fixedSize(horizontal: false, vertical: true)

            if isABCPurchaseLocked {
                Text("Only default ABC letter keys are locked. Non-letter slots stay editable.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(subtleTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = abcUnlockStore.statusMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(tabAccentColor)
                }

                if let error = abcUnlockStore.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.58))
                }

                HStack(spacing: 10) {
                    outlineButton(abcUnlockStore.isRestoring ? "Restoring..." : "Restore Purchase") {
                        abcUnlockStore.restorePurchases()
                    }

                    solidButton(
                        abcUnlockStore.purchaseButtonTitle,
                        disabled: abcUnlockStore.isBusy
                    ) {
                        abcUnlockStore.purchaseUnlock()
                    }
                }
            } else if !showsABCUnlockPrompt {
                Text("Restore Default ABC Letters any time you want to turn the default touch map back on.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(subtleTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                solidButton("Edit ABC Layout") {
                    presentABCUnlockPrompt()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Editing these letters removes the default ABC touch map.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(subtleTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Non-letter slots stay editable either way.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(subtleTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    outlineButton("Cancel") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsABCUnlockPrompt = false
                        }
                    }

                    solidButton("Enable Editing") {
                        unlockABCLayer()
                    }
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        detail: String? = nil,
        detailID: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sectionCard(
            title: title,
            detail: detail,
            detailID: detailID,
            content: AnyView(content())
        )
    }

    private func sectionCard(
        title: String,
        detail: String? = nil,
        detailID: String? = nil,
        content: AnyView
    ) -> some View {
        cardContainer(
            content: AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    sectionCardHeader(title: title, detail: detail, detailID: detailID)

                    content
                }
            )
        )
    }

    private func canvasRowHeader(title: String, detail: String) -> some View {
        rowTitle(
            title,
            detail: detail,
            id: disclosureID("canvas", "\(title)|\(detail)")
        )
    }

    private func behaviorTutorialRow(title: String, tap: String, hold: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            featureBullet("Tap: \(tap)")
            featureBullet("Hold: \(hold)")
        }
    }

    private func keyboardCanvasSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: keyboardCanvasSurfaceCornerRadius, style: .continuous)

        return content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                keyboardCanvasSurfaceBackground(shape: shape)
            )
    }

    private func keyboardCanvasSurface(content: AnyView) -> some View {
        let shape = RoundedRectangle(cornerRadius: keyboardCanvasSurfaceCornerRadius, style: .continuous)

        return content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                keyboardCanvasSurfaceBackground(shape: shape)
            )
    }

    @ViewBuilder
    private func keyboardCanvasSurfaceBackground(shape: RoundedRectangle) -> some View {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            shape
                .fill(Color(red: 0.085, green: 0.085, blue: 0.09))
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    paletteGlowColor.opacity(0.06),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    shape
                        .stroke(keyboardCanvasSurfaceBorderColor, lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 7, x: 0, y: 3)
        case .dark:
            shape
                .fill(darkThemeKeyboardShellFill)
                .overlay(
                    Rectangle()
                        .fill(keyboardCanvasTopSeparatorColor)
                        .frame(height: 1),
                    alignment: .top
                )
                .overlay(
                    Rectangle()
                        .fill(keyboardCanvasBottomSeparatorColor)
                        .frame(height: 1),
                    alignment: .bottom
                )
                .overlay(
                    shape
                        .stroke(keyboardCanvasSurfaceBorderColor, lineWidth: 1)
                )
        }
    }

    private func keyField(title: String, binding: Binding<String>) -> some View {
        VStack(spacing: 6) {
            if binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TextField("Type custom text", text: binding)
                    .font(.system(size: 18, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .frame(height: 44)
                    .background(secondaryCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(previewTileBorder, lineWidth: 1)
                    )
            } else if shouldHideCustomFieldValue(for: binding.wrappedValue) {
                selectedKeyValueChip(binding.wrappedValue)
                    .frame(maxWidth: .infinity)
            } else {
                TextField("Type custom text", text: binding)
                    .font(.system(size: 18, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .frame(height: 44)
                    .background(secondaryCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(previewTileBorder, lineWidth: 1)
                    )
            }

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(subtleTextColor)
        }
    }

    private var hardwareKeyboardTestField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
                HardwareLabCaptureTextField(
                    text: $hardwareKeyboardTestText,
                    placeholder: "Tap here, then run the quick button sample",
                    focusRequestAt: hardwareLabCaptureFocusRequestAt,
                    isEnabled: hardwareKeyboardTestEnabled,
                    onKeyEvent: handleHardwareLabCapturedEvent
                )
                #else
                HardwareKeyboardOnlyTextField(
                    text: $hardwareKeyboardTestText,
                    placeholder: "Tap here, then type with the hardware keyboard",
                    isEnabled: hardwareKeyboardTestEnabled
                )
                #endif
            }
                .frame(height: 44)
                .padding(.horizontal, 12)
                .background(secondaryCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(previewTileBorder, lineWidth: 1)
                )

            HStack {
                Spacer()

                compactOutlineButton(
                    "Close Keyboard",
                    systemImage: "keyboard.chevron.compact.down"
                ) {
                    closeHardwareKeyboardTest()
                }
            }

            #if HWC_INTERNAL_BUILD
            if let hardwareLabExportMessage {
                Text(hardwareLabExportMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(subtleTextColor)
            }
            #endif
        }
    }

    #if HWC_INTERNAL_BUILD
    private var hardwareCalibrationCapturePad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(buttonBackgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isRawHardwareCalibrationActive ? tabAccentColor : previewTileBorder,
                            lineWidth: 1
                        )
                )

            VStack(spacing: 8) {
                Image(systemName: isRawHardwareCalibrationActive ? "keyboard.badge.ellipsis" : "keyboard")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Text(isRawHardwareCalibrationActive ? "App check running. Press hardware keys now." : "App check idle.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text("Press A, 1, Delete, Shift, Tab, Arrow. Hold A optional.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(subtleTextColor)
            }
            .padding(.horizontal, 12)

            KeyDebugCaptureBridge(
                isEnabled: isRawHardwareCalibrationActive,
                emitKeyUp: true
            ) { event in
                handleRawHardwareCalibrationEvent(event)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
        .frame(height: 108)
    }

    private var rawHardwareCalibrationSummary: HardwareCalibrationSummary {
        HardwareCalibrationSummary(events: rawHardwareCalibrationEvents)
    }

    private var liveHardwareCalibrationEvents: [KeyEvent] {
        guard let liveHardwareCalibrationStartedAt else { return [] }

        return monitor.events
            .filter { event in
                event.timestamp >= liveHardwareCalibrationStartedAt &&
                event.source != .appDebug
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var liveHardwareCalibrationSummary: HardwareCalibrationSummary {
        HardwareCalibrationSummary(events: liveHardwareCalibrationEvents)
    }

    private var hardwareCalibrationTimedFamilies: [HardwareCalibrationFamily] {
        switch hardwareCalibrationScanMode {
        case .quick:
            return HardwareCalibrationFamily.quickCases
        case .full:
            let repeatCases = HardwareCalibrationFamily.quickCases.filter { family in
                family.tokens.contains { $0.requiresRepeat }
            }
            return HardwareCalibrationFamily.allCases + repeatCases
        }
    }

    private var currentTimedHardwareCalibrationFamily: HardwareCalibrationFamily? {
        guard hardwareCalibrationScanPhase == .raw ||
            hardwareCalibrationScanPhase == .readyForLive ||
            hardwareCalibrationScanPhase == .live else {
            return nil
        }

        let families = hardwareCalibrationTimedFamilies
        guard families.indices.contains(hardwareCalibrationScanStepIndex) else { return nil }
        return families[hardwareCalibrationScanStepIndex]
    }

    private var isHardwareCalibrationTimedFlowActive: Bool {
        hardwareCalibrationScanPhase == .raw || hardwareCalibrationScanPhase == .live
    }

    private var hardwareCalibrationTimedStepTotal: Int {
        max(1, hardwareCalibrationTimedFamilies.count * 2)
    }

    private var hardwareCalibrationTimedStepOrdinal: Int {
        let familyCount = max(1, hardwareCalibrationTimedFamilies.count)

        switch hardwareCalibrationScanPhase {
        case .idle:
            return 0
        case .raw:
            return min(hardwareCalibrationScanStepIndex + 1, familyCount)
        case .readyForLive, .live:
            return min(familyCount + hardwareCalibrationScanStepIndex + 1, familyCount * 2)
        case .complete:
            return familyCount * 2
        }
    }

    private var hardwareCalibrationTimedStepSecondsLeft: Int {
        guard isHardwareCalibrationTimedFlowActive,
              let hardwareCalibrationStepDeadline else {
            return 0
        }

        return max(0, Int(ceil(hardwareCalibrationStepDeadline.timeIntervalSince(hardwareCalibrationClock))))
    }

    private var hardwareCalibrationTimedStepProgress: Double {
        guard isHardwareCalibrationTimedFlowActive,
              let hardwareCalibrationStepStartedAt else {
            return hardwareCalibrationScanPhase == .complete ? 1 : 0
        }

        let elapsed = hardwareCalibrationClock.timeIntervalSince(hardwareCalibrationStepStartedAt)
        return max(0, min(elapsed / hardwareCalibrationStepDuration, 1))
    }

    private var hardwareCalibrationRecommendationReady: Bool {
        quickHardwareCalibrationReady ||
        (hardwareCalibrationScanPhase == .complete && rawHardwareCalibrationSummary.hasSignal)
    }

    private var quickRequiredHardwareCalibrationFamilies: [HardwareCalibrationFamily] {
        HardwareCalibrationFamily.quickCases.filter { !$0.isOptional }
    }

    private var quickOptionalHardwareCalibrationFamily: HardwareCalibrationFamily? {
        HardwareCalibrationFamily.quickCases.first { family in
            family.isOptional &&
            (!family.isComplete(in: rawHardwareCalibrationSummary) ||
                !family.isComplete(in: liveHardwareCalibrationSummary))
        }
    }

    private var quickHardwareCalibrationTotalCount: Int {
        quickRequiredHardwareCalibrationFamilies.count
    }

    private var quickHardwareCalibrationRawCount: Int {
        quickRequiredHardwareCalibrationFamilies.reduce(into: 0) { partialResult, family in
            if family.isComplete(in: rawHardwareCalibrationSummary) {
                partialResult += 1
            }
        }
    }

    private var quickHardwareCalibrationLiveCount: Int {
        quickRequiredHardwareCalibrationFamilies.reduce(into: 0) { partialResult, family in
            if family.isComplete(in: liveHardwareCalibrationSummary) {
                partialResult += 1
            }
        }
    }

    private var quickHardwareCalibrationReady: Bool {
        quickHardwareCalibrationRawCount == quickHardwareCalibrationTotalCount &&
        quickHardwareCalibrationLiveCount == quickHardwareCalibrationTotalCount &&
        quickHardwareCalibrationTotalCount > 0
    }

    private var currentQuickHardwareCalibrationFamily: HardwareCalibrationFamily? {
        if let currentTimedHardwareCalibrationFamily {
            return currentTimedHardwareCalibrationFamily
        }

        if hardwareCalibrationScanPhase == .complete {
            return nil
        }

        return HardwareCalibrationFamily.quickCases.first { family in
            !family.isOptional &&
            (!family.isComplete(in: rawHardwareCalibrationSummary) ||
                !family.isComplete(in: liveHardwareCalibrationSummary))
        }
    }

    private var currentQuickHardwareCalibrationPhaseLabel: String {
        guard let currentQuickHardwareCalibrationFamily else { return "Done" }

        if hardwareCalibrationScanPhase == .raw {
            return "App"
        }

        if hardwareCalibrationScanPhase == .readyForLive ||
            hardwareCalibrationScanPhase == .live {
            return "Keyboard"
        }

        if !currentQuickHardwareCalibrationFamily.isComplete(in: rawHardwareCalibrationSummary) {
            return "App"
        }

        if !currentQuickHardwareCalibrationFamily.isComplete(in: liveHardwareCalibrationSummary) {
            return "Keyboard"
        }

        return "Done"
    }

    private var currentExtendedHardwareCalibrationFamily: HardwareCalibrationFamily? {
        HardwareCalibrationFamily.allCases.first { family in
            !family.isComplete(in: rawHardwareCalibrationSummary) ||
            !family.isComplete(in: liveHardwareCalibrationSummary)
        }
    }

    private var recommendedHardwareCalibrationProfile: HardwareCalibrationProfile? {
        guard hardwareCalibrationRecommendationReady else { return nil }

        if rawHardwareCalibrationSummary.hasSignal && !liveHardwareCalibrationSummary.hasSignal {
            return .universal
        }

        if !liveDroppedHardwareCalibrationTokens.isEmpty {
            return .universal
        }

        if hardwareCalibrationScanPhase == .complete &&
            quickHardwareCalibrationLiveCount < min(quickHardwareCalibrationRawCount, quickHardwareCalibrationTotalCount) {
            return .universal
        }

        let repeatDelays = [
            rawHardwareCalibrationSummary.firstRepeatDelayMs,
            liveHardwareCalibrationSummary.firstRepeatDelayMs
        ].compactMap { $0 }
        if let fastestRepeat = repeatDelays.min(), fastestRepeat < 320 {
            return .universal
        }

        if (rawHardwareCalibrationSummary.sawArrows && !liveHardwareCalibrationSummary.sawArrows) ||
            (rawHardwareCalibrationSummary.sawShift && !liveHardwareCalibrationSummary.sawShift) ||
            (rawHardwareCalibrationSummary.sawTab && !liveHardwareCalibrationSummary.sawTab) {
            return .navigationSafe
        }

        return .balanced
    }

    private var hardwareCalibrationAutoApplyFingerprint: String {
        guard hardwareCalibrationRecommendationReady,
              let recommendedHardwareCalibrationProfile else {
            return "idle"
        }

        let keyUpSeen = (rawHardwareCalibrationSummary.keyUpCount > 0 ||
            liveHardwareCalibrationSummary.keyUpCount > 0)
            ? "keyup"
            : "nodup"
        let rawRepeatDelay = rawHardwareCalibrationSummary.firstRepeatDelayMs ?? -1
        let liveRepeatDelay = liveHardwareCalibrationSummary.firstRepeatDelayMs ?? -1

        return [
            recommendedHardwareCalibrationProfile.rawValue,
            hardwareCalibrationScanPhase.rawValue,
            keyUpSeen,
            String(rawRepeatDelay),
            String(liveRepeatDelay),
            String(rawHardwareCalibrationSummary.eventCount),
            String(liveHardwareCalibrationSummary.eventCount)
        ].joined(separator: "|")
    }

    private var hardwareCalibrationHeadline: String? {
        if hardwareCalibrationScanPhase == .readyForLive {
            return "App check done. Tap the keyboard-check field, then start the keyboard pass."
        }

        if rawHardwareCalibrationSummary.eventCount == 0 && liveHardwareCalibrationSummary.eventCount == 0 {
            return nil
        }

        if rawHardwareCalibrationSummary.eventCount == 0 {
            return "Start the app check first."
        }

        if quickHardwareCalibrationRawCount < quickHardwareCalibrationTotalCount {
            return hardwareCalibrationScanPhase == .complete
                ? "Timed setup finished, but the app check missed required keys."
                : "Finish the app check first."
        }

        if liveHardwareCalibrationSummary.eventCount == 0 {
            return "App check done. Run the same few buttons with HWC Keyboard selected."
        }

        if quickHardwareCalibrationLiveCount < quickHardwareCalibrationTotalCount {
            return hardwareCalibrationScanPhase == .complete
                ? "Timed setup finished with keyboard-check misses."
                : "Finish the keyboard check and HWC will calibrate itself."
        }

        guard let recommendedHardwareCalibrationProfile else {
            return "Quick calibration data ready."
        }

        switch recommendedHardwareCalibrationProfile {
        case .balanced:
            return "Quick calibration says Balanced looks safe."
        case .navigationSafe:
            return "Quick calibration says Nav Safe should protect navigation keys."
        case .universal:
            return "Quick calibration says Universal should use broader keyboard compatibility for this board."
        }
    }

    private var hardwareCalibrationDetail: String? {
        guard let recommendedHardwareCalibrationProfile else { return nil }
        return hardwareCalibrationSettings(for: recommendedHardwareCalibrationProfile).detail
    }

    private var hardwareCalibrationFindings: [String] {
        var findings = [String]()

        if rawHardwareCalibrationSummary.eventCount == 0 {
            findings.append("App check still empty. Press A, 1, Delete, Shift, Tab, and one arrow in the companion first.")
        } else if quickHardwareCalibrationRawCount < quickHardwareCalibrationTotalCount {
            findings.append(
                hardwareCalibrationScanPhase == .complete
                    ? "App timed scan missed some required quick keys. This can mean the key is absent, remapped, or blocked by iOS."
                    : "App check not finished yet. Follow the current step card until App reaches \(quickHardwareCalibrationTotalCount)/\(quickHardwareCalibrationTotalCount)."
            )
        }

        if liveHardwareCalibrationSummary.eventCount == 0 {
            findings.append("Keyboard check still empty. Start Keyboard Check, tap the field, keep HWC on screen, then press the same few buttons again.")
        } else if quickHardwareCalibrationLiveCount < quickHardwareCalibrationTotalCount {
            findings.append(
                hardwareCalibrationScanPhase == .complete
                    ? "Keyboard timed scan missed keys that the app check saw or expected. HWC will prefer the safer profile."
                    : "Keyboard check not finished yet. Follow the current step card until Keyboard reaches \(quickHardwareCalibrationTotalCount)/\(quickHardwareCalibrationTotalCount)."
            )
        }

        if rawHardwareCalibrationSummary.hasSignal && !liveHardwareCalibrationSummary.hasSignal {
            findings.append("The companion app sees the hardware keyboard, but HWC Keyboard is still missing it.")
        }

        if rawHardwareCalibrationSummary.sawArrows && !liveHardwareCalibrationSummary.sawArrows {
            findings.append("Arrow or navigation keys drop out once input moves through HWC Keyboard.")
        }

        if rawHardwareCalibrationSummary.sawShift && !liveHardwareCalibrationSummary.sawShift {
            findings.append("Shift or modifier state is weaker in the keyboard check.")
        }

        if !liveDroppedHardwareCalibrationTokens.isEmpty {
            findings.append(
                "Keyboard check missed app-check keys: \(liveDroppedHardwareCalibrationTokens.prefix(8).joined(separator: ", ")). Universal mode stays on for this board."
            )
        }

        if !rawUnavailableHardwareCalibrationTokens.isEmpty {
            findings.append(
                "No app-check event for: \(rawUnavailableHardwareCalibrationTokens.prefix(8).joined(separator: ", ")). If those keys exist, system setup or keyboard mapping is blocking/remapping them."
            )
        }

        if rawHardwareCalibrationSummary.keyUpCount > 0 &&
            liveHardwareCalibrationSummary.keyUpCount == 0 &&
            liveHardwareCalibrationSummary.eventCount > 0 {
            findings.append("Keyboard sample is only surfacing press events right now.")
        }

        if findings.isEmpty &&
            hardwareCalibrationRecommendationReady {
            findings.append("App and keyboard checks agree on the buttons detected so far.")
        }

        return findings
    }

    private var liveDroppedHardwareCalibrationTokens: [String] {
        uniqueHardwareCalibrationTokenLabels(
            HardwareCalibrationFamily.allCases.flatMap { family in
                family.tokenTitles(
                    matchedIn: rawHardwareCalibrationSummary,
                    missingIn: liveHardwareCalibrationSummary
                ).map { "\(family.title) \($0)" }
            }
        )
    }

    private var rawUnavailableHardwareCalibrationTokens: [String] {
        guard rawHardwareCalibrationSummary.eventCount > 0 else { return [] }

        return uniqueHardwareCalibrationTokenLabels(
            HardwareCalibrationFamily.allCases
                .filter(\.isOptional)
                .flatMap { family in
                    family.missingTokenTitles(in: rawHardwareCalibrationSummary).map {
                        "\(family.title) \($0)"
                    }
                }
        )
    }

    private func uniqueHardwareCalibrationTokenLabels(_ labels: [String]) -> [String] {
        var unique = [String]()
        var seen = Set<String>()

        for label in labels where seen.insert(label).inserted {
            unique.append(label)
        }

        return unique
    }

    private func hardwareCalibrationSettings(
        for profile: HardwareCalibrationProfile
    ) -> (priorityMode: Bool, emitKeyUp: Bool, holdTriggerMs: Int, detail: String) {
        let baseHoldTrigger = calibratedHardwareHoldTriggerMs
        let emitKeyUp = settings.signalRelayEmitKeyUp ||
            rawHardwareCalibrationSummary.keyUpCount > 0 ||
            liveHardwareCalibrationSummary.keyUpCount > 0

        switch profile {
        case .balanced:
            return (
                priorityMode: true,
                emitKeyUp: emitKeyUp,
                holdTriggerMs: max(250, min(baseHoldTrigger, 360)),
                detail: "Balanced keeps normal hold timing when letters, delete, and tested navigation keys line up."
            )
        case .navigationSafe:
            return (
                priorityMode: true,
                emitKeyUp: emitKeyUp,
                holdTriggerMs: max(300, min(baseHoldTrigger, 420)),
                detail: "Nav Safe keeps broader compatibility on so arrows, tab, escape, and modifiers stay visible to HWC Keyboard."
            )
        case .universal:
            return (
                priorityMode: true,
                emitKeyUp: true,
                holdTriggerMs: max(420, baseHoldTrigger),
                detail: "Universal uses the broadest keyboard compatibility and slower hold trigger for keyboards that still drop events or feel unstable."
            )
        }
    }

    private var calibratedHardwareHoldTriggerMs: Int {
        let detectedRepeatDelay = liveHardwareCalibrationSummary.firstRepeatDelayMs ??
            rawHardwareCalibrationSummary.firstRepeatDelayMs

        guard let detectedRepeatDelay else {
            return KeyboardLayoutBounds.clampedHardwareHoldTriggerMs(settings.signalRelayHoldTriggerMs)
        }

        return KeyboardLayoutBounds.clampedHardwareHoldTriggerMs(max(320, detectedRepeatDelay + 80))
    }

    private func startHardwareCalibrationTimedFlow(mode: HardwareCalibrationScanMode) {
        guard !isHardwarePremiumLocked else { return }

        hardwareCalibrationAppliedMessage = nil
        lastAutoAppliedHardwareCalibrationFingerprint = nil
        hardwareCalibrationScanMode = mode
        hardwareCalibrationScanPhase = .raw
        hardwareCalibrationScanStepIndex = 0
        rawHardwareCalibrationEvents = []
        monitor.clear()
        liveHardwareCalibrationStartedAt = nil
        hardwareKeyboardTestText = ""
        beginHardwareCalibrationTimedStep(now: Date())
    }

    private func startHardwareCalibrationLiveTimedPass() {
        guard !isHardwarePremiumLocked else { return }
        guard hardwareCalibrationScanPhase == .readyForLive else { return }

        hardwareCalibrationAppliedMessage = nil
        lastAutoAppliedHardwareCalibrationFingerprint = nil
        hardwareCalibrationScanPhase = .live
        hardwareCalibrationScanStepIndex = 0
        settings.signalRelayEnabled = true
        settings.applyHardwareKeypressReadingDefaults(clearSession: false)
        monitor.clear()
        liveHardwareCalibrationStartedAt = Date().addingTimeInterval(-0.05)
        hardwareKeyboardTestText = ""
        beginHardwareCalibrationTimedStep(now: Date())
    }

    private func stopHardwareCalibrationTimedFlow() {
        isRawHardwareCalibrationActive = false
        hardwareCalibrationScanPhase = .idle
        hardwareCalibrationStepStartedAt = nil
        hardwareCalibrationStepDeadline = nil
    }

    private func resetHardwareCalibrationScan(clearSamples: Bool) {
        stopHardwareCalibrationTimedFlow()
        hardwareCalibrationScanMode = .quick
        hardwareCalibrationScanStepIndex = 0
        hardwareCalibrationAppliedMessage = nil
        lastAutoAppliedHardwareCalibrationFingerprint = nil

        if clearSamples {
            rawHardwareCalibrationEvents = []
            monitor.clear()
            liveHardwareCalibrationStartedAt = nil
            hardwareKeyboardTestText = ""
        }
    }

    private func beginHardwareCalibrationTimedStep(now: Date) {
        hardwareCalibrationClock = now
        hardwareCalibrationStepStartedAt = now
        hardwareCalibrationStepDeadline = now.addingTimeInterval(hardwareCalibrationStepDuration)

        switch hardwareCalibrationScanPhase {
        case .raw:
            isRawHardwareCalibrationActive = true
            dismissActiveKeyboard()
        case .live:
            isRawHardwareCalibrationActive = false
            settings.signalRelayEnabled = true
            settings.applyHardwareKeypressReadingDefaults(clearSession: false)
            if liveHardwareCalibrationStartedAt == nil {
                liveHardwareCalibrationStartedAt = now.addingTimeInterval(-0.05)
            }
        case .idle, .readyForLive, .complete:
            isRawHardwareCalibrationActive = false
        }
    }

    private func advanceHardwareCalibrationTimedFlowIfNeeded(now: Date) {
        guard isHardwareCalibrationTimedFlowActive,
              let family = currentTimedHardwareCalibrationFamily,
              let hardwareCalibrationStepDeadline else {
            return
        }

        let summary = hardwareCalibrationScanPhase == .raw
            ? rawHardwareCalibrationSummary
            : liveHardwareCalibrationSummary
        let didMatch = family.isComplete(in: summary)
        let didTimeout = now >= hardwareCalibrationStepDeadline

        if didMatch || didTimeout {
            advanceHardwareCalibrationTimedStep(now: now)
        }
    }

    private func advanceHardwareCalibrationTimedStep(now: Date) {
        guard isHardwareCalibrationTimedFlowActive else { return }

        let families = hardwareCalibrationTimedFamilies
        if hardwareCalibrationScanStepIndex + 1 < families.count {
            hardwareCalibrationScanStepIndex += 1
            beginHardwareCalibrationTimedStep(now: now)
            return
        }

        switch hardwareCalibrationScanPhase {
        case .raw:
            isRawHardwareCalibrationActive = false
            hardwareCalibrationScanPhase = .readyForLive
            hardwareCalibrationScanStepIndex = 0
            hardwareCalibrationStepStartedAt = nil
            hardwareCalibrationStepDeadline = nil
            hardwareKeyboardTestText = ""
        case .live:
            isRawHardwareCalibrationActive = false
            hardwareCalibrationScanPhase = .complete
            hardwareCalibrationScanStepIndex = max(0, families.count - 1)
            hardwareCalibrationStepStartedAt = nil
            hardwareCalibrationStepDeadline = nil
            autoApplyHardwareCalibrationIfNeeded()
        case .idle, .readyForLive, .complete:
            break
        }
    }

    private func startRawHardwareCalibration() {
        resetHardwareCalibrationScan(clearSamples: false)
        hardwareCalibrationAppliedMessage = nil
        lastAutoAppliedHardwareCalibrationFingerprint = nil
        isRawHardwareCalibrationActive = true
        rawHardwareCalibrationEvents = []
        dismissActiveKeyboard()
    }

    private func stopRawHardwareCalibration() {
        isRawHardwareCalibrationActive = false
    }

    private func clearRawHardwareCalibration() {
        resetHardwareCalibrationScan(clearSamples: false)
        lastAutoAppliedHardwareCalibrationFingerprint = nil
        rawHardwareCalibrationEvents = []
        isRawHardwareCalibrationActive = false
    }

    private func startLiveHardwareCalibration() {
        resetHardwareCalibrationScan(clearSamples: false)
        hardwareCalibrationAppliedMessage = nil
        lastAutoAppliedHardwareCalibrationFingerprint = nil
        isRawHardwareCalibrationActive = false
        settings.signalRelayEnabled = true
        settings.applyHardwareKeypressReadingDefaults(clearSession: false)
        monitor.clear()
        liveHardwareCalibrationStartedAt = Date().addingTimeInterval(-0.05)
        hardwareKeyboardTestText = ""
    }

    private func clearLiveHardwareCalibration() {
        resetHardwareCalibrationScan(clearSamples: false)
        lastAutoAppliedHardwareCalibrationFingerprint = nil
        monitor.clear()
        liveHardwareCalibrationStartedAt = nil
        hardwareKeyboardTestText = ""
    }

    private func applyHardwareCalibration(
        _ profile: HardwareCalibrationProfile,
        autoApplied: Bool = false
    ) {
        let nextSettings = hardwareCalibrationSettings(for: profile)
        settings.signalRelayEnabled = true
        settings.applyHardwareKeypressReadingDefaults(clearSession: false)
        settings.signalRelayEmitKeyUp = true
        settings.signalRelayPriorityMode = nextSettings.priorityMode
        settings.signalRelaySessionPersist = true
        settings.signalRelayHoldTriggerMs = nextSettings.holdTriggerMs
        appliedHardwareCalibrationProfile = profile
        if hardwareCalibrationAutoApplyFingerprint != "idle" {
            lastAutoAppliedHardwareCalibrationFingerprint = hardwareCalibrationAutoApplyFingerprint
        }
        hardwareCalibrationAppliedMessage = autoApplied
            ? "Quick calibration applied \(profile.title). More Keys is only needed if this keyboard still feels wrong."
            : "Hardware Keyboard now using \(profile.title): \(nextSettings.detail)"
    }

    private func autoApplyHardwareCalibrationIfNeeded() {
        guard !isHardwarePremiumLocked,
              hardwareCalibrationRecommendationReady,
              let recommendedHardwareCalibrationProfile else {
            return
        }

        let fingerprint = hardwareCalibrationAutoApplyFingerprint
        guard fingerprint != "idle",
              fingerprint != lastAutoAppliedHardwareCalibrationFingerprint else {
            return
        }

        applyHardwareCalibration(recommendedHardwareCalibrationProfile, autoApplied: true)
    }

    private func handleRawHardwareCalibrationEvent(_ event: KeyEvent) {
        guard isRawHardwareCalibrationActive else { return }
        let maxCalibrationEventCount = max(512, KeyEventRing.capacity)

        rawHardwareCalibrationEvents.append(event)

        if rawHardwareCalibrationEvents.count > maxCalibrationEventCount {
            rawHardwareCalibrationEvents.removeFirst(
                rawHardwareCalibrationEvents.count - maxCalibrationEventCount
            )
        }
    }

    private func hardwareCalibrationSummaryGrid(_ summary: HardwareCalibrationSummary) -> some View {
        EmptyView()
    }

    private func hardwareCalibrationPromptLine(_ line: String, emphasis: Bool) -> some View {
        Text(line)
            .font(.system(size: emphasis ? 15 : 13, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: emphasis ? 40 : 34)
            .background(buttonBackgroundFill.opacity(emphasis ? 1.0 : 0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        emphasis ? tabAccentColor.opacity(0.35) : previewTileBorder,
                        lineWidth: 1
                    )
            )
    }

    private func hardwareCalibrationFindingRow(_ finding: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "dot.scope")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tabAccentColor)
                .padding(.top, 2)

            Text(finding)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(subtleTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

    @ViewBuilder
    private func rowTitle(
        _ title: String,
        detail: String? = nil,
        id: String? = nil,
        color: Color = .white
    ) -> some View {
        if let detail, !detail.isEmpty {
            infoDisclosureHeader(
                title: title,
                detail: detail,
                id: id ?? disclosureID("row", "\(title)|\(detail)"),
                titleSize: 15,
                titleWeight: .semibold,
                detailSize: 12,
                titleColor: color,
                detailColor: subtleTextColor
            )
        } else {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private func numericSliderRow(
        title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String
    ) -> some View {
        let doubleValue = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { newValue in
                let safeStep = max(step, 1)
                let rounded = Int((newValue / Double(safeStep)).rounded()) * safeStep
                value.wrappedValue = min(max(rounded, range.lowerBound), range.upperBound)
            }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                rowTitle(
                    title,
                    detail: detail,
                    id: disclosureID("slider", "\(title)|\(detail)")
                )

                Spacer(minLength: 12)

                Text("\(value.wrappedValue) \(suffix)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(secondaryCardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(previewTileBorder, lineWidth: 1)
                    )
            }

            Slider(
                value: doubleValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(max(step, 1))
            )
            .tint(tabAccentColor)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.isEmpty ? title : "\(title). \(detail)")
        .accessibilityValue("\(value.wrappedValue) \(suffix)")
    }

    private func topRowHeightControl(
        detail: String,
        previewValues: [String]? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            numericSliderRow(
                title: "Top Row Height",
                detail: detail,
                value: $settings.toolbarHeight,
                range: KeyboardLayoutBounds.toolbarHeightRange,
                step: 1,
                suffix: "pt"
            )

            if let previewValues {
                topRowHeightThemePreviews(values: previewValues)
            }
        }
    }

    private func topRowHeightThemePreviews(values: [String]) -> some View {
        let previewValues = Array(values.prefix(5))

        return HStack(spacing: 10) {
            topRowHeightThemePreview(theme: .classic, values: previewValues)
            topRowHeightThemePreview(theme: .dark, values: previewValues)
        }
    }

    private func topRowHeightThemePreview(
        theme: CompanionAppTheme,
        values: [String]
    ) -> some View {
        let height = CGFloat(KeyboardLayoutBounds.clampedToolbarHeight(settings.toolbarHeight))
        let spacing: CGFloat = theme.usesDarkChrome ? 0 : 4

        return VStack(alignment: .leading, spacing: 7) {
            Text(theme.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(subtleTextColor)

            HStack(spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { item in
                    topRowHeightPreviewKey(item.element, theme: theme, height: height)
                }
            }
            .padding(theme.usesDarkChrome ? 0 : 5)
            .frame(maxWidth: .infinity)
            .background(topRowHeightPreviewBackground(theme: theme))
            .overlay(
                RoundedRectangle(cornerRadius: theme.usesDarkChrome ? 0 : 6, style: .continuous)
                    .stroke(topRowHeightPreviewBorder(theme: theme), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func topRowHeightPreviewKey(
        _ value: String,
        theme: CompanionAppTheme,
        height: CGFloat
    ) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cornerRadius = theme.usesDarkChrome ? CGFloat(0) : max(4, min(7, height * 0.16))
        let fontSize = max(11, min(16, height * 0.34))

        return Text(trimmed.isEmpty ? "-" : tokenLabel(trimmed))
            .font(.system(size: fontSize, weight: theme.usesDarkChrome ? .regular : .medium))
            .foregroundColor(topRowHeightPreviewText(theme: theme))
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(topRowHeightPreviewKeyFill(theme: theme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(topRowHeightPreviewBorder(theme: theme), lineWidth: 1)
            )
    }

    private func topRowHeightPreviewBackground(theme: CompanionAppTheme) -> Color {
        switch theme {
        case .classic, .chameleon, .custom:
            return Color.black.opacity(0.18)
        case .dark:
            return Color.black.opacity(0.92)
        }
    }

    private func topRowHeightPreviewKeyFill(theme: CompanionAppTheme) -> Color {
        switch theme {
        case .classic, .chameleon, .custom:
            return Color(red: 0.17, green: 0.17, blue: 0.18)
        case .dark:
            return Color(red: 0.14, green: 0.14, blue: 0.15)
        }
    }

    private func topRowHeightPreviewBorder(theme: CompanionAppTheme) -> Color {
        switch theme {
        case .classic, .chameleon, .custom:
            return Color.white.opacity(0.12)
        case .dark:
            return Color.white.opacity(0.10)
        }
    }

    private func topRowHeightPreviewText(theme: CompanionAppTheme) -> Color {
        switch theme {
        case .classic, .chameleon, .custom:
            return Color.white.opacity(0.92)
        case .dark:
            return Color(red: 0.72, green: 0.72, blue: 0.73)
        }
    }

    private func toggleRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        disabled: Bool = false
    ) -> some View {
        return HStack(alignment: .top, spacing: 14) {
            rowTitle(
                title,
                detail: detail,
                id: disclosureID("toggle", "\(title)|\(detail)"),
                color: disabled ? subtleTextColor : .white
            )

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: tabAccentColor))
                .disabled(disabled)
        }
        .opacity(disabled ? 0.78 : 1.0)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.isEmpty ? title : "\(title). \(detail)")
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    private func actionRow(
        title: String,
        detail: String,
        actionTitle: String = "Open",
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        return HStack(alignment: .top, spacing: 14) {
            rowTitle(
                title,
                detail: detail,
                id: disclosureID("action", "\(title)|\(detail)"),
                color: disabled ? subtleTextColor : .white
            )

            Spacer(minLength: 12)

            compactOutlineButton(
                actionTitle,
                systemImage: "doc.on.clipboard",
                disabled: disabled,
                action: action
            )
        }
        .opacity(disabled ? 0.78 : 1.0)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.isEmpty ? title : "\(title). \(detail)")
    }

    #if HWC_INTERNAL_BUILD
    private func syncHardwareKeyMonitor() {
        guard hardwareMonitorEnabled else {
            monitor.stop()
            return
        }

        monitor.start()
    }
    #else
    private func syncHardwareKeyMonitor() {}
    #endif

    #if HWC_INTERNAL_BUILD
    private func recordCompanionHardwareDiagnostic(_ code: KeyDiagCode) {
        KeyDiagStore.append(
            component: .companion,
            code: code,
            flags: companionHardwareDiagnosticFlags
        )
    }
    #endif

    private func enforceHardwarePremiumAccess() {
        // Reader is retired. Preserve saved preferences and the purchase ledger.
    }

    private func reportSupportAccessDiagnostics() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["HWC_TIP_PURCHASE_DIAGNOSTICS"] == "1" else { return }
        print("HWC support access: supportUnlocked=\(supportDeveloperStore.isUnlocked), unlimitedLayers=\(hasUnlimitedAdditionalLayerAccess), abcAccess=\(!isABCPurchaseLocked), hardwareReadingAccess=\(!isHardwarePremiumLocked)")
        #endif
    }

    private func setHardwareKeypressReadingMaster(_ isEnabled: Bool) {
        if isEnabled {
            enforceHardwarePremiumAccess()
            guard !isHardwarePremiumLocked else {
                settings.disableHardwareKeypressReading(clearSession: true)
                return
            }
        }
        settings.signalRelayEnabled = isEnabled
        if isEnabled {
            settings.applyHardwareKeypressReadingDefaults(clearSession: true)
        } else {
            settings.disableHardwareKeypressReading(clearSession: true)
            #if HWC_INTERNAL_BUILD
            monitor.clear()
            #endif
        }
    }

    private func resetLocalPurchasesForCurrentBuild() {
        guard isCurrentBuildPurchaseResetAvailable else { return }
        let status = "Local purchase unlocks reset for this build."
        abcUnlockStore.resetLocalPurchaseForCurrentBuild(statusMessage: status)
        hardwarePremiumStore.resetLocalPurchaseForCurrentBuild(statusMessage: status)
        supportDeveloperStore.resetLocalPurchaseForCurrentBuild(statusMessage: status)
        settings.setHardwarePremiumAccessUnlocked(false, clearSession: true)
        settings.disableHardwareKeypressReading(clearSession: true)
    }

    private var isCurrentBuildPurchaseResetAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "130"
    }

    private var hardwareKeypressReadingBinding: Binding<Bool> {
        Binding(
            get: { settings.signalRelayEnabled },
            set: { isEnabled in
                setHardwareKeypressReadingMaster(isEnabled)
            }
        )
    }

    private var hardwareAutocorrectSelectorBinding: Binding<Bool> {
        Binding(
            get: { settings.hardwareAutocorrectSelectorEnabled },
            set: { isEnabled in
                if isEnabled {
                    setHardwareKeypressReadingMaster(true)
                    settings.hardwareAutocorrectSelectorEnabled = !isHardwarePremiumLocked
                } else {
                    settings.hardwareAutocorrectSelectorEnabled = false
                }
            }
        )
    }

    private func formattedReleaseNotesTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: timestamp)
    }

    private func solidButton(
        _ title: String,
        role: HWCCompanionActionRole = .primary,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 42)

        return Button(action: action) {
            label
        }
        .hwcCompanionActionStyle(role, tint: tabAccentColor)
        .disabled(disabled)
        .frame(minHeight: 44)
    }

    private func outlineButton(
        _ title: String,
        role: HWCCompanionActionRole = .secondary,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(disabled ? subtleTextColor : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 42)

        return Button(action: action) {
            label
        }
        .hwcCompanionActionStyle(role, tint: tabAccentColor)
        .disabled(disabled)
        .frame(minHeight: 44)
    }

    private func compactOutlineButton(
        _ title: String,
        systemImage: String,
        role: HWCCompanionActionRole = .secondary,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(disabled ? subtleTextColor : .white)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .hwcCompanionActionStyle(role, tint: tabAccentColor)
        .disabled(disabled)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func closeHardwareKeyboardTest() {
        dismissActiveKeyboard()
    }

    #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
    private func handleHardwareLabCapturedEvent(_ event: KeyEvent) {
        let cutoff = Date().addingTimeInterval(-(Self.hardwareLabEventMatchWindow * 4))
        hardwareLabCapturedEvents.append(event)
        hardwareLabCapturedEvents.removeAll { $0.timestamp < cutoff }

        if hardwareLabCapturedEvents.count > 96 {
            hardwareLabCapturedEvents.removeFirst(hardwareLabCapturedEvents.count - 96)
        }
    }

    private func handleHardwareLabTextChange(_ newValue: String) {
        let previousText = previousHardwareKeyboardTestText
        previousHardwareKeyboardTestText = newValue
        hardwareLabExportMessage = nil
        guard newValue != previousText else { return }

        let observedAt = Date()
        recordHardwareLabTextChange(previousText: previousText, currentText: newValue, observedAt: observedAt)
    }

    private func recordHardwareLabTextChange(previousText: String, currentText: String, observedAt: Date) {
        guard let event = hardwareLabMatchedTextEvent(observedAt: observedAt)
            ?? hardwareLabFallbackTextEvent(
                previousText: previousText,
                currentText: currentText,
                observedAt: observedAt
            ) else {
            hardwareLabExportMessage = "Waiting for fresh captured key event."
            return
        }

        if hardwareLabCapturedEvents.contains(where: { $0.id == event.id }) {
            hardwareLabConsumedEventIDs.insert(event.id)
        }
        let expectedTextDelta = hardwareLabExpectedTextDelta(
            event: event,
            previousText: previousText,
            currentText: currentText
        )
        let evidenceEvent = HardwareLabModifierEvidence.eventByMergingRecentCaseModifiers(
            event: event,
            expectedTextDelta: expectedTextDelta,
            recentEvents: hardwareLabCapturedEvents,
            observedAt: observedAt,
            matchWindow: Self.hardwareLabEventMatchWindow
        )
        monitor.recordHardwareLabTextChange(
            event: evidenceEvent,
            expectedTextDelta: expectedTextDelta,
            previousText: previousText,
            currentText: currentText
        )
    }

    private func hardwareLabMatchedTextEvent(observedAt: Date) -> KeyEvent? {
        hardwareLabCapturedEvents
            .filter { $0.phase == .down }
            .filter { !hardwareLabConsumedEventIDs.contains($0.id) }
            .filter { !isHardwareLabModifierOnlyEvent($0) }
            .filter { observedAt.timeIntervalSince($0.timestamp) >= -0.05 }
            .filter { observedAt.timeIntervalSince($0.timestamp) <= Self.hardwareLabEventMatchWindow }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    private func hardwareLabFallbackTextEvent(
        previousText: String,
        currentText: String,
        observedAt: Date
    ) -> KeyEvent? {
        let delta = hardwareLabObservedTextDelta(previousText: previousText, currentText: currentText)
        guard !delta.isEmpty else { return nil }

        return KeyEvent(
            timestamp: observedAt,
            source: .appDebug,
            phase: .down,
            characters: delta,
            charactersIgnoringModifiers: delta
        )
    }

    private func isHardwareLabModifierOnlyEvent(_ event: KeyEvent) -> Bool {
        switch event.keyCode {
        case Int(UIKeyboardHIDUsage.keyboardLeftShift.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightShift.rawValue),
             Int(UIKeyboardHIDUsage.keyboardLeftControl.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightControl.rawValue),
             Int(UIKeyboardHIDUsage.keyboardLeftAlt.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightAlt.rawValue),
             Int(UIKeyboardHIDUsage.keyboardLeftGUI.rawValue),
             Int(UIKeyboardHIDUsage.keyboardRightGUI.rawValue),
             Int(UIKeyboardHIDUsage.keyboardCapsLock.rawValue),
             Int(UIKeyboardHIDUsage.keyboardLockingCapsLock.rawValue):
            return true
        default:
            return event.characters == "⇧" ||
                event.modifiers.contains(.command) ||
                event.modifiers.contains(.control) ||
                event.modifiers.contains(.option)
        }
    }

    private func hardwareLabExpectedTextDelta(
        event: KeyEvent,
        previousText: String,
        currentText: String
    ) -> String {
        if let characters = event.characters,
           !characters.isEmpty {
            return characters
        }

        return hardwareLabObservedTextDelta(previousText: previousText, currentText: currentText)
    }

    private func hardwareLabObservedTextDelta(previousText: String, currentText: String) -> String {
        if currentText.hasPrefix(previousText) {
            return String(currentText.dropFirst(previousText.count))
        }

        let prefix = currentText.commonPrefix(with: previousText)
        return String(currentText.dropFirst(prefix.count))
    }
    #endif

    private func dismissActiveKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func previewRow(_ values: [String]) -> some View {
        previewRowSurface {
            HStack(spacing: previewRowSpacing) {
                ForEach(values.indices, id: \.self) { index in
                    previewValueKey(values[index], height: CGFloat(settings.expandedKeyHeight))
                }
            }
        }
    }

    private func expandedEditorKey(value: String, row: KeyboardRowKind, slotIndex: Int) -> some View {
        let expandedHeight = CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))

        return editableCanvasKey(
            value: value,
            row: row,
            slotIndex: slotIndex,
            height: expandedHeight
        )
    }

    private func topRowEditorKey(value: String, row: KeyboardRowKind, slotIndex: Int) -> some View {
        let toolbarHeight = CGFloat(KeyboardLayoutBounds.clampedToolbarHeight(settings.toolbarHeight))

        return editableCanvasKey(
            value: value,
            row: row,
            slotIndex: slotIndex,
            height: toolbarHeight
        )
    }

    private func utilityEditorKey(
        value: String,
        row: KeyboardRowKind,
        slotIndex: Int,
        width: CGFloat? = nil,
        height: CGFloat
    ) -> some View {
        let isSelected = isSelectedEditorKey(row, slotIndex: slotIndex)

        return canvasKeyDragSource(payload: keyDragPayload(row: row, slotIndex: slotIndex, value: value)) {
            Button(action: {
                presentKeyEditor(row: row, slotIndex: slotIndex)
            }) {
                editableUtilityPreview(value: value, width: width, height: height)
                    .overlay(
                        RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                            .fill(isSelected ? liveEditorSelectedKeyFill : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                            .stroke(
                                isSelected ? selectedAccentBorderColor : Color.clear,
                                lineWidth: settings.highContrastKeys ? 1.8 : 1.4
                            )
                    )
                    .scaleEffect(isSelected ? liveEditorSelectedKeyScale : 1)
                    .shadow(
                        color: isSelected ? liveEditorSelectedKeyShadowColor : Color.clear,
                        radius: isSelected ? 10 : 0,
                        x: 0,
                        y: isSelected ? 4 : 0
                    )
                    .animation(liveEditorSpring, value: isSelected)
            }
            .buttonStyle(StaticPressButtonStyle())
            .accessibilityIdentifier("keymap.key.\(row.rawValue).\(slotIndex)")
            .onDrop(of: ["public.text"], isTargeted: nil) { providers in
                applyDroppedKeyValue(from: providers, to: row, slotIndex: slotIndex)
            }
        }
    }

    private func editableCanvasKey(
        value: String,
        row: KeyboardRowKind,
        slotIndex: Int,
        height: CGFloat
    ) -> some View {
        let isSelected = isSelectedEditorKey(row, slotIndex: slotIndex)

        return canvasKeyDragSource(payload: keyDragPayload(row: row, slotIndex: slotIndex, value: value)) {
            Button(action: {
                presentKeyEditor(row: row, slotIndex: slotIndex)
            }) {
                let legendAlignment = hardwareLegendAlignment(for: row, slotIndex: slotIndex)
                let primaryAlignment = hardwarePrimaryAlignment(for: row, slotIndex: slotIndex)
                let showsABCTapLegendLayout = selectedEditActionMode == .tap && row.tapVariant.isABCLetterRow
                let usesHardwarePrimaryAlignment = showsABCTapLegendLayout && settings.appTheme.usesDarkChrome
                let primaryFontSize: CGFloat = showsABCTapLegendLayout ? 14 : 16
                let label = Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        editablePrimaryLegend(
                            value: value,
                            fontSize: primaryFontSize,
                            usesHardwareAlignment: usesHardwarePrimaryAlignment
                        )
                        .padding(.horizontal, usesHardwarePrimaryAlignment ? 9 : 0)
                        .padding(.top, usesHardwarePrimaryAlignment ? 7 : 0)
                        .offset(x: usesHardwarePrimaryAlignment ? editablePrimaryLegendHorizontalOffset(for: row, slotIndex: slotIndex) : 0),
                        alignment: usesHardwarePrimaryAlignment ? primaryAlignment : .center
                    )
                    .overlay(
                        Group {
                            if let holdLegend = holdLegend(for: row, slotIndex: slotIndex) {
                                editableHoldLegend(holdLegend)
                            }
                        },
                        alignment: legendAlignment
                    )
                    .frame(height: height)

                label
                    .background(
                        ZStack {
                            buttonSurface(fill: buttonBackgroundFill)

                            if isSelected {
                                buttonSurface(fill: liveEditorSelectedKeyFill)
                            }
                        }
                    )
                    .overlay(
                        buttonSurfaceStroke(
                            Color(red: 0.24, green: 0.24, blue: 0.26)
                        )
                    )
                    .overlay(
                        buttonSurfaceStroke(
                            isSelected ? selectedAccentBorderColor : Color.clear,
                            lineWidth: settings.highContrastKeys ? 1.8 : 1.4
                        )
                    )
                    .scaleEffect(isSelected ? liveEditorSelectedKeyScale : 1)
                    .shadow(
                        color: isSelected ? liveEditorSelectedKeyShadowColor : Color.clear,
                        radius: isSelected ? 10 : 0,
                        x: 0,
                        y: isSelected ? 4 : 0
                    )
                    .animation(liveEditorSpring, value: isSelected)
            }
            .buttonStyle(StaticPressButtonStyle())
            .accessibilityIdentifier("keymap.key.\(row.rawValue).\(slotIndex)")
            .onDrop(of: ["public.text"], isTargeted: nil) { providers in
                applyDroppedKeyValue(from: providers, to: row, slotIndex: slotIndex)
            }
        }
    }

    private func customLayerCanvasKey(
        row: KeyboardLayoutRow,
        key: KeyboardLayoutKey,
        rowIndex: Int,
        keyIndex: Int,
        height: CGFloat
    ) -> some View {
        let selection = CustomLayerEditorKeySelection(
            layerID: row.customLayerID ?? selectedCustomLayerID ?? UUID(),
            rowID: row.id,
            keyID: key.id,
            rowIndex: rowIndex,
            keyIndex: keyIndex
        )
        let value = selectedEditActionMode == .hold ? (key.hold ?? "") : key.tap
        let isSelected = selectedCustomLayerKeySelection == selection

        return Button(action: {
            selectCustomLayerKeyForEditing(selection)
            presentSelectedKeyEditor()
        }) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    editablePrimaryLegend(
                        value: value,
                        fontSize: 16,
                        usesHardwareAlignment: false
                    ),
                    alignment: .center
                )
                .frame(height: height)
                .background(
                    ZStack {
                        buttonSurface(fill: buttonBackgroundFill)
                        if isSelected {
                            buttonSurface(fill: liveEditorSelectedKeyFill)
                        }
                    }
                )
                .overlay(buttonSurfaceStroke(Color(red: 0.24, green: 0.24, blue: 0.26)))
                .overlay(
                    buttonSurfaceStroke(
                        isSelected ? selectedAccentBorderColor : Color.clear,
                        lineWidth: settings.highContrastKeys ? 1.8 : 1.4
                    )
                )
                .scaleEffect(isSelected ? liveEditorSelectedKeyScale : 1)
                .shadow(
                    color: isSelected ? liveEditorSelectedKeyShadowColor : Color.clear,
                    radius: isSelected ? 10 : 0,
                    x: 0,
                    y: isSelected ? 4 : 0
                )
                .animation(liveEditorSpring, value: isSelected)
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private func editableUtilityPreview(
        value: String,
        width: CGFloat? = nil,
        height: CGFloat
    ) -> some View {
        let visual = utilityTokenVisual(for: value)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        return previewUtilityKey(
            text: visual?.text ?? (trimmedValue.isEmpty ? "·" : tokenLabel(trimmedValue)),
            icon: visual?.icon,
            label: visual?.label,
            width: width,
            height: height
        )
    }

    private func holdLegend(for row: KeyboardRowKind, slotIndex: Int) -> String? {
        guard !row.isHoldRow,
              row.tapVariant.isABCLetterRow,
              selectedEditActionMode == .tap else {
            return nil
        }

        let values = displayedValues(for: row.holdVariant)
        guard values.indices.contains(slotIndex) else { return nil }

        let legend = values[slotIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return legend.isEmpty ? nil : legend
    }

    @ViewBuilder
    private func editablePrimaryLegend(
        value: String,
        fontSize: CGFloat,
        usesHardwareAlignment: Bool
    ) -> some View {
        if let customLayerVisual = customLayerTokenVisual(value) {
            let legendFrameWidth = usesHardwareAlignment ? editablePrimaryLegendBoxWidth : nil
            let legendFrameHeight = max(20, fontSize + 8)
            let iconSize = max(10, min(fontSize - 1, usesHardwareAlignment ? 12 : 13))
            let labelSize = max(9, min(fontSize - 3, usesHardwareAlignment ? 10 : 11))

            VStack(spacing: 2) {
                Image(systemName: customLayerVisual.icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(previewIconColor)

                Text(customLayerVisual.title)
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundColor(previewTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(width: legendFrameWidth, height: legendFrameHeight, alignment: .center)
        } else if let specialAction = KeyboardSpecialKeyAction.resolved(from: value) {
            editableSpecialActionLegend(
                specialAction,
                fontSize: fontSize,
                usesHardwareAlignment: usesHardwareAlignment
            )
        } else {
            let legendFrameWidth = usesHardwareAlignment ? editablePrimaryLegendBoxWidth : nil
            let legendFrameHeight = max(20, fontSize + 4)
            let displayValue = value.isEmpty ? "·" : tokenLabel(value)
            let legend = HWKKeyLegendPresentation.resolve(displayValue)
            let label = Text(legend.text)
                .font(
                    .system(
                        size: min(fontSize, CGFloat(legend.maximumFontSize)),
                        weight: usesHardwareAlignment ? .medium : .semibold
                    )
                )
                .foregroundColor(previewTextColor)
                .lineLimit(legend.lineLimit)
                .minimumScaleFactor(legend.minimumScaleFactor)
                .multilineTextAlignment(.center)
                .allowsTightening(true)
                .accessibilityLabel(legend.accessibilityText)

            if legend.usesFullKeyWidth {
                label
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
            } else {
                label
                    .frame(width: legendFrameWidth, height: legendFrameHeight, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func editableSpecialActionLegend(
        _ action: KeyboardSpecialKeyAction,
        fontSize: CGFloat,
        usesHardwareAlignment: Bool
    ) -> some View {
        let visual = utilityTokenVisual(for: action.storageToken)
        let legendFrameWidth = usesHardwareAlignment ? editablePrimaryLegendBoxWidth : nil
        let legendFrameHeight = max(20, fontSize + 8)
        let iconSize = max(10, min(fontSize - 1, usesHardwareAlignment ? 12 : 13))
        let labelSize = max(9, min(fontSize - 3, usesHardwareAlignment ? 10 : 11))
        let labelText = visual?.label ?? visual?.text ?? tokenLabel(action.storageToken)

        Group {
            if action == .menu {
                VStack(spacing: 2) {
                    PreviewToolbarMenuMorphIcon(
                        isExpanded: false,
                        color: previewIconColor,
                        lineWidth: usesHardwareAlignment ? 1.5 : 1.7
                    )
                    .frame(width: iconSize + 1, height: iconSize + 1)

                    Text(labelText)
                        .font(.system(size: labelSize, weight: .semibold))
                        .foregroundColor(previewTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else if let icon = visual?.icon, let label = visual?.label {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(previewIconColor)

                    Text(label)
                        .font(.system(size: labelSize, weight: .semibold))
                        .foregroundColor(previewTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else if let icon = visual?.icon {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(previewIconColor)
            } else {
                Text(labelText)
                    .font(.system(size: max(labelSize, 10), weight: .semibold))
                    .foregroundColor(previewTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: legendFrameWidth, height: legendFrameHeight, alignment: .center)
    }

    private func editableHoldLegend(_ value: String) -> some View {
        Group {
            if let action = KeyboardSpecialKeyAction.resolved(from: value) {
                if action == .menu {
                    PreviewToolbarMenuMorphIcon(
                        isExpanded: false,
                        color: subtleTextColor.opacity(0.9),
                        lineWidth: 1.4
                    )
                    .frame(width: 10, height: 10)
                } else if let systemImage = editorTokenIconName(for: action) {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(subtleTextColor.opacity(0.9))
                } else if let visual = utilityTokenVisual(for: action.storageToken),
                          let text = visual.text ?? visual.label {
                    Text(text)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(subtleTextColor.opacity(0.9))
                } else {
                    Text(tokenLabel(action.storageToken))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(subtleTextColor.opacity(0.9))
                }
            } else {
                Text(tokenLabel(value))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(subtleTextColor.opacity(0.9))
            }
        }
        .frame(width: editableHoldLegendBoxWidth, alignment: .center)
        .padding(.bottom, 4)
    }

    private func tokenLabel(_ token: String) -> String {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let customLayerLabel = customLayerTokenLabel(trimmedToken) {
            return customLayerLabel
        }

        guard let action = KeyboardSpecialKeyAction.resolved(from: trimmedToken) else {
            return humanizedLegacyActionTokenLabel(trimmedToken) ?? trimmedToken
        }

        switch action {
        case .toggleLayer:
            return selectedExpandedLayer == .letters ? "123" : "ABC"
        case .toggleSymbolPage:
            return selectedExpandedLayer == .symbols2 ? "123" : "#+="
        case .deleteBackward:
            return "Delete"
        case .menu:
            return "Menu"
        default:
            return action.shelfTitle
        }
    }

    private func customLayerTokenLabel(_ token: String) -> String? {
        guard let layerID = KeyboardCustomLayer.id(fromStorageToken: token),
              canAccessCustomLayer(layerID),
              let layer = settings.customKeymapLayers.first(where: { $0.id == layerID }) else {
            return nil
        }
        return layer.title
    }

    private func customLayerTokenVisual(_ token: String) -> (icon: String, title: String)? {
        guard let layerID = KeyboardCustomLayer.id(fromStorageToken: token),
              canAccessCustomLayer(layerID),
              let layer = settings.customKeymapLayers.first(where: { $0.id == layerID }) else {
            return nil
        }
        return (layer.iconSystemName, layer.title)
    }

    private func humanizedLegacyActionTokenLabel(_ token: String) -> String? {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.hasPrefix("@"), trimmedToken.count > 1 else {
            return nil
        }

        let legacyBody = String(trimmedToken.dropFirst())
        let normalizedToken = legacyBody
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
            .lowercased()

        switch normalizedToken {
        case "enter", "return":
            return "Return"
        case "shift", "caps", "capslock", "alphashift":
            return "Shift"
        case "layer", "symbols", "togglelayer", "toggle", "123", "abc":
            return "123 / ABC"
        case "space", "spacebar":
            return "Space"
        case "tab":
            return "Tab"
        case "delete", "deletebackward", "backwarddelete", "backspace", "back", "bksp", "deleteleft":
            return "Backspace"
        case "fwddel", "fwddelete", "forwarddelete", "forwarddel", "deleteforward", "deletefwd", "fdel":
            return "Fwd Delete"
        case "left", "arrowleft", "cursorleft", "moveleft":
            return "Left"
        case "right", "arrowright", "cursorright", "moveright":
            return "Right"
        case "menu", "more", "expand", "morekey":
            return "Menu"
        case "globe", "nextkeyboard", "nextkb", "nextinput", "keyboardnext":
            return "Globe"
        default:
            guard looksLikeLegacyActionTokenBody(legacyBody) else {
                return nil
            }
            return formattedLegacyActionTokenLabel(legacyBody)
        }
    }

    private func looksLikeLegacyActionTokenBody(_ rawValue: String) -> Bool {
        guard !rawValue.isEmpty else {
            return false
        }

        if rawValue.contains(where: { $0 == "_" || $0 == "-" || $0 == "/" || $0 == "." }) {
            return true
        }

        return rawValue.contains { character in
            let scalarString = String(character)
            return scalarString.rangeOfCharacter(from: .uppercaseLetters) != nil ||
                scalarString.rangeOfCharacter(from: .decimalDigits) != nil
        }
    }

    private func formattedLegacyActionTokenLabel(_ rawValue: String) -> String? {
        guard !rawValue.isEmpty else {
            return nil
        }

        var spacedValue = ""
        var previousWasLowerOrDigit = false

        for character in rawValue {
            if character == "_" || character == "-" || character == "/" || character == "." {
                if !spacedValue.hasSuffix(" ") {
                    spacedValue.append(" ")
                }
                previousWasLowerOrDigit = false
                continue
            }

            let scalarString = String(character)
            let isUppercase = scalarString.rangeOfCharacter(from: .uppercaseLetters) != nil
            let isLowercase = scalarString.rangeOfCharacter(from: .lowercaseLetters) != nil
            let isDigit = scalarString.rangeOfCharacter(from: .decimalDigits) != nil

            if isUppercase && previousWasLowerOrDigit && !spacedValue.hasSuffix(" ") {
                spacedValue.append(" ")
            }

            spacedValue.append(character)
            previousWasLowerOrDigit = isLowercase || isDigit
        }

        let words = spacedValue
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !words.isEmpty else {
            return nil
        }

        let formattedWords = words.map { word -> String in
            switch word.lowercased() {
            case "abc":
                return "ABC"
            case "fwd":
                return "Fwd"
            case "del":
                return "Delete"
            case "bksp":
                return "Backspace"
            case "kb":
                return "Keyboard"
            case "glb":
                return "Globe"
            default:
                return word.capitalized
            }
        }

        let label = formattedWords.joined(separator: " ")
        return label.isEmpty ? nil : label
    }

    private func shouldHideCustomFieldValue(for value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return KeyboardSpecialKeyAction.resolved(from: trimmedValue) != nil ||
            humanizedLegacyActionTokenLabel(trimmedValue) != nil
    }

    private func utilityTokenVisual(for token: String) -> KeyTokenVisual? {
        guard let action = KeyboardSpecialKeyAction.resolved(from: token) else {
            return nil
        }

        switch action {
        case .enter:
            return KeyTokenVisual(
                text: nil,
                icon: "return.left",
                label: previewReturnLabel
            )
        case .shift:
            return KeyTokenVisual(
                text: nil,
                icon: "shift.fill",
                label: previewShiftLabel
            )
        case .toggleLayer:
            return KeyTokenVisual(
                text: selectedExpandedLayer == .letters ? "123" : "ABC",
                icon: nil,
                label: nil
            )
        case .toggleSymbolPage:
            return KeyTokenVisual(
                text: selectedExpandedLayer == .symbols2 ? "123" : "#+=",
                icon: nil,
                label: nil
            )
        case .space:
            return KeyTokenVisual(
                text: previewSpaceLabel == nil ? "Space" : nil,
                icon: nil,
                label: previewSpaceLabel
            )
        case .tab:
            return KeyTokenVisual(text: "Tab", icon: nil, label: nil)
        case .undo:
            return KeyTokenVisual(text: nil, icon: "arrow.uturn.backward", label: "Undo")
        case .cut:
            return KeyTokenVisual(text: nil, icon: "scissors", label: "Cut")
        case .copy:
            return KeyTokenVisual(text: nil, icon: "doc.on.doc", label: "Copy")
        case .paste:
            return KeyTokenVisual(text: nil, icon: "doc.on.clipboard", label: "Paste")
        case .clipboard:
            return KeyTokenVisual(text: nil, icon: "tray.full", label: "Clipboard")
        case .redo:
            return KeyTokenVisual(text: nil, icon: "arrow.uturn.forward", label: "Redo")
        case .deleteBackward:
            return KeyTokenVisual(
                text: nil,
                icon: settings.appTheme.usesDarkChrome ? "delete.backward.fill" : "delete.backward",
                label: "Delete"
            )
        case .deleteForward:
            return KeyTokenVisual(
                text: nil,
                icon: "delete.forward",
                label: tokenLabel(token)
            )
        case .moveLeft:
            return KeyTokenVisual(text: nil, icon: "arrow.left", label: "Left")
        case .moveRight:
            return KeyTokenVisual(text: nil, icon: "arrow.right", label: "Right")
        case .moveUp:
            return KeyTokenVisual(text: nil, icon: "arrow.up", label: "Up")
        case .moveDown:
            return KeyTokenVisual(text: nil, icon: "arrow.down", label: "Down")
        case .menu:
            return KeyTokenVisual(
                text: nil,
                icon: "line.3.horizontal",
                label: "Menu"
            )
        case .nextKeyboard:
            return KeyTokenVisual(text: nil, icon: "globe", label: "Globe")
        }
    }

    private func editorTokenIconName(for action: KeyboardSpecialKeyAction) -> String? {
        switch action {
        case .enter:
            return "return.left"
        case .shift:
            return "shift.fill"
        case .deleteBackward:
            return settings.appTheme.usesDarkChrome ? "delete.backward.fill" : "delete.backward"
        case .deleteForward:
            return "delete.forward"
        case .undo:
            return "arrow.uturn.backward"
        case .cut:
            return "scissors"
        case .copy:
            return "doc.on.doc"
        case .paste:
            return "doc.on.clipboard"
        case .clipboard:
            return "tray.full"
        case .redo:
            return "arrow.uturn.forward"
        case .moveLeft:
            return "arrow.left"
        case .moveRight:
            return "arrow.right"
        case .moveUp:
            return "arrow.up"
        case .moveDown:
            return "arrow.down"
        case .nextKeyboard:
            return "globe"
        default:
            return nil
        }
    }

    @ViewBuilder
    private func editorTokenGlyph(
        for action: KeyboardSpecialKeyAction,
        color: Color,
        compact: Bool
    ) -> some View {
        if action == .menu {
            PreviewToolbarMenuMorphIcon(
                isExpanded: false,
                color: color,
                lineWidth: compact ? 1.8 : 2
            )
            .frame(width: compact ? 14 : 16, height: compact ? 14 : 16)
        } else if let systemImage = editorTokenIconName(for: action) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private func editorTokenChip(
        _ token: String,
        fill: Color,
        border: Color,
        textColor: Color,
        iconColor: Color,
        height: CGFloat,
        horizontalPadding: CGFloat,
        cornerRadius: CGFloat,
        compact: Bool = false
    ) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            if let action = KeyboardSpecialKeyAction.resolved(from: token) {
                editorTokenGlyph(for: action, color: iconColor, compact: compact)

                Text(tokenLabel(token))
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            } else {
                Text(tokenLabel(token))
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(settings.appTheme.usesDarkChrome ? 0.05 : 0.08),
                            Color.clear,
                            Color.black.opacity(settings.appTheme.usesDarkChrome ? 0.08 : 0.03),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(border, lineWidth: compact && settings.highContrastKeys ? 1.4 : 1)
        )
    }

    @ViewBuilder
    private func selectedKeyValueChip(_ token: String) -> some View {
        if token.isEmpty {
            previewChip("Empty")
        } else {
            editorTokenChip(
                token,
                fill: previewTileFill,
                border: previewTileBorder,
                textColor: previewTextColor,
                iconColor: previewIconColor,
                height: 34,
                horizontalPadding: 12,
                cornerRadius: previewTileCornerRadius,
                compact: true
            )
        }
    }

    private var selectedKeyDisplayBinding: Binding<String> {
        Binding(
            get: {
                let value = selectedKeyBinding.wrappedValue
                return shouldHideCustomFieldValue(for: value) ? "" : value
            },
            set: { newValue in
                setSelectedKeyValueWithModeChangeWarning(newValue)
            }
        )
    }

    private func selectedKeyFieldPlaceholder(for value: String) -> String {
        if shouldHideCustomFieldValue(for: value) {
            return "Replace \(tokenLabel(value)) with custom text"
        }

        return "Type any character, shortcut, or custom text"
    }

    private var editablePrimaryLegendBoxWidth: CGFloat {
        settings.appTheme.usesDarkChrome ? 22 : 20
    }

    private var editableHoldLegendBoxWidth: CGFloat {
        16
    }

    private func hardwareLegendAlignment(for row: KeyboardRowKind, slotIndex: Int) -> Alignment {
        switch row.tapVariant {
        case .letterTop:
            return slotIndex <= 4 ? .bottomTrailing : .bottomLeading
        case .letterMiddle:
            return slotIndex <= 4 ? .bottomTrailing : .bottomLeading
        case .letterBottom:
            return slotIndex <= 3 ? .bottomTrailing : .bottomLeading
        default:
            return .bottomTrailing
        }
    }

    private func hardwarePrimaryAlignment(for row: KeyboardRowKind, slotIndex: Int) -> Alignment {
        switch row.tapVariant {
        case .letterTop:
            return slotIndex <= 4 ? .topTrailing : .topLeading
        case .letterMiddle:
            return slotIndex <= 4 ? .topTrailing : .topLeading
        case .letterBottom:
            return slotIndex <= 3 ? .topTrailing : .topLeading
        default:
            return .center
        }
    }

    private func editablePrimaryLegendHorizontalOffset(for row: KeyboardRowKind, slotIndex: Int) -> CGFloat {
        switch settings.appTheme {
        case .dark:
            return isMirroredEditablePrimaryPosition(for: row, slotIndex: slotIndex) ? -2 : 0
        case .classic, .chameleon, .custom:
            if isLeadingEditablePrimaryPosition(for: row, slotIndex: slotIndex) {
                return 2
            }
            return isMirroredEditablePrimaryPosition(for: row, slotIndex: slotIndex) ? -2 : 0
        }
    }

    private func isLeadingEditablePrimaryPosition(for row: KeyboardRowKind, slotIndex: Int) -> Bool {
        switch row.tapVariant {
        case .letterTop, .letterMiddle:
            return slotIndex <= 4
        case .letterBottom:
            return slotIndex <= 3
        default:
            return false
        }
    }

    private func isMirroredEditablePrimaryPosition(for row: KeyboardRowKind, slotIndex: Int) -> Bool {
        switch row.tapVariant {
        case .letterTop, .letterMiddle:
            return slotIndex > 4
        case .letterBottom:
            return slotIndex > 3
        default:
            return false
        }
    }

    private func keyBlockChip(_ token: String) -> some View {
        let isSelectedValue = selectedKeyBinding.wrappedValue == token

        return canvasKeyDragSource(payload: token) {
            Button(action: {
                setSelectedKeyValueWithModeChangeWarning(token)
            }) {
                editorTokenChip(
                    token,
                    fill: isSelectedValue ? selectedAccentFill : buttonBackgroundFill,
                    border: isSelectedValue ? selectedAccentBorderColor : previewTileBorder,
                    textColor: isSelectedValue ? .white : previewTextColor,
                    iconColor: isSelectedValue ? .white : previewIconColor,
                    height: 30,
                    horizontalPadding: 8,
                    cornerRadius: 8,
                    compact: true
                )
                .animation(liveEditorSpring, value: isSelectedValue)
            }
            .buttonStyle(StaticPressButtonStyle())
        }
    }

    private var liveEditorSpring: Animation {
        .interactiveSpring(
            response: settings.appTheme.usesDarkChrome ? 0.24 : 0.28,
            dampingFraction: settings.appTheme.usesDarkChrome ? 0.86 : 0.82,
            blendDuration: 0.12
        )
    }

    private var layerDropletSpring: Animation {
        .spring(response: 0.62, dampingFraction: 0.80, blendDuration: 0.30)
    }

    private var liveEditorShelfTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity
                .combined(with: .scale(scale: 0.99, anchor: .top))
        )
    }

    private var liveEditorSelectedKeyScale: CGFloat {
        settings.appTheme.usesDarkChrome ? 1.012 : 1.02
    }

    private var liveEditorSelectedKeyFill: Color {
        selectedAccentFill.opacity(settings.appTheme.usesDarkChrome ? 0.26 : 0.20)
    }

    private var liveEditorSelectedKeyShadowColor: Color {
        selectedAccentBorderColor.opacity(settings.appTheme.usesDarkChrome ? 0.26 : 0.18)
    }

    private func isSelectedEditorKey(_ row: KeyboardRowKind, slotIndex: Int) -> Bool {
        selectedEditableRow == row &&
            safeSelectedSlotIndex == clampedSlotIndex(slotIndex, for: row)
    }

    private var keyboardEditorExpandedRowSpacing: CGFloat {
        settings.appTheme.usesDarkChrome ? 0 : 5
    }

    private var keyboardEditorBottomStripSpacing: CGFloat {
        settings.appTheme.usesDarkChrome ? 0 : 4
    }

    private var keyboardEditorToolbarHeight: CGFloat {
        CGFloat(KeyboardLayoutBounds.clampedToolbarHeight(settings.toolbarHeight))
    }

    private var keyboardEditorSurfaceHeight: CGFloat {
        return keyboardEditorBottomStripHeight
            + keyboardEditorExpandedRowsRevealHeight
            + (keyboardEditorExpandedRowsRevealHeight > 0 ? keyboardEditorBottomStripSpacing : 0)
    }

    private var keyboardEditorExpandedRowsLift: CGFloat {
        guard keyboardEditorExpandedRowsRevealHeight > 0 else { return 0 }
        return keyboardEditorBottomStripHeight + keyboardEditorBottomStripSpacing
    }

    private var keyboardEditorExpandedRowsRevealHeight: CGFloat {
        guard isKeyboardEditorExpanded else { return 0 }
        return keyboardEditorExpandedRowsContentHeight
    }

    private var keyboardEditorExpandedRowsContentHeight: CGFloat {
        let expandedKeyHeight = CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))
        let totalExpandedRows = selectedCustomLayerID != nil
            ? selectedCustomLayerPrimaryRows.count
            : expandedRows(for: selectedExpandedLayer).count
        guard totalExpandedRows > 0 else { return 0 }

        return (expandedKeyHeight * CGFloat(totalExpandedRows))
            + (keyboardEditorExpandedRowSpacing * CGFloat(max(totalExpandedRows - 1, 0)))
    }

    private var keyboardEditorUtilityRevealHeight: CGFloat {
        guard isKeyboardEditorExpanded else { return 0 }
        return keyboardEditorToolbarHeight
    }

    private var keyboardEditorBottomStripHeight: CGFloat {
        isKeyboardEditorExpanded ? keyboardEditorUtilityRevealHeight : keyboardEditorToolbarHeight
    }

    @ViewBuilder
    private func canvasKeyDragSource<Content: View>(
        payload: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let base = content()

        if let payload, !payload.isEmpty {
            base.onDrag {
                NSItemProvider(object: payload as NSString)
            }
        } else {
            base
        }
    }

    private func previewChip(_ text: String) -> some View {
        Text(text)
            .font(
                .system(
                    size: settings.appTheme.usesDarkChrome ? 15 : 13,
                    weight: settings.appTheme.usesDarkChrome ? .regular : .medium
                )
            )
            .foregroundColor(previewTextColor)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                    .fill(previewTileFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                    .stroke(previewTileBorder, lineWidth: settings.highContrastKeys ? 1.4 : 1)
            )
    }

    private func previewDisplayText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "·" }
        return tokenLabel(trimmed)
    }

    @ViewBuilder
    private func previewValueKey(_ value: String, height: CGFloat) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let visual = utilityTokenVisual(for: trimmed) {
            previewKey(
                text: visual.text ?? (trimmed.isEmpty ? "·" : nil),
                icon: visual.icon,
                label: visual.label,
                height: height
            )
        } else {
            previewKey(
                text: trimmed.isEmpty ? "·" : tokenLabel(trimmed),
                height: height
            )
        }
    }

    private func previewKey(
        text: String? = nil,
        icon: String? = nil,
        label: String? = nil,
        height: CGFloat
    ) -> some View {
        let isDarkTheme = settings.appTheme.usesDarkChrome
        let isToolbarKey = height <= CGFloat(settings.toolbarHeight) + 1
        let textColor = isDarkTheme && isToolbarKey ? Color(red: 0.72, green: 0.72, blue: 0.73) : previewTextColor
        let iconColor = isDarkTheme && isToolbarKey ? Color(red: 0.66, green: 0.66, blue: 0.67) : previewIconColor
        let textSize: CGFloat = {
            if !isDarkTheme {
                return settings.largeLegends ? 22 : 18
            }
            return isToolbarKey ? 18 : (settings.largeLegends ? 30 : 27)
        }()
        let textWeight: Font.Weight = isDarkTheme ? (isToolbarKey ? .regular : .light) : .regular
        let iconSize: CGFloat = {
            if !isDarkTheme {
                return settings.largeLegends ? 18 : 16
            }
            return isToolbarKey ? 18 : 16
        }()
        let captionTextSize: CGFloat = {
            if !isToolbarKey {
                return isDarkTheme ? 12 : 11
            }

            switch settings.appTheme {
            case .classic, .chameleon, .custom:
                return settings.largeLegends ? 10 : 9
            case .dark:
                return settings.largeLegends ? 9 : 8
            }
        }()
        let captionIconSize = max(iconSize - 4, 11)

        let tileLabel = Group {
            if let icon, let label {
                VStack(spacing: isToolbarKey ? 1 : 2) {
                    Image(systemName: icon)
                        .font(.system(size: captionIconSize, weight: .regular))
                        .foregroundColor(iconColor)

                    Text(label)
                        .font(.system(size: captionTextSize, weight: .medium))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, isToolbarKey ? 3 : 4)
            } else if let text {
                Text(text)
                    .font(.system(size: textSize, weight: textWeight))
                    .foregroundColor(textColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            } else if let label {
                Text(label)
                    .font(.system(size: captionTextSize, weight: .medium))
                    .foregroundColor(textColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundColor(iconColor)
            }
        }

        return ZStack {
            RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                .fill(previewTileFill)
            RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: settings.appTheme == .classic
                            ? [
                                Color.white.opacity(settings.highContrastKeys ? 0.08 : 0.05),
                                Color.clear,
                                Color.black.opacity(0.10),
                            ]
                            : [Color.clear, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                .stroke(previewTileBorder, lineWidth: settings.highContrastKeys ? 1.4 : 1)
            tileLabel
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func previewUtilityKey(
        text: String? = nil,
        icon: String? = nil,
        label: String? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil
    ) -> some View {
        previewKey(
            text: text,
            icon: icon,
            label: label,
            height: height ?? CGFloat(settings.expandedKeyHeight)
        )
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }

    private var previewToolbarMenuGlyphSize: CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 16
        case .dark:
            return settings.showControlLabels ? 14 : 18
        }
    }

    private var toolbarExpansionKey: some View {
        toolbarRowActionTile(
            icon: nil,
            isExpandedGlyph: isKeyboardEditorExpanded,
            highlightTone: isKeyboardEditorExpanded ? .accent : .orange
        ) {
            toggleKeyboardEditorExpansion()
        }
    }

    private enum ToolbarRowActionHighlightTone {
        case neutral
        case orange
        case accent
    }

    @ViewBuilder
    private func toolbarRowActionTile(
        icon: String? = nil,
        isExpandedGlyph: Bool = false,
        highlightTone: ToolbarRowActionHighlightTone = .neutral,
        action: (() -> Void)? = nil
    ) -> some View {
        let toolbarHeight = CGFloat(KeyboardLayoutBounds.clampedToolbarHeight(settings.toolbarHeight))
        let colors = toolbarRowActionColors(for: highlightTone)

        let tile = ZStack {
            RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
                .fill(colors.fill)
            RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(colors.foreground)
            } else {
                PreviewToolbarMenuMorphIcon(
                    isExpanded: isExpandedGlyph,
                    color: colors.foreground,
                    lineWidth: 2
                )
                .frame(width: previewToolbarMenuGlyphSize, height: previewToolbarMenuGlyphSize)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: toolbarHeight)

        if let action {
            tile
                .contentShape(RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous))
                .onTapGesture(perform: action)
        } else {
            tile
        }
    }

    private func toolbarRowActionColors(for tone: ToolbarRowActionHighlightTone) -> (fill: Color, border: Color, foreground: Color) {
        switch tone {
        case .neutral:
            return (buttonBackgroundFill, Color(red: 0.24, green: 0.24, blue: 0.26), previewIconColor)
        case .orange:
            return (mainRowSelectionFill, mainRowSelectionBorder, .white)
        case .accent:
            return (selectedAccentFill, selectedAccentBorderColor, .white)
        }
    }

    private func previewToolbarMenuTile(isExpanded: Bool) -> some View {
        let height = CGFloat(settings.toolbarHeight)

        return ZStack {
            RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                .fill(previewTileFill)
            RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                .stroke(previewTileBorder, lineWidth: settings.highContrastKeys ? 1.4 : 1)
            PreviewToolbarMenuMorphIcon(
                isExpanded: isExpanded,
                color: previewIconColor,
                lineWidth: 2
            )
            .frame(width: previewToolbarMenuGlyphSize, height: previewToolbarMenuGlyphSize)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func editorActionKey(
        text: String? = nil,
        icon: String? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if width != nil || text == "space" || text == "return" {
                    previewUtilityKey(text: text, icon: icon, width: width, height: height)
                } else {
                    previewKey(
                        text: text,
                        icon: icon,
                        height: height ?? CGFloat(settings.toolbarHeight)
                    )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: previewTileCornerRadius, style: .continuous)
                    .stroke(isActive ? tabAccentColor : Color.clear, lineWidth: isActive ? 1.6 : 0)
            )
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private func setupRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(accentFill)
                )
                .overlay(
                    Circle()
                        .stroke(tabAccentColor, lineWidth: 1)
                )

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(subtleTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup step \(number). \(text)")
    }

    private func accessStatusRow(title: String, value: String, detail: String) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                rowTitle(
                    title,
                    detail: detail,
                    id: disclosureID("status", "\(title)|\(detail)")
                )

                Spacer(minLength: 12)

            }
        }
    }

    private func disclosureID(_ prefix: String, _ value: String) -> String {
        "\(prefix)::\(value)"
    }

    private func toggleInfoDisclosure(_ id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedInfoIDs.contains(id) {
                expandedInfoIDs.remove(id)
            } else {
                expandedInfoIDs.insert(id)
            }
        }
    }

    private func sectionCardHeader(title: String, detail: String?, detailID: String?) -> AnyView {
        if let detail, !detail.isEmpty {
            return AnyView(
                infoDisclosureHeader(
                    title: title,
                    detail: detail,
                    id: detailID ?? disclosureID("section", "\(title)|\(detail)"),
                    titleSize: 18,
                    titleWeight: .semibold,
                    detailSize: 13
                )
            )
        }

        return AnyView(
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        )
    }

    private func infoDisclosureHeader(
        title: String,
        detail: String,
        id: String,
        titleSize: CGFloat,
        titleWeight: Font.Weight,
        detailSize: CGFloat,
        titleColor: Color = .white,
        detailColor: Color? = nil,
        iconColor: Color? = nil
    ) -> InfoDisclosureHeaderView {
        let isExpanded = expandedInfoIDs.contains(id)
        let resolvedDetailColor = detailColor ?? subtleTextColor
        let resolvedIconColor = iconColor ?? tabAccentColor

        return InfoDisclosureHeaderView(
            title: title,
            detail: detail,
            isExpanded: isExpanded,
            titleSize: titleSize,
            titleWeight: titleWeight,
            detailSize: detailSize,
            titleColor: titleColor,
            detailColor: resolvedDetailColor,
            iconColor: resolvedIconColor,
            onToggle: {
                toggleInfoDisclosure(id)
            }
        )
    }

    private func featureBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tabAccentColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(subtleTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func presetCopy(for preset: KeyboardLayoutPreset) -> String {
        switch preset {
        case .compact:
            return "Compact daily typing. Balanced symbols."
        case .coding:
            return "Code and shell-heavy editing. Symbols forward."
        case .writing:
            return "Drafting and punctuation-heavy writing. Flow close."
        case .web:
            return "URLs, handles, and search entry. Web tokens close."
        case .custom:
            return "Your edited layout."
        }
    }

    private var expandedLayerBinding: Binding<ExpandedKeymapLayer> {
        Binding(
            get: { selectedExpandedLayer },
            set: { newLayer in
                selectedExpandedLayer = newLayer
                let selection = HWKKeymapEditorNavigation.rowAfterChangingSurface(
                    to: newLayer == .letters ? .letters : .symbols,
                    currentRow: selectedEditableRow,
                    currentMode: selectedEditActionMode.navigationMode
                )
                let resolvedMode = KeyboardEditActionMode(selection.mode)
                if selectedEditActionMode != resolvedMode {
                    selectedEditActionMode = resolvedMode
                }
                selectedEditableRow = selection.row
                clampSelectedSlotIndex()
            }
        )
    }

    private var layoutLocaleBinding: Binding<KeyboardLayoutLocale> {
        Binding(
            get: { settings.layoutLocale },
            set: { settings.applyLayoutLocale($0) }
        )
    }

    private var keyboardEditorSurface: KeyboardEditorSurface {
        guard isKeyboardEditorExpanded else { return .mainRow }
        switch selectedExpandedLayer {
        case .letters:
            return .letters
        case .symbols1:
            return .symbols1
        case .symbols2:
            return .symbols2
        }
    }

    private var keyboardEditorSurfaceBinding: Binding<KeyboardEditorSurface> {
        Binding(
            get: { keyboardEditorSurface },
            set: { setKeyboardEditorSurface($0) }
        )
    }

    private var keyboardEditorLayerOptions: [KeyboardEditorLayerOption] {
        [
            KeyboardEditorLayerOption(
                id: KeyboardEditorLayerOption.mainRowID,
                title: "Main Row",
                systemImage: "keyboard",
                customLayerID: nil
            ),
            KeyboardEditorLayerOption(
                id: KeyboardEditorLayerOption.lettersID,
                title: "ABC",
                systemImage: "textformat",
                customLayerID: nil
            ),
            KeyboardEditorLayerOption(
                id: KeyboardEditorLayerOption.symbols1ID,
                title: "SYM1",
                systemImage: "number",
                customLayerID: nil
            ),
            KeyboardEditorLayerOption(
                id: KeyboardEditorLayerOption.symbols2ID,
                title: "SYM2",
                systemImage: "number.square",
                customLayerID: nil
            ),
        ]
    }

    private var keyboardEditorLayerSelectionID: String {
        if let selectedCustomLayerID {
            return KeyboardEditorLayerOption.customIDPrefix + selectedCustomLayerID.uuidString
        }

        switch keyboardEditorSurface {
        case .mainRow:
            return KeyboardEditorLayerOption.mainRowID
        case .symbols1:
            return KeyboardEditorLayerOption.symbols1ID
        case .symbols2:
            return KeyboardEditorLayerOption.symbols2ID
        case .letters:
            return KeyboardEditorLayerOption.lettersID
        }
    }

    private var keyboardEditorLayerTitle: String {
        if let selectedCustomLayerID,
           let layer = settings.customKeymapLayers.first(where: { $0.id == selectedCustomLayerID }) {
            return layer.title
        }
        return keyboardEditorSurface.title
    }

    private var keyboardEditorLayerSelectionBinding: Binding<String> {
        Binding(
            get: { keyboardEditorLayerSelectionID },
            set: { setKeyboardEditorLayerSelection($0) }
        )
    }

    private var additionalLayerAddID: String { "additional:add" }

    private var liveEditorActionSelector: some View {
        Picker("Key Action", selection: $selectedEditActionMode) {
            ForEach(KeyboardEditActionMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Key Action")
    }

    private var liveEditorLayerSelector: some View {
        HStack(spacing: 0) {
            ForEach(keyboardEditorLayerOptions) { option in
                let isSelected = keyboardEditorLayerSelectionID == option.id
                Button {
                    withAnimation(layerDropletSpring) {
                        setKeyboardEditorLayerSelection(option.id)
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(height: 30)
                        .anchorPreference(
                            key: HWCSelectedLayerAnchorPreferenceKey.self,
                            value: .bounds
                        ) { anchor in
                            [option.id: anchor]
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor Layer")
    }

    @ViewBuilder
    nonisolated private static func liveEditorLayerSelectionHighlight(
        flow: CGFloat,
        usesGlass: Bool
    ) -> some View {
        if #available(iOS 26.0, *), usesGlass {
            Color.clear
                .glassEffect(.clear.tint(Color.white.opacity(0.12)).interactive(), in: HWCWordDropletShape(flow: flow))
        } else {
            HWCWordDropletShape(flow: flow).fill(Color.white.opacity(0.30))
        }
    }

    @ViewBuilder
    private var liveEditorPersistentWaterDroplet: some View {
        let usesGlass = !accessibilityReduceTransparency
        if #available(iOS 17.0, *) {
            Color.clear
                .keyframeAnimator(
                    initialValue: HWCWaterMotionValues(),
                    trigger: keyboardEditorLayerSelectionID
                ) { _, motion in
                    Self.liveEditorLayerSelectionHighlight(flow: motion.flow, usesGlass: usesGlass)
                        .scaleEffect(x: motion.stretchX, y: motion.squashY)
                        .rotationEffect(.degrees(motion.tilt))
                        .offset(x: motion.lagX, y: motion.liftY)
                } keyframes: { _ in
                    KeyframeTrack(\.stretchX) {
                        CubicKeyframe(0.80, duration: 0.18)
                        CubicKeyframe(0.94, duration: 0.16)
                        SpringKeyframe(1.0, duration: 0.30, spring: .smooth)
                    }
                    KeyframeTrack(\.squashY) {
                        CubicKeyframe(0.76, duration: 0.18)
                        CubicKeyframe(0.92, duration: 0.16)
                        SpringKeyframe(1.0, duration: 0.30, spring: .smooth)
                    }
                    KeyframeTrack(\.tilt) {
                        CubicKeyframe(2.5, duration: 0.14)
                        CubicKeyframe(-0.8, duration: 0.14)
                        SpringKeyframe(0.0, duration: 0.26, spring: .smooth)
                    }
                    KeyframeTrack(\.lagX) {
                        CubicKeyframe(-3.0, duration: 0.16)
                        CubicKeyframe(1.0, duration: 0.14)
                        SpringKeyframe(0.0, duration: 0.26, spring: .smooth)
                    }
                    KeyframeTrack(\.liftY) {
                        CubicKeyframe(-3.5, duration: 0.16)
                        CubicKeyframe(1.0, duration: 0.14)
                        SpringKeyframe(0.0, duration: 0.28, spring: .smooth)
                    }
                    KeyframeTrack(\.flow) {
                        CubicKeyframe(0.42, duration: 0.16)
                        CubicKeyframe(-0.12, duration: 0.16)
                        CubicKeyframe(0.12, duration: 0.14)
                        CubicKeyframe(-0.04, duration: 0.12)
                        SpringKeyframe(0.0, duration: 0.30, spring: .smooth)
                    }
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        } else {
            HWCWordDropletShape(flow: 0).fill(Color.white.opacity(0.30))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func liveEditorOsmoticTrail(source: CGPoint, target: CGPoint) -> some View {
        let usesGlass = !accessibilityReduceTransparency
        return Color.clear
            .keyframeAnimator(
                initialValue: HWCWaterOsmosisValues(),
                trigger: keyboardEditorLayerSelectionID
            ) { _, osmosis in
                ZStack {
                    Self.osmoticSatellite(size: 9 * osmosis.cohesion, usesGlass: usesGlass)
                        .position(
                            Self.osmoticPoint(
                                from: source,
                                to: target,
                                progress: min(osmosis.progress, 1),
                                arcHeight: -4,
                                normalOffset: 2
                            )
                        )
                    Self.osmoticSatellite(size: 6 * osmosis.cohesion, usesGlass: usesGlass)
                        .position(
                            Self.osmoticPoint(
                                from: source,
                                to: target,
                                progress: min(max(osmosis.progress - 0.10, 0) * 1.11, 1),
                                arcHeight: -4,
                                normalOffset: -2
                            )
                        )
                }
                .opacity(osmosis.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.progress) {
                    CubicKeyframe(1.0, duration: 0.58)
                }
                KeyframeTrack(\.cohesion) {
                    CubicKeyframe(0.86, duration: 0.16)
                    CubicKeyframe(0.54, duration: 0.18)
                    SpringKeyframe(0.08, duration: 0.18, spring: .smooth)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1.0, duration: 0.24)
                    SpringKeyframe(0.0, duration: 0.18, spring: .smooth)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    nonisolated private static func osmoticSatellite(
        size: CGFloat,
        usesGlass: Bool
    ) -> some View {
        if #available(iOS 26.0, *), usesGlass {
            Color.clear
                .frame(width: max(size, 1), height: max(size, 1))
                .glassEffect(.clear.tint(Color.white.opacity(0.04)), in: Circle())
        } else {
            Circle()
                .fill(Color.white.opacity(0.24))
                .frame(width: max(size, 1), height: max(size, 1))
        }
    }

    nonisolated private static func osmoticPoint(
        from source: CGPoint,
        to target: CGPoint,
        progress: CGFloat,
        arcHeight: CGFloat,
        normalOffset: CGFloat
    ) -> CGPoint {
        let easedProgress = progress * progress * (3 - 2 * progress)
        let dx = target.x - source.x
        let dy = target.y - source.y
        let distance = max(hypot(dx, dy), 1)
        let normalX = -dy / distance
        let normalY = dx / distance
        let waterOffset = sin(.pi * easedProgress) * normalOffset
        return CGPoint(
            x: source.x + dx * easedProgress + normalX * waterOffset,
            y: source.y + dy * easedProgress + sin(.pi * easedProgress) * arcHeight + normalY * waterOffset
        )
    }

    private func dropletEdgePoint(
        from center: CGPoint,
        toward other: CGPoint,
        size: CGSize
    ) -> CGPoint {
        let dx = other.x - center.x
        let dy = other.y - center.y
        let radiusX = max(size.width * 0.5, 1)
        let radiusY = max(size.height * 0.5, 1)
        let denominator = sqrt((dx * dx) / (radiusX * radiusX) + (dy * dy) / (radiusY * radiusY))
        guard denominator > 0.001 else { return center }
        return CGPoint(x: center.x + dx / denominator, y: center.y + dy / denominator)
    }

    private var unifiedKeyboardEditorLayerSwitcher: some View {
        Group {
            if #available(iOS 26.0, *), !accessibilityReduceTransparency {
                GlassEffectContainer(spacing: 18) {
                    liveEditorLayerSelectorContent
                }
            } else {
                liveEditorLayerSelectorContent
            }
        }
        .backgroundPreferenceValue(HWCSelectedLayerAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let targetAnchor = anchors[keyboardEditorLayerSelectionID] {
                    let rect = proxy[targetAnchor]
                    let bubbleSize = CGSize(width: rect.width + 18, height: 32)
                    let rawTargetCenter = layerDropletFingerLocation
                        ?? CGPoint(x: rect.midX, y: rect.midY)
                    let targetCenter = HWCKeymapEditorLayerScrubPolicy.clampedBubbleCenter(
                        rawTargetCenter,
                        containerSize: proxy.size,
                        bubbleSize: bubbleSize
                    )
                    ZStack {
                        if let previousID = previousKeyboardEditorLayerSelectionID,
                           let sourceAnchor = anchors[previousID] {
                            let sourceRect = proxy[sourceAnchor]
                            let sourceCenter = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
                            let travelDistance = hypot(
                                rect.midX - sourceRect.midX,
                                rect.midY - sourceRect.midY
                            )
                            if travelDistance > 90 {
                                liveEditorOsmoticTrail(
                                    source: dropletEdgePoint(
                                        from: sourceCenter,
                                        toward: targetCenter,
                                        size: CGSize(width: sourceRect.width + 18, height: 32)
                                    ),
                                    target: dropletEdgePoint(
                                        from: targetCenter,
                                        toward: sourceCenter,
                                        size: bubbleSize
                                    )
                                )
                            }
                        }

                        liveEditorPersistentWaterDroplet
                            .frame(width: bubbleSize.width, height: bubbleSize.height)
                            .position(x: targetCenter.x, y: targetCenter.y)
                    }
                }
            }
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .animation(layerDropletSpring, value: keyboardEditorLayerSelectionID)
    }

    private var liveEditorLayerSelectorContent: some View {
        VStack(spacing: 0) {
            ZStack {
                liveEditorLayerSelector
                    .frame(height: 30)

                keyboardEditorLayerHoldOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)

            Divider().overlay(Color.white.opacity(0.10))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4),
                spacing: 0
            ) {
                Group {
                    if draggedCustomLayerID != nil {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                Color.red.opacity(
                                    additionalLayerDragLocation.map(additionalLayerTrashFrame.contains) == true
                                        ? 0.22
                                        : 0.08
                                )
                            )
                            .accessibilityLabel("Delete Additional Layer")
                            .accessibilityIdentifier("additional-layer-trash-target")
                    } else {
                        Button {
                            switch additionalLayerPurchasePrompt.tap(
                                requiresPurchase: isAdditionalLayersLocked,
                                isBusy: additionalLayersStore.isPurchasing || additionalLayersStore.isRestoring
                            ) {
                            case .showPrice:
                                if additionalLayersStore.priceLabel.isEmpty {
                                    additionalLayersStore.refreshProduct()
                                }
                            case .purchase:
                                if additionalLayersStore.priceLabel.isEmpty {
                                    additionalLayersStore.refreshProduct()
                                } else {
                                    additionalLayersStore.purchaseUnlock()
                                }
                            case .add:
                                withAnimation(layerDropletSpring) { addCustomLayer() }
                            case .none:
                                break
                            }
                        } label: {
                            Group {
                                if isAdditionalLayersLocked && additionalLayerPurchasePrompt.isPriceVisible {
                                    Text(additionalLayersStore.isPurchasing ? "Purchasing…" : additionalLayerPurchasePrice)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                } else {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                        }
                        .id(additionalLayerAddID)
                        .buttonStyle(.plain)
                        .disabled(
                            additionalLayersStore.isPurchasing || additionalLayersStore.isRestoring ||
                            (additionalLayerPurchasePrompt.isPriceVisible && additionalLayersStore.isLoadingProduct)
                        )
                        .accessibilityIdentifier("keymap.additional.add")
                        .accessibilityLabel(
                            isAdditionalLayersLocked && additionalLayerPurchasePrompt.isPriceVisible
                                ? (additionalLayersStore.priceLabel.isEmpty
                                    ? "Load Additional Layer price from App Store"
                                    : "Buy Additional Layer for \(additionalLayersStore.priceLabel)")
                                : "Add Additional Layer"
                        )
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HWCAdditionalLayerTrashFramePreferenceKey.self,
                            value: proxy.frame(in: .named("liveEditorAdditionalLayerDrag"))
                        )
                    }
                }

                ForEach(accessibleCustomKeymapLayers) { layer in
                    let option = KeyboardEditorLayerOption(
                        id: KeyboardEditorLayerOption.customIDPrefix + layer.id.uuidString,
                        title: layer.title,
                        systemImage: layer.iconSystemName,
                        customLayerID: layer.id
                    )
                    let isSelected = selectedCustomLayerID == layer.id
                    Button {
                        withAnimation(layerDropletSpring) {
                            setKeyboardEditorLayerSelection(option.id)
                        }
                    } label: {
                    Text(layer.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(height: 30)
                            .anchorPreference(
                                key: HWCSelectedLayerAnchorPreferenceKey.self,
                                value: .bounds
                            ) { anchor in
                                [option.id: anchor]
                            }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        additionalLayerHoldDragGesture(for: option)
                    )
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .background { additionalLayerScrubObserver }

            if let layer = accessibleCustomKeymapLayers.first(where: { $0.id == selectedCustomLayerID }) {
                HStack {
                    Spacer()
                    Button {
                        presentCustomLayerHoldPrompt(KeyboardEditorLayerOption(
                            id: KeyboardEditorLayerOption.customIDPrefix + layer.id.uuidString,
                            title: layer.title,
                            systemImage: layer.iconSystemName,
                            customLayerID: layer.id
                        ))
                    } label: {
                        Label("Edit Layer", systemImage: "square.and.pencil")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("keymap.additional.edit")
                    .accessibilityLabel("Edit \(layer.title)")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            if additionalLayerPurchasePrompt.isPriceVisible,
               let error = additionalLayersStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .coordinateSpace(name: "liveEditorAdditionalLayerDrag")
        .onPreferenceChange(HWCAdditionalLayerTrashFramePreferenceKey.self) {
            additionalLayerTrashFrame = $0
        }
        .animation(layerDropletSpring, value: keyboardEditorLayerSelectionID)
    }

    private var selectedKeyBinding: Binding<String> {
        if let selectedCustomLayerKeySelection {
            let holdLayer = selectedEditActionMode == .hold
            return Binding(
                get: {
                    customLayerKeyValue(
                        selection: selectedCustomLayerKeySelection,
                        holdLayer: holdLayer
                    )
                },
                set: { newValue in
                    setCustomLayerKeyValue(
                        newValue,
                        selection: selectedCustomLayerKeySelection,
                        holdLayer: holdLayer
                    )
                }
            )
        }

        if let row = sym2LayoutRow(for: selectedEditableRow),
           row.keys.indices.contains(safeSlotIndex(for: selectedEditableRow)) {
            let key = row.keys[safeSlotIndex(for: selectedEditableRow)]
            let holdLayer = selectedEditActionMode == .hold
            return Binding(
                get: {
                    holdLayer
                        ? (key.holdChoices.isEmpty ? (key.hold ?? "") : key.holdChoices.joined(separator: " | "))
                        : key.tap
                },
                set: { newValue in
                    settings.updateKeymapTableKey(
                        rowID: row.id,
                        keyID: key.id,
                        value: newValue,
                        holdLayer: holdLayer
                    )
                }
            )
        }

        let safeSlot = safeSlotIndex(for: selectedEditableRow)
        return settings.keyBinding(for: selectedEditableRow, index: safeSlot)
    }

    private var selectedKeyGuardedBinding: Binding<String> {
        Binding(
            get: { selectedKeyBinding.wrappedValue },
            set: { setSelectedKeyValueWithModeChangeWarning($0) }
        )
    }

    private func customLayerKeyValue(
        selection: CustomLayerEditorKeySelection,
        holdLayer: Bool
    ) -> String {
        for row in settings.customKeymapLayerRows(id: selection.layerID) where row.id == selection.rowID {
            guard let key = row.keys.first(where: { $0.id == selection.keyID }) else { return "" }
            return holdLayer ? (key.hold ?? "") : key.tap
        }
        return ""
    }

    private func setCustomLayerKeyValue(
        _ value: String,
        selection: CustomLayerEditorKeySelection,
        holdLayer: Bool
    ) {
        settings.updateKeymapTableKey(
            rowID: selection.rowID,
            keyID: selection.keyID,
            value: value,
            holdLayer: holdLayer
        )
    }

    private func pasteClipboardValueIntoSelectedKey() {
        guard let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return
        }

        setSelectedKeyValueWithModeChangeWarning(value)
    }

    private var safeSelectedSlotIndex: Int {
        safeSlotIndex(for: selectedEditableRow)
    }

    private var activeKeyShelfSection: KeyBlockLibrarySection? {
        keyBlockSections.first(where: { $0.id == selectedKeyShelfSectionID }) ?? keyBlockSections.first
    }

    private var activeToolbarRow: KeyboardRowKind {
        editableRow(for: .toolbar)
    }

    private var activeExpandedTrailingUtilityRow: KeyboardRowKind {
        selectedExpandedLayer == .symbols1 ? .expandedTrailingUtility : .expandedLetterTrailingUtility
    }

    private var selectedCustomLayerRows: [KeyboardLayoutRow] {
        guard let selectedCustomLayerID else { return [] }
        return settings.customKeymapLayerRows(id: selectedCustomLayerID)
    }

    private var selectedCustomLayerSurface: KeyboardRowSurface? {
        guard let selectedCustomLayerID else { return nil }
        return settings.customKeymapLayers.first { $0.id == selectedCustomLayerID }?.surface
    }

    private var selectedCustomLayerPrimaryRows: [KeyboardLayoutRow] {
        selectedCustomLayerRows.filter { row in
            row.kind == .toolbar ||
            row.kind == .symbolTop ||
            row.kind == .symbolMiddle ||
            row.kind == .symbolBottom ||
            row.kind == .letterTop ||
            row.kind == .letterMiddle ||
            row.kind == .letterBottom
        }
    }

    private var selectedCustomLayerToolbarRow: KeyboardLayoutRow? {
        selectedCustomLayerRows.first { row in
            row.kind == .toolbar
        }
    }

    private var selectedCustomLayerUtilityRow: KeyboardLayoutRow? {
        selectedCustomLayerRows.first { row in
            row.kind == .symbolUtility || row.kind == .letterUtility
        }
    }

    private func editableRow(for baseRow: KeyboardRowKind) -> KeyboardRowKind {
        HWKKeymapEditorNavigation.rowAfterSelectingRenderedKey(
            baseRow,
            currentMode: selectedEditActionMode.navigationMode
        ).row
    }

    private var allIOSKeyShelfSections: [KeyBlockLibrarySection] {
        [
            KeyBlockLibrarySection(
                title: "All Keys",
                detail: "All iOS character, action, and layer tokens.",
                tokens: Self.cachedAllIOSKeyShelfTokens
            ),
            KeyBlockLibrarySection(
                title: "Letters",
                detail: "Lowercase and uppercase letters.",
                tokens: Self.cachedAllIOSLetterTokens
            ),
            KeyBlockLibrarySection(
                title: "Characters",
                detail: "Printable punctuation, brackets, marks, and web tokens.",
                tokens: Self.cachedAllIOSCharacterTokens
            ),
            KeyBlockLibrarySection(
                title: "Currency",
                detail: "Currency marks available from iOS symbol keyboards.",
                tokens: ["$", "¢", "€", "£", "¥", "₩", "₹", "₽", "₺", "₫", "₱", "฿"]
            ),
            KeyBlockLibrarySection(
                title: "Math",
                detail: "Operators and math symbols.",
                tokens: Self.cachedIOSMathTokens
            ),
            KeyBlockLibrarySection(
                title: "Fractions",
                detail: "Fractions, superscripts, and ordinals.",
                tokens: Self.cachedIOSFractionTokens
            ),
            KeyBlockLibrarySection(
                title: "Arrows",
                detail: "Directional arrows and cursor-style symbols.",
                tokens: Self.cachedIOSArrowTokens
            ),
            KeyBlockLibrarySection(
                title: "Shapes",
                detail: "Bullets, stars, checks, and geometric marks.",
                tokens: Self.cachedIOSShapeTokens
            ),
            KeyBlockLibrarySection(
                title: "Greek",
                detail: "Greek letters commonly exposed by iOS text input.",
                tokens: Self.cachedIOSGreekTokens
            ),
            KeyBlockLibrarySection(
                title: "System",
                detail: "Apple, command, option, and system glyphs.",
                tokens: Self.cachedIOSSystemTokens
            ),
            KeyBlockLibrarySection(
                title: "Scripts",
                detail: "Non-Latin writing systems exposed through Unicode input.",
                tokens: Self.cachedIOSScriptTokens
            ),
            KeyBlockLibrarySection(
                title: "Enclosed",
                detail: "Circled numbers, enclosed letters, and compact marks.",
                tokens: Self.cachedIOSEnclosedTokens
            ),
            KeyBlockLibrarySection(
                title: "Braille",
                detail: "Braille pattern cells.",
                tokens: Self.cachedIOSBrailleTokens
            ),
            KeyBlockLibrarySection(
                title: "Diacritics",
                detail: "Common accented Latin characters.",
                tokens: Self.cachedIOSDiacriticTokens
            ),
            KeyBlockLibrarySection(
                title: "Emoji",
                detail: "Common emoji text tokens.",
                tokens: Self.cachedIOSEmojiTokens
            ),
        ]
    }

    private static let cachedAllIOSKeyShelfTokens: [String] = uniqueKeyShelfTokens(
            KeyboardSpecialKeyAction.allCases.map(\.storageToken)
                + cachedAllIOSLetterTokens
                + cachedAllIOSCharacterTokens
                + cachedIOSMathTokens
                + cachedIOSFractionTokens
                + cachedIOSArrowTokens
                + cachedIOSShapeTokens
                + cachedIOSGreekTokens
                + cachedIOSSystemTokens
                + cachedIOSScriptTokens
                + cachedIOSEnclosedTokens
                + cachedIOSBrailleTokens
                + cachedIOSDiacriticTokens
                + cachedIOSEmojiTokens
    )

    private var allIOSKeyShelfTokens: [String] {
        Self.cachedAllIOSKeyShelfTokens
    }

    private static let cachedIOSSymbolRanges: [ClosedRange<Int>] = [
        0x00A0...0x00FF, // Latin-1 supplement
        0x2000...0x206F, // general punctuation
        0x20A0...0x20CF, // currency
        0x2100...0x214F, // letterlike
        0x2150...0x218F, // number forms
        0x2190...0x21FF, // arrows
        0x2200...0x22FF, // math operators
        0x2300...0x23FF, // technical symbols
        0x2400...0x243F, // control pictures
        0x2500...0x257F, // box drawing
        0x25A0...0x25FF, // geometric shapes
        0x2600...0x26FF, // miscellaneous symbols
        0x2700...0x27BF, // dingbats
        0x27C0...0x27EF, // math symbols-A
        0x27F0...0x27FF, // supplemental arrows-A
        0x2900...0x297F, // supplemental arrows-B
        0x2980...0x29FF, // math symbols-B
        0x2B00...0x2BFF, // miscellaneous symbols and arrows
    ]

    private var allIOSSymbolRanges: [ClosedRange<Int>] {
        Self.cachedIOSSymbolRanges
    }

    private var legacyAllIOSSymbolRanges: [ClosedRange<Int>] {
        [
            0x00A0...0x00FF, // Latin-1 supplement
            0x2000...0x206F, // general punctuation
            0x20A0...0x20CF, // currency
            0x2100...0x214F, // letterlike
            0x2150...0x218F, // number forms
            0x2190...0x21FF, // arrows
            0x2200...0x22FF, // math operators
            0x2300...0x23FF, // technical symbols
            0x2400...0x243F, // control pictures
            0x2500...0x257F, // box drawing
            0x25A0...0x25FF, // geometric shapes
            0x2600...0x26FF, // miscellaneous symbols
            0x2700...0x27BF, // dingbats
            0x27C0...0x27EF, // math symbols-A
            0x27F0...0x27FF, // supplemental arrows-A
            0x2900...0x297F, // supplemental arrows-B
            0x2980...0x29FF, // math symbols-B
            0x2B00...0x2BFF, // miscellaneous symbols and arrows
        ]
    }

    private static let cachedAllIOSLetterTokens: [String] =
        ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
         "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
         "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
         "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]

    private var allIOSLetterTokens: [String] {
        Self.cachedAllIOSLetterTokens
    }

    private static let cachedAllIOSCharacterTokens: [String] = uniqueKeyShelfTokens(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
         ".", ",", "!", "?", ":", ";", "\"", "'", "’", "‘", "“", "”",
         "-", "–", "—", "_", "/", "\\", "|", "@", "#", "&", "*", "•",
         "(", ")", "[", "]", "{", "}", "<", ">", "[]", "()", "{}", "<>",
         "$", "¢", "€", "£", "¥", "₩", "₹", "₽", "₺", "₫", "₱", "฿",
         "~", "`", "^", "§", "¶", "©", "®", "™", "…",
         ".com", ".net", ".org", ".edu", ".io", ".app"]
            + cachedIOSMathTokens
            + cachedIOSFractionTokens
            + cachedIOSArrowTokens
            + cachedIOSShapeTokens
            + cachedIOSSystemTokens
            + cachedIOSScriptTokens
            + cachedIOSEnclosedTokens
            + cachedIOSBrailleTokens
            + cachedIOSDiacriticTokens
            + unicodeScalarTokens(in: cachedIOSSymbolRanges))

    private var allIOSCharacterTokens: [String] {
        Self.cachedAllIOSCharacterTokens
    }

    private static let cachedIOSMathTokens: [String] =
        ["=", "+", "-", "−", "×", "÷", "±", "≈", "≠", "≤", "≥", "∞", "%", "‰", "√", "∑", "∏", "∆", "∫", "π", "°"]

    private var allIOSMathTokens: [String] {
        Self.cachedIOSMathTokens
    }

    private static let cachedIOSFractionTokens: [String] =
        ["½", "⅓", "⅔", "¼", "¾", "⅛", "⅜", "⅝", "⅞", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹", "⁰", "ª", "º"]

    private var allIOSFractionTokens: [String] {
        Self.cachedIOSFractionTokens
    }

    private static let cachedIOSArrowTokens: [String] =
        ["←", "↑", "→", "↓", "↔", "↕", "↖", "↗", "↘", "↙", "⇐", "⇒", "⇑", "⇓", "⇔", "⟵", "⟶", "⟷"]

    private var allIOSArrowTokens: [String] {
        Self.cachedIOSArrowTokens
    }

    private static let cachedIOSShapeTokens: [String] =
        ["•", "◦", "▪", "▫", "■", "□", "●", "○", "◆", "◇", "▲", "△", "▼", "▽", "★", "☆", "✓", "✔", "✕", "✖", "✚", "✦", "✧"]

    private var allIOSShapeTokens: [String] {
        Self.cachedIOSShapeTokens
    }

    private static let cachedIOSGreekTokens: [String] =
        ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "λ", "μ", "ν", "ξ", "π", "ρ", "σ", "τ", "φ", "χ", "ψ", "ω",
         "Α", "Β", "Γ", "Δ", "Ε", "Ζ", "Η", "Θ", "Λ", "Μ", "Ν", "Ξ", "Π", "Ρ", "Σ", "Τ", "Φ", "Χ", "Ψ", "Ω"]

    private var allIOSGreekTokens: [String] {
        Self.cachedIOSGreekTokens
    }

    private static let cachedIOSSystemTokens: [String] =
        ["⌘", "⌥", "⌃", "⇧", "⎋", "⌫", "⌦", "↩", "⏎", "⇥", "⇤", "␣", ""]

    private var allIOSSystemTokens: [String] {
        Self.cachedIOSSystemTokens
    }

    private static let cachedIOSScriptTokens: [String] = uniqueKeyShelfTokens([
            "Ж", "Й", "Ц", "Ш", "Щ", "Ю", "Я", "ж", "я",
            "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט", "י", "ש",
            "ا", "ب", "ت", "ث", "ج", "ح", "خ", "د", "ر", "ز", "س", "ش", "ع", "غ", "ف", "ق", "ك", "ل", "م", "ن", "ه", "و", "ي",
            "अ", "आ", "इ", "ई", "उ", "ऊ", "क", "ख", "ग", "च", "ज", "ट", "ड", "त", "द", "न", "प", "ब", "म", "य", "र", "ल", "व", "स", "ह",
            "ก", "ข", "ค", "ง", "จ", "ช", "ญ", "ด", "ต", "ท", "น", "บ", "ป", "ผ", "ฝ", "พ", "ฟ", "ม", "ย", "ร", "ล", "ว", "ส", "ห",
            "あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "さ", "し", "す", "せ", "そ", "ん",
            "ア", "イ", "ウ", "エ", "オ", "カ", "キ", "ク", "ケ", "コ", "サ", "シ", "ス", "セ", "ソ", "ン",
            "。", "、", "・", "々", "〆", "〇",
        ] + unicodeScalarTokens(in: cachedIOSScriptRanges))

    private var allIOSScriptTokens: [String] {
        Self.cachedIOSScriptTokens
    }

    private static let cachedIOSScriptRanges: [ClosedRange<Int>] = [
            0x0100...0x024F, // Latin extended
            0x0250...0x02AF, // IPA
            0x0400...0x052F, // Cyrillic
            0x0590...0x05FF, // Hebrew
            0x0600...0x06FF, // Arabic
            0x0900...0x097F, // Devanagari
            0x0E00...0x0E7F, // Thai
            0x3000...0x303F, // CJK symbols and punctuation
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
        ]

    private var allIOSScriptRanges: [ClosedRange<Int>] {
        Self.cachedIOSScriptRanges
    }

    private static let cachedIOSEnclosedTokens: [String] =
        uniqueKeyShelfTokens(["①"] + unicodeScalarTokens(in: [0x2460...0x24FF, 0x3200...0x32FF]))

    private var allIOSEnclosedTokens: [String] {
        Self.cachedIOSEnclosedTokens
    }

    private static let cachedIOSBrailleTokens: [String] =
        uniqueKeyShelfTokens(["⣿"] + unicodeScalarTokens(in: [0x2800...0x28FF]))

    private var allIOSBrailleTokens: [String] {
        Self.cachedIOSBrailleTokens
    }

    private static let cachedIOSDiacriticTokens: [String] =
        [
            "á", "à", "â", "ä", "ã", "å", "ā", "ă", "ą", "æ",
            "ç", "ć", "č", "ď", "ð", "é", "è", "ê", "ë", "ē", "ė", "ę",
            "í", "ì", "î", "ï", "ī", "ı", "ñ", "ń", "ó", "ò", "ô", "ö", "õ", "ø", "ō", "œ",
            "ř", "š", "ś", "ß", "ť", "ú", "ù", "û", "ü", "ū", "ý", "ÿ", "ž", "ź", "ż",
            "Á", "À", "Â", "Ä", "Ã", "Å", "Ā", "Æ", "Ç", "Č", "É", "È", "Ê", "Ë", "Ē",
            "Í", "Ì", "Î", "Ï", "Ī", "Ñ", "Ó", "Ò", "Ô", "Ö", "Õ", "Ø", "Ō", "Œ",
            "Ú", "Ù", "Û", "Ü", "Ū", "Ý", "Ÿ", "Ž",
        ]

    private var allIOSDiacriticTokens: [String] {
        Self.cachedIOSDiacriticTokens
    }

    private static let cachedIOSEmojiTokens: [String] = uniqueKeyShelfTokens([
            "😀", "😃", "😄", "😁", "😆", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😍", "🥰", "😘", "😎", "🤔", "😭",
            "👍", "👎", "👌", "✌️", "🤞", "🤟", "🤘", "👏", "🙌", "🙏", "💪",
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "💕", "💯",
            "🔥", "⭐", "✨", "✅", "❌", "⚠️", "🚀", "🏆", "🎉", "💡", "🧠", "💻", "📎", "📌", "🔒", "🔑",
            "☕", "🍕", "🍔", "🍎", "🌮", "🍩", "🌟", "🌙", "☀️", "🌈",
            "🏳️‍🌈", "🏳️‍⚧️", "👨‍👩‍👧‍👦", "👩‍💻", "👨‍💻", "🧑‍💻", "🧑‍🚀", "🧑‍⚕️",
            "👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿", "🙏🏻", "🙏🏼", "🙏🏽", "🙏🏾", "🙏🏿",
            "🇺🇸", "🇨🇦", "🇬🇧", "🇪🇺", "🇯🇵", "🇰🇷", "🇮🇳", "🇧🇷", "🇲🇽",
        ])

    private var allIOSEmojiTokens: [String] {
        Self.cachedIOSEmojiTokens
    }

    private static func unicodeScalarTokens(in ranges: [ClosedRange<Int>]) -> [String] {
        var tokens: [String] = []
        var seen = Set<String>()
        for range in ranges {
            for value in range {
                guard let scalar = UnicodeScalar(UInt32(value)),
                      !CharacterSet.controlCharacters.contains(scalar),
                      !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                    continue
                }
                let token = String(scalar)
                guard seen.insert(token).inserted else { continue }
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func uniqueKeyShelfTokens(_ rawTokens: [String]) -> [String] {
        var tokens: [String] = []
        var seen = Set<String>()
        for token in rawTokens {
            let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            tokens.append(value)
        }
        return tokens
    }

    private var actionLibrarySection: KeyBlockLibrarySection {
        KeyBlockLibrarySection(
            title: "Actions",
            detail: "Keyboard actions you can drop onto any editable key.",
            tokens: KeyboardSpecialKeyAction.allCases.map(\.storageToken)
        )
    }

    private var keyBlockSections: [KeyBlockLibrarySection] {
        switch selectedEditableRow.tapVariant {
        case .quickInsert, .holdQuickInsert, .toolbar, .holdToolbar:
            return allIOSKeyShelfSections + [actionLibrarySection] + layerLibrarySections + broadKeyShelfSections + [
                KeyBlockLibrarySection(
                    title: "Smart Picks",
                    detail: selectedEditableRow.isHoldRow
                        ? "Fast alternate actions for a long press on the one-line strip."
                        : "Fast shortcuts for the one-line strip.",
                    tokens: paletteTokens
                ),
                KeyBlockLibrarySection(
                    title: "Web",
                    detail: "Link, domain, and handle shortcuts.",
                    tokens: [".com", ".net", ".org", "@", "#", "/", "-", "_"]
                ),
                KeyBlockLibrarySection(
                    title: "Writing",
                    detail: "Frequent punctuation and separators.",
                    tokens: [",", ".", "!", "?", "'", "\"", ";", ":"]
                ),
                KeyBlockLibrarySection(
                    title: "Coding",
                    detail: "Compact symbols for technical typing.",
                    tokens: ["[]", "()", "{}", "<>", "=", "+", "-", "*"]
                ),
            ]
        case .symbolUtility, .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility,
             .letterUtility, .letterBottomLeading:
            return allIOSKeyShelfSections + [actionLibrarySection] + layerLibrarySections + broadKeyShelfSections + [
                KeyBlockLibrarySection(
                    title: "Smart Picks",
                    detail: "Current control values, defaults, and fast replacements for this slot.",
                    tokens: paletteTokens
                ),
                KeyBlockLibrarySection(
                    title: "Text",
                    detail: "Short labels and characters that still fit well on utility keys.",
                    tokens: [".", ",", "!", "?", "@", "#", "/", "-", "_", ".com", "1", "2", "3"]
                ),
            ]
        case .symbolTop, .holdSymbolTop, .symbolMiddle, .holdSymbolMiddle, .symbolBottom, .holdSymbolBottom,
             .symbolMain, .symbolHold:
            return allIOSKeyShelfSections + [actionLibrarySection] + layerLibrarySections + broadKeyShelfSections + [
                KeyBlockLibrarySection(
                    title: "Smart Picks",
                    detail: selectedEditableRow.isHoldRow
                        ? "Alternate symbol actions already used in this layout."
                        : "Symbols already used in this layout and preset.",
                    tokens: paletteTokens
                ),
                KeyBlockLibrarySection(
                    title: "Core Symbols",
                    detail: "Common symbol-set building blocks.",
                    tokens: ["@", "#", "$", "%", "&", "*", "_", "=", "+", "|", "/", "\\"]
                ),
                KeyBlockLibrarySection(
                    title: "Punctuation",
                    detail: "Punctuation for symbol-heavy layouts.",
                    tokens: ["!", "?", ":", ";", ".", ",", "-", "\"", "'"]
                ),
            ]
        case .letterTop, .holdLetterTop, .letterMiddle, .holdLetterMiddle, .letterBottom, .holdLetterBottom,
             .letterMain, .letterHold:
            return allIOSKeyShelfSections + [actionLibrarySection] + layerLibrarySections + broadKeyShelfSections + [
                KeyBlockLibrarySection(
                    title: "Smart Picks",
                    detail: selectedEditableRow.isHoldRow
                        ? "Hardware-style symbol legends and alternate ABC hold actions."
                        : "Current row values, preset values, and smart extras.",
                    tokens: paletteTokens
                ),
                KeyBlockLibrarySection(
                    title: "Alphabet",
                    detail: "Alphabet tokens for direct letter swaps.",
                    tokens: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "a", "s", "d", "f", "g", "h", "j", "k", "l", "z", "x", "c", "v", "b", "n", "m"]
                ),
                KeyBlockLibrarySection(
                    title: "Writing",
                    detail: "Punctuation that fits naturally on ABC rows.",
                    tokens: ["enter", ".", ",", "'", "\"", "!", "?", ":", ";"]
                ),
                KeyBlockLibrarySection(
                    title: "Web",
                    detail: "Useful tokens for mixed text and web entry.",
                    tokens: [".com", "@", "#", "/", "-", "_"]
                ),
            ]
        }
    }

    private var layerLibrarySections: [KeyBlockLibrarySection] {
        guard let layersLibrarySection else { return [] }
        return [layersLibrarySection]
    }

    private var broadKeyShelfSections: [KeyBlockLibrarySection] {
        [
            KeyBlockLibrarySection(
                title: "Navigation",
                detail: "Cursor movement, return, space, tab, and keyboard switches.",
                tokens: [
                    KeyboardSpecialKeyAction.moveLeft.storageToken,
                    KeyboardSpecialKeyAction.moveRight.storageToken,
                    KeyboardSpecialKeyAction.moveUp.storageToken,
                    KeyboardSpecialKeyAction.moveDown.storageToken,
                    KeyboardSpecialKeyAction.enter.storageToken,
                    KeyboardSpecialKeyAction.space.storageToken,
                    KeyboardSpecialKeyAction.tab.storageToken,
                    KeyboardSpecialKeyAction.shift.storageToken,
                    KeyboardSpecialKeyAction.toggleLayer.storageToken,
                    KeyboardSpecialKeyAction.menu.storageToken,
                    KeyboardSpecialKeyAction.nextKeyboard.storageToken,
                ]
            ),
            KeyBlockLibrarySection(
                title: "Editing",
                detail: "Delete, clipboard, and edit-history actions.",
                tokens: [
                    KeyboardSpecialKeyAction.deleteBackward.storageToken,
                    KeyboardSpecialKeyAction.deleteForward.storageToken,
                    KeyboardSpecialKeyAction.undo.storageToken,
                    KeyboardSpecialKeyAction.redo.storageToken,
                    KeyboardSpecialKeyAction.cut.storageToken,
                    KeyboardSpecialKeyAction.copy.storageToken,
                    KeyboardSpecialKeyAction.paste.storageToken,
                    KeyboardSpecialKeyAction.clipboard.storageToken,
                ]
            ),
            KeyBlockLibrarySection(
                title: "Numbers",
                detail: "Digits and number-like shortcuts.",
                tokens: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
            ),
            KeyBlockLibrarySection(
                title: "Symbols",
                detail: "Common punctuation, operators, and brackets.",
                tokens: ["@", "#", "$", "%", "&", "*", "_", "=", "+", "-", "/", "\\", "|", "~", "`", "[]", "()", "{}", "<>", "\"", "'"]
            ),
        ]
    }

    private var layersLibrarySection: KeyBlockLibrarySection? {
        let tokens = customLayerTokens
        guard !tokens.isEmpty else { return nil }
        return KeyBlockLibrarySection(
            title: "Layers",
            detail: "Custom layers that can be opened from the selected key.",
            tokens: tokens
        )
    }

    private var customLayerTokens: [String] {
        settings.customKeymapLayers.map(\.storageToken)
    }

    private var paletteTokens: [String] {
        let targetRow = selectedEditableRow
        let current = settings.values(for: targetRow)
        let preset = settings.layoutPreset == .custom ? KeyboardLayoutPreset.compact : settings.layoutPreset
        let presetValues = values(for: targetRow, in: KeyboardKeymap.preset(preset))
        let extras: [String]

        switch targetRow.tapVariant {
        case .quickInsert, .holdQuickInsert, .toolbar, .holdToolbar:
            extras = targetRow.isHoldRow
                ? ["@", "#", "/", "-", "_", "{", "}", "[", "]", "(", ")", "<", ">"]
                : [".com", ",", ".", "!", "?", "@", "#", "/", "-", "_", ".net", ".org"]
        case .symbolUtility, .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility,
             .letterUtility, .letterBottomLeading:
            extras = KeyboardSpecialKeyAction.allCases.map(\.storageToken)
                + [".", ",", "!", "?", "@", "#", "/", "-", "_", ".com"]
        case .symbolTop, .holdSymbolTop, .symbolMain, .symbolHold:
            extras = [".com", ".net", ".org", "@", "#", "/", "\\"]
        case .symbolMiddle, .holdSymbolMiddle:
            extras = ["@", "#", "$", "%", "&", "*", "_", "="]
        case .symbolBottom, .holdSymbolBottom:
            extras = ["!", "?", ":", ";", ".", ",", "-", "+", "\"", "'"]
        case .letterTop, .holdLetterTop, .letterMain, .letterHold:
            extras = targetRow.isHoldRow
                ? ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
                : ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
        case .letterMiddle, .holdLetterMiddle:
            extras = targetRow.isHoldRow
                ? ["@", "#", "$", "%", "&", "*", "(", ")", "_", "="]
                : ["a", "s", "d", "f", "g", "h", "j", "k", "l", "enter"]
        case .letterBottom, .holdLetterBottom:
            extras = targetRow.isHoldRow
                ? ["!", "?", ":", ";", "/", "\\", "-", ".", "\"", "'"]
                : ["z", "x", "c", "v", "b", "n", "m", ",", ":"]
        }

        var tokens = [String]()
        for token in current + presetValues + extras {
            guard !token.isEmpty, !tokens.contains(token) else { continue }
            tokens.append(token)
        }
        return Array(tokens.prefix(40))
    }

    private var selectedRowSummary: String {
        switch selectedEditableRow {
        case .quickInsert, .toolbar:
            return "Main Row"
        case .holdQuickInsert, .holdToolbar:
            return "Main Row • Hold"
        case .symbolUtility:
            return "Expanded Symbols • Utility"
        case .symbolTop:
            return "Expanded Symbols • Row 1"
        case .holdSymbolTop:
            return "Expanded Symbols • Hold Row 1"
        case .symbolMiddle:
            return "Expanded Symbols • Row 2"
        case .holdSymbolMiddle:
            return "Expanded Symbols • Hold Row 2"
        case .symbolBottom:
            return "Expanded Symbols • Row 3"
        case .holdSymbolBottom:
            return "Expanded Symbols • Hold Row 3"
        case .symbolMain:
            return "Expanded Symbols • Row"
        case .symbolHold:
            return "Expanded Symbols • Hold Row"
        case .trailingUtility:
            return "Main Row Key 1"
        case .expandedTrailingUtility:
            return "Expanded Symbols Key 1"
        case .expandedLetterTrailingUtility:
            return "Expanded ABC Key 1"
        case .letterUtility:
            return "Expanded ABC • Utility"
        case .letterBottomLeading:
            return "Expanded ABC • Lead Key"
        case .letterTop:
            return "Expanded ABC • Row 1"
        case .holdLetterTop:
            return "Expanded ABC • Hold Row 1"
        case .letterMiddle:
            return "Expanded ABC • Row 2"
        case .holdLetterMiddle:
            return "Expanded ABC • Hold Row 2"
        case .letterBottom:
            return "Expanded ABC • Row 3"
        case .holdLetterBottom:
            return "Expanded ABC • Hold Row 3"
        case .letterMain:
            return "Expanded ABC • Row"
        case .letterHold:
            return "Expanded ABC • Hold Row"
        }
    }

    private var selectedKeyCardTitle: String {
        if let selectedCustomLayerKeySelection,
           let layer = settings.customKeymapLayers.first(where: { $0.id == selectedCustomLayerKeySelection.layerID }) {
            return "\(layer.title) • Row \(selectedCustomLayerKeySelection.rowIndex + 1) • Key \(selectedCustomLayerKeySelection.keyIndex + 1)"
        }

        if let action = KeyboardSpecialKeyAction.resolved(from: selectedKeyBinding.wrappedValue) {
            switch action {
            case .shift:
                return "Shift Key"
            case .toggleLayer:
                return "ABC/123 Key"
            case .toggleSymbolPage:
                return "SYM1/SYM2 Key"
            case .menu:
                return "Menu Key"
            default:
                break
            }
        }

        return "\(selectedRowSummary) • Key \(safeSelectedSlotIndex + 1)"
    }

    private var selectedRowHelp: String {
        if selectedCustomLayerKeySelection != nil {
            if selectedEditActionMode == .hold {
                return "Assign one hold choice, or separate multiple ordered choices with |. Repeated holds cycle those choices."
            }
            return "Assign the key shown on this custom layer. The layer opens when its token is assigned to any key."
        }

        if selectedEditActionMode == .hold {
            return "Assign one hold choice, or separate multiple ordered choices with |. Repeated holds cycle those choices."
        }

        switch selectedEditableRow {
        case .quickInsert, .toolbar:
            return "Assign the text inserted by this top-row shortcut. Changes are saved instantly."
        case .holdQuickInsert, .holdToolbar:
            return "Assign the alternate action inserted when this top-row shortcut is held."
        case .symbolUtility:
            return "Assign the actions or text shown in the expanded Symbols control strip."
        case .symbolTop, .symbolMiddle, .symbolBottom, .symbolMain:
            return "Assign the symbol or shortcut string that appears in the expanded symbol keyboard after tapping More."
        case .holdSymbolTop, .holdSymbolMiddle, .holdSymbolBottom, .symbolHold:
            return "Assign the alternate string inserted when this expanded symbol key is held."
        case .trailingUtility:
            return "Assign this main-row key beside Menu. It edits only this key."
        case .expandedTrailingUtility:
            return "Assign this expanded Symbols key beside Menu. It edits only this key."
        case .expandedLetterTrailingUtility:
            return "Assign this expanded ABC key beside Menu. It edits only this key."
        case .letterUtility:
            return "Assign the actions or text shown in the expanded ABC control strip."
        case .letterBottomLeading:
            return "Assign the leading key shown before the bottom ABC row. This is where Forward Delete lives by default."
        case .letterTop, .letterMiddle, .letterBottom, .letterMain:
            return "Assign the character or shortcut string that appears in the expanded ABC keyboard after tapping More, then switching away from symbols."
        case .holdLetterTop, .holdLetterMiddle, .holdLetterBottom, .letterHold:
            return "Assign the hardware-style symbol legend inserted when this expanded ABC key is held."
        }
    }

    private func rows(for layer: ExpandedKeymapLayer) -> [[String]] {
        expandedRows(for: layer).map(displayedValues(for:))
    }

    private func displayedValues(for row: KeyboardRowKind) -> [String] {
        if let layoutRow = sym2LayoutRow(for: row) {
            if row.isHoldRow {
                return layoutRow.keys.map { key in
                    key.holdChoices.first ?? key.hold ?? ""
                }
            }
            return layoutRow.keys.map(\.tap)
        }
        let targetCount = settings.slotCount(for: row)
        let values = settings.values(for: row)

        if values.count > targetCount {
            return Array(values.prefix(targetCount))
        }

        if values.count < targetCount {
            return values + Array(repeating: "", count: targetCount - values.count)
        }

        return values
    }

    private func sym2LayoutRow(for row: KeyboardRowKind) -> KeyboardLayoutRow? {
        guard selectedCustomLayerID == nil, selectedExpandedLayer == .symbols2 else { return nil }
        switch row.tapVariant {
        case .symbolTop, .symbolMiddle, .symbolBottom:
            return settings.keymap.rows(surface: .symbols2, holdLayer: false)
                .first(where: { $0.kind == row.tapVariant })
        default:
            return nil
        }
    }

    private func previewDisplayedValues(for row: KeyboardRowKind) -> [String] {
        displayedValues(for: row)
    }

    private func values(for row: KeyboardRowKind, in keymap: KeyboardKeymap) -> [String] {
        switch row {
        case .quickInsert, .holdQuickInsert:
            return []
        case .toolbar:
            return keymap.toolbarRow
        case .holdToolbar:
            return keymap.holdToolbarRow
        case .symbolUtility:
            return keymap.symbolUtilityRow
        case .symbolTop:
            return keymap.symbolTopRow
        case .holdSymbolTop:
            return keymap.holdSymbolTopRow
        case .symbolMiddle:
            return keymap.symbolMiddleRow
        case .holdSymbolMiddle:
            return keymap.holdSymbolMiddleRow
        case .symbolBottom:
            return keymap.symbolBottomRow
        case .holdSymbolBottom:
            return keymap.holdSymbolBottomRow
        case .symbolMain:
            return keymap.symbolTopRow
        case .symbolHold:
            return keymap.holdSymbolTopRow
        case .trailingUtility:
            return keymap.trailingUtilityRow
        case .expandedTrailingUtility:
            return keymap.expandedTrailingUtilityRow
        case .expandedLetterTrailingUtility:
            return keymap.expandedLetterTrailingUtilityRow
        case .letterUtility:
            return keymap.letterUtilityRow
        case .letterBottomLeading:
            return keymap.letterBottomLeadingRow
        case .letterTop:
            return keymap.letterTopRow
        case .holdLetterTop:
            return keymap.holdLetterTopRow
        case .letterMiddle:
            return keymap.letterMiddleRow
        case .holdLetterMiddle:
            return keymap.holdLetterMiddleRow
        case .letterBottom:
            return keymap.letterBottomRow
        case .holdLetterBottom:
            return keymap.holdLetterBottomRow
        case .letterMain:
            return keymap.letterTopRow
        case .letterHold:
            return keymap.holdLetterTopRow
        }
    }

    private func expandedRows(for layer: ExpandedKeymapLayer) -> [KeyboardRowKind] {
        switch layer {
        case .symbols1, .symbols2:
            return [
                editableRow(for: .symbolTop),
                editableRow(for: .symbolMiddle),
                editableRow(for: .symbolBottom),
            ]
        case .letters:
            return [
                editableRow(for: .letterTop),
                editableRow(for: .letterMiddle),
                editableRow(for: .letterBottom),
            ]
        }
    }

    private func safeSlotIndex(for row: KeyboardRowKind) -> Int {
        clampedSlotIndex(selectedSlotIndex, for: row)
    }

    private func clampedSlotIndex(_ index: Int, for row: KeyboardRowKind) -> Int {
        let count = settings.slotCount(for: row)
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    private func clampSelectedSlotIndex() {
        selectedSlotIndex = clampedSlotIndex(selectedSlotIndex, for: selectedEditableRow)
    }

    private func syncKeyShelfSectionSelection() {
        let availableIDs = keyBlockSections.map(\.id)

        guard !availableIDs.isEmpty else {
            selectedKeyShelfSectionID = ""
            return
        }

        if !availableIDs.contains(selectedKeyShelfSectionID) {
            selectedKeyShelfSectionID = availableIDs[0]
        }
    }

    @discardableResult
    private func selectKeyForEditing(
        _ row: KeyboardRowKind,
        slotIndex: Int
    ) -> Bool {
        guard !isLockedEditableKey(row: row, slotIndex: slotIndex) else {
            presentABCUnlockPrompt()
            return false
        }

        let selection = HWKKeymapEditorNavigation.rowAfterSelectingRenderedKey(
            row,
            currentMode: selectedEditActionMode.navigationMode
        )
        let resolvedMode = KeyboardEditActionMode(selection.mode)
        if selectedEditActionMode != resolvedMode {
            selectedEditActionMode = resolvedMode
        }

        selectedCustomLayerKeySelection = nil
        selectedEditableRow = selection.row
        selectedSlotIndex = clampedSlotIndex(slotIndex, for: selectedEditableRow)
        syncKeyShelfSectionSelection()
        withAnimation(liveEditorSpring) {
            isKeyShelfExpanded = false
        }
        return true
    }

    private func selectCustomLayerKeyForEditing(_ selection: CustomLayerEditorKeySelection) {
        selectedCustomLayerKeySelection = selection
        syncKeyShelfSectionSelection()
        withAnimation(liveEditorSpring) {
            isKeyShelfExpanded = false
        }
    }

    private func presentKeyEditor(row: KeyboardRowKind, slotIndex: Int) {
        guard selectKeyForEditing(row, slotIndex: slotIndex) else { return }
        presentSelectedKeyEditor()
    }

    private func presentSelectedKeyEditor() {
        pendingKeyEditor = KeyEditorItem(
            title: selectedKeyCardTitle,
            actionTitle: selectedEditActionMode == .hold ? "Hold Action" : "Tap Action",
            initialValue: selectedKeyBinding.wrappedValue
        )
    }

    private var keyEditorSections: [KeyEditorSection] {
        keyBlockSections.map { section in
            KeyEditorSection(
                title: section.title,
                detail: section.detail,
                choices: Self.uniqueKeyShelfTokens(section.tokens).map(keyEditorChoice)
            )
        }
    }

    private func keyEditorChoice(_ token: String) -> KeyEditorChoice {
        if let customLayer = customLayerTokenVisual(token) {
            return KeyEditorChoice(
                token: token,
                title: customLayer.title,
                systemImage: customLayer.icon
            )
        }
        let visual = utilityTokenVisual(for: token)
        return KeyEditorChoice(
            token: token,
            title: visual?.label ?? visual?.text ?? tokenLabel(token),
            systemImage: visual?.icon
        )
    }

    private func toggleKeyboardEditorExpansion() {
        setKeyboardEditorSurface(
            isKeyboardEditorExpanded
                ? .mainRow
                : (selectedExpandedLayer == .letters ? .letters : .symbols1)
        )
    }

    private func toggleExpandedEditingLayer() {
        setKeyboardEditorSurface(selectedExpandedLayer == .symbols1 ? .letters : .symbols1)
    }

    private func addCustomLayer() {
        guard !isAdditionalLayersLocked else {
            return
        }

        let customLayer = settings.addCustomKeymapLayer(surface: .mainRow)
        selectedCustomLayerID = customLayer.id
        selectedCustomLayerKeySelection = nil
        selectedExpandedLayer = .symbols1
        isKeyboardEditorExpanded = false
        selectedKeyShelfSectionID = layersLibrarySection?.id ?? selectedKeyShelfSectionID
        syncKeyShelfSectionSelection()
    }

    private var newCustomLayerSurface: KeyboardRowSurface {
        switch keyboardEditorSurface {
        case .mainRow:
            return .mainRow
        case .letters:
            return .letters
        case .symbols1:
            return .symbols1
        case .symbols2:
            return .symbols2
        }
    }

    private func presentCustomLayerHoldPrompt(_ option: KeyboardEditorLayerOption) {
        guard option.customLayerID != nil else { return }
        pendingCustomLayerHoldPrompt = option
    }

    private var additionalLayerScrubObserver: some View {
        let layers = accessibleCustomKeymapLayers
        return KeyboardEditorAdditionalLayerScrubObserver(
            itemCount: layers.count + 1,
            scrubHandler: { location, size, state in
                guard draggedCustomLayerID == nil else {
                    layerDropletFingerLocation = nil
                    return
                }
                updateKeyboardEditorLayerScrub(
                    at: CGPoint(
                        x: location.x,
                        y: location.y + HWCKeymapEditorLayerScrubPolicy.topRowHeight
                    ),
                    selectorWidth: size.width,
                    state: state
                )
            }
        )
    }


    private func additionalLayerHoldDragGesture(
        for option: KeyboardEditorLayerOption
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .sequenced(before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("liveEditorAdditionalLayerDrag")
            ))
            .onChanged { value in
                guard case .second(true, let drag?) = value,
                      let layerID = option.customLayerID else { return }
                withAnimation(layerDropletSpring) {
                    draggedCustomLayerID = layerID
                }
                additionalLayerDragLocation = drag.location
            }
            .onEnded { value in
                defer {
                    withAnimation(layerDropletSpring) {
                        draggedCustomLayerID = nil
                        additionalLayerDragLocation = nil
                    }
                }

                guard case .second(true, let drag?) = value else { return }
                let dragDistance = hypot(drag.translation.width, drag.translation.height)
                if additionalLayerTrashFrame.contains(drag.location) {
                    deleteCustomLayerFromPrompt(option)
                } else if dragDistance < 12 {
                    presentCustomLayerHoldPrompt(option)
                }
            }
    }


    private func saveCustomLayerEdits(layerID: UUID, title: String, iconSystemName: String) {
        settings.renameCustomKeymapLayer(id: layerID, title: title)
        settings.updateCustomKeymapLayerIcon(id: layerID, systemName: iconSystemName)
        syncKeyShelfSectionSelection()
    }

    private func convertCustomLayerFromPrompt(
        _ option: KeyboardEditorLayerOption,
        to style: KeyboardCustomLayerStyle
    ) {
        guard let layerID = option.customLayerID else { return }
        settings.convertCustomKeymapLayer(id: layerID, to: style)
        selectedCustomLayerID = layerID
        selectedCustomLayerKeySelection = nil
        isKeyboardEditorExpanded = style == .expanded
        selectedExpandedLayer = .symbols1
        syncKeyShelfSectionSelection()
    }

    private func deleteCustomLayerFromPrompt(_ option: KeyboardEditorLayerOption) {
        guard let layerID = option.customLayerID else { return }
        let deletedLayerSurface = settings.customKeymapLayers.first(where: { $0.id == layerID })?.surface
        settings.deleteCustomKeymapLayer(id: layerID)
        if selectedCustomLayerID == layerID {
            selectedCustomLayerID = nil
            selectedCustomLayerKeySelection = nil
            setKeyboardEditorSurface(deletedLayerSurface == .letters ? .letters : .symbols1)
        }
        syncKeyShelfSectionSelection()
    }

    private func setKeyboardEditorLayerSelection(_ selectionID: String) {
        let currentSelectionID = keyboardEditorLayerSelectionID
        if currentSelectionID != selectionID {
            previousKeyboardEditorLayerSelectionID = currentSelectionID
        }

        if selectionID == KeyboardEditorLayerOption.mainRowID {
            selectedCustomLayerID = nil
            selectedCustomLayerKeySelection = nil
            setKeyboardEditorSurface(.mainRow)
            return
        }

        if selectionID == KeyboardEditorLayerOption.symbols1ID {
            selectedCustomLayerID = nil
            selectedCustomLayerKeySelection = nil
            setKeyboardEditorSurface(.symbols1)
            return
        }

        if selectionID == KeyboardEditorLayerOption.symbols2ID {
            selectedCustomLayerID = nil
            selectedCustomLayerKeySelection = nil
            setKeyboardEditorSurface(.symbols2)
            return
        }

        if selectionID == KeyboardEditorLayerOption.lettersID {
            selectedCustomLayerID = nil
            selectedCustomLayerKeySelection = nil
            setKeyboardEditorSurface(.letters)
            return
        }

        if selectionID.hasPrefix(KeyboardEditorLayerOption.customIDPrefix) {
            let idText = String(selectionID.dropFirst(KeyboardEditorLayerOption.customIDPrefix.count))
            if let id = UUID(uuidString: idText),
               canAccessCustomLayer(id),
               let layer = settings.customKeymapLayers.first(where: { $0.id == id }) {
                selectedCustomLayerID = id
                selectedCustomLayerKeySelection = nil
                selectedExpandedLayer = layer.surface == .letters ? .letters : .symbols1
                isKeyboardEditorExpanded = layer.surface != .mainRow
                return
            }
        }

        selectedCustomLayerID = nil
        selectedCustomLayerKeySelection = nil
        setKeyboardEditorSurface(.symbols1)
    }

    private func setKeyboardEditorSurface(_ surface: KeyboardEditorSurface) {
        selectedCustomLayerID = nil
        selectedCustomLayerKeySelection = nil
        let selection = HWKKeymapEditorNavigation.rowAfterChangingSurface(
            to: surface.navigationSurface,
            currentRow: selectedEditableRow,
            currentMode: selectedEditActionMode.navigationMode
        )

        withAnimation(liveEditorSpring) {
            switch surface {
            case .mainRow:
                isKeyboardEditorExpanded = false
            case .symbols1:
                isKeyboardEditorExpanded = true
                selectedExpandedLayer = .symbols1
            case .symbols2:
                isKeyboardEditorExpanded = true
                selectedExpandedLayer = .symbols2
            case .letters:
                isKeyboardEditorExpanded = true
                selectedExpandedLayer = .letters
            }

            let resolvedMode = KeyboardEditActionMode(selection.mode)
            if selectedEditActionMode != resolvedMode {
                selectedEditActionMode = resolvedMode
            }
            selectedEditableRow = selection.row

            if surface == .letters {
                if isLockedEditableKey(row: selection.row, slotIndex: safeSelectedSlotIndex) {
                    isKeyShelfExpanded = false
                    showsABCUnlockPrompt = false
                }
            }

            clampSelectedSlotIndex()
            syncKeyShelfSectionSelection()
        }
    }

    private func selectEditableRow(_ row: KeyboardRowKind, slotIndex: Int) {
        selectedEditableRow = row
        selectedSlotIndex = clampedSlotIndex(slotIndex, for: row)
    }

    private func keyDragPayload(row: KeyboardRowKind, slotIndex: Int, value: String) -> String? {
        guard !value.isEmpty else { return nil }
        return "hwkb-slot|\(row.rawValue)|\(slotIndex)"
    }

    private func decodeKeyDragPayload(_ payload: String) -> (row: KeyboardRowKind, slotIndex: Int)? {
        let components = payload.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "hwkb-slot",
              let row = KeyboardRowKind(rawValue: String(components[1])),
              let slotIndex = Int(components[2]) else {
            return nil
        }

        return (row, slotIndex)
    }

    private func applyDroppedKeyValue(
        from providers: [NSItemProvider],
        to row: KeyboardRowKind,
        slotIndex: Int
    ) -> Bool {
        guard !isLockedEditableKey(row: row, slotIndex: slotIndex) else {
            presentABCUnlockPrompt()
            return false
        }

        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString else { return }

            DispatchQueue.main.async {
                let droppedValue = String(text)
                selectKeyForEditing(row, slotIndex: slotIndex)

                if let source = decodeKeyDragPayload(droppedValue) {
                    settings.swapKeys(
                        from: source.row,
                        sourceIndex: source.slotIndex,
                        to: row,
                        destinationIndex: slotIndex
                    )
                } else {
                    setKeyValueWithModeChangeWarning(droppedValue, row: row, slotIndex: slotIndex)
                }
            }
        }

        return true
    }

    private var additionalLayerPurchasePrice: String {
        if additionalLayersStore.isLoadingProduct && additionalLayersStore.priceLabel.isEmpty {
            return "Loading…"
        }
        return additionalLayersStore.priceLabel.isEmpty ? "Retry" : additionalLayersStore.priceLabel
    }

    private var hasUnlimitedAdditionalLayerAccess: Bool {
        supportDeveloperStore.isUnlocked && !additionalLayersStore.isLayerPurchaseTestingResetActive
    }

    private var isAdditionalLayersLocked: Bool {
        !additionalLayersStore.canUseLayerCount(settings.customKeymapLayers.count) && !hasUnlimitedAdditionalLayerAccess
    }

    private var accessibleCustomKeymapLayers: [KeyboardCustomLayer] {
        settings.customKeymapLayers.enumerated().compactMap { index, layer in
            HWCAdditionalLayerEntitlementPolicy.canAccessLayer(
                at: index,
                purchasedCredits: additionalLayersStore.purchasedLayerCount,
                hasUnlimitedAccess: hasUnlimitedAdditionalLayerAccess
            ) ? layer : nil
        }
    }

    private func canAccessCustomLayer(_ id: UUID) -> Bool {
        guard let index = settings.customKeymapLayers.firstIndex(where: {
            $0.id == id
        }) else {
            return false
        }
        return HWCAdditionalLayerEntitlementPolicy.canAccessLayer(
            at: index,
            purchasedCredits: additionalLayersStore.purchasedLayerCount,
            hasUnlimitedAccess: hasUnlimitedAdditionalLayerAccess
        )
    }

    private func enforceAdditionalLayerAccess() {
        guard let selectedCustomLayerID,
              !canAccessCustomLayer(selectedCustomLayerID) else {
            return
        }
        self.selectedCustomLayerID = nil
        selectedCustomLayerKeySelection = nil
        setKeyboardEditorSurface(.mainRow)
    }

    private var isABCLayerLocked: Bool {
        isABCEditingLocked &&
            isKeyboardEditorExpanded &&
            selectedExpandedLayer == .letters
    }

    private var isABCPurchaseLocked: Bool {
        !abcUnlockStore.isUnlocked && !supportDeveloperStore.isUnlocked
    }

    private var isHardwarePremiumLocked: Bool {
        return true // Reader retirement cannot be bypassed by previous purchases or yearly support.
    }

    private var hardwareKeyboardTestEnabled: Bool {
        !isHardwarePremiumLocked && settings.signalRelayEnabled
    }

    #if HWC_INTERNAL_BUILD
    private var hardwareMonitorEnabled: Bool {
        HWCBuildFlavor.supportsHardwareDebugTools &&
        scenePhase == .active &&
        !isHardwarePremiumLocked &&
        settings.signalRelayEnabled
    }

    private var companionHardwareDiagnosticFlags: Int {
        var flags = 0

        if settings.signalRelayEnabled {
            flags |= 1 << 0
        }

        if settings.signalRelayEmitKeyUp {
            flags |= 1 << 1
        }

        if settings.signalRelayPriorityMode {
            flags |= 1 << 2
        }

        if hardwareMonitorEnabled {
            flags |= 1 << 3
        }

        if !isHardwarePremiumLocked {
            flags |= 1 << 4
        }

        return flags
    }
    #endif

    private var isABCEditingLocked: Bool {
        isABCPurchaseLocked || (hasProtectedABCLayer && !isABCLayerUnlocked)
    }

    private var isABCSettingsLocked: Bool {
        false
    }

    private func isLockedEditableKey(row: KeyboardRowKind, slotIndex: Int) -> Bool {
        guard isABCEditingLocked else { return false }
        return ProtectedABCLayerMap.lockedSlotIndexes(for: row).contains(slotIndex)
    }

    private func modeChangeKeyWarning(for value: String) -> String? {
        switch KeyboardSpecialKeyAction.resolved(from: value) {
        case .some(.menu):
            return "Menu opens expanded layers. Removing it can strand Symbols, ABC, and Additional Layers."
        case .some(.toggleLayer):
            return "ABC/123 switches between expanded layers. Removing it can strand the symbol and ABC flow."
        case .some(.toggleSymbolPage):
            return "SYM1/SYM2 switches between symbol pages. Removing it can strand the alternate symbol page."
        default:
            return nil
        }
    }

    private var selectedKeyModeChangeWarning: String? {
        selectedKeyModeChangeWarning(for: "")
    }

    private func selectedKeyModeChangeWarning(for replacementValue: String) -> String? {
        guard selectedCustomLayerKeySelection == nil else { return nil }
        return modeChangeKeyWarning(
            row: selectedEditableRow,
            slotIndex: safeSelectedSlotIndex,
            replacementValue: replacementValue
        )
    }

    private func setSelectedKeyValueWithModeChangeWarning(_ value: String) {
        if let selectedCustomLayerKeySelection {
            setCustomLayerKeyValue(
                value,
                selection: selectedCustomLayerKeySelection,
                holdLayer: selectedEditActionMode == .hold
            )
            return
        }

        setKeyValueWithModeChangeWarning(value, row: selectedEditableRow, slotIndex: safeSelectedSlotIndex)
    }

    private func setSelectedKeyValueWithoutModeChangeWarning(_ value: String) {
        if let selectedCustomLayerKeySelection {
            setCustomLayerKeyValue(
                value,
                selection: selectedCustomLayerKeySelection,
                holdLayer: selectedEditActionMode == .hold
            )
            return
        }

        setKeyValueWithoutModeChangeWarning(
            value,
            row: selectedEditableRow,
            slotIndex: safeSelectedSlotIndex
        )
    }

    private func deleteSelectedKey() {
        if let selectedCustomLayerKeySelection {
            settings.removeKeymapTableColumn(keyID: selectedCustomLayerKeySelection.keyID, rowID: selectedCustomLayerKeySelection.rowID)
            self.selectedCustomLayerKeySelection = nil
            return
        }

        let row = selectedEditableRow
        let slotIndex = safeSelectedSlotIndex

        guard !isLockedEditableKey(row: row, slotIndex: slotIndex) else {
            presentABCUnlockPrompt()
            return
        }

        guard (0..<settings.slotCount(for: row)).contains(slotIndex) else { return }

        if let warning = modeChangeKeyWarning(row: row, slotIndex: slotIndex, replacementValue: "") {
            pendingModeChangeKeyEdit = PendingModeChangeKeyEdit(
                row: row,
                slotIndex: slotIndex,
                replacementValue: "",
                removesSlot: true,
                warning: warning
            )
            return
        }

        deleteKey(row: row, slotIndex: slotIndex)
    }

    private func deleteSelectedKeyWithoutModeChangeWarning() {
        if let selectedCustomLayerKeySelection {
            settings.removeKeymapTableColumn(
                keyID: selectedCustomLayerKeySelection.keyID,
                rowID: selectedCustomLayerKeySelection.rowID
            )
            self.selectedCustomLayerKeySelection = nil
            return
        }

        let row = selectedEditableRow
        let slotIndex = safeSelectedSlotIndex

        guard !isLockedEditableKey(row: row, slotIndex: slotIndex) else {
            presentABCUnlockPrompt()
            return
        }

        guard (0..<settings.slotCount(for: row)).contains(slotIndex) else { return }
        deleteKey(row: row, slotIndex: slotIndex)
    }

    private func shouldPreserveABCRowCountDuringLockedEdit(_ row: KeyboardRowKind) -> Bool {
        guard isABCEditingLocked else { return false }
        switch row.tapVariant {
        case .letterTop, .letterMiddle, .letterBottom:
            return true
        default:
            return false
        }
    }

    private func deleteKey(row: KeyboardRowKind, slotIndex: Int) {
        if shouldPreserveABCRowCountDuringLockedEdit(row) {
            settings.updateValue("", for: row, index: slotIndex)
            selectedSlotIndex = clampedSlotIndex(slotIndex, for: row)
            return
        }

        if settings.removeVisibleKey(at: slotIndex, from: row) {
            selectedSlotIndex = clampedSlotIndex(slotIndex, for: row)
            return
        }

        settings.updateValue("", for: row, index: slotIndex)
    }

    private func setKeyValueWithModeChangeWarning(_ value: String, row: KeyboardRowKind, slotIndex: Int) {
        guard !isLockedEditableKey(row: row, slotIndex: slotIndex) else {
            presentABCUnlockPrompt()
            return
        }

        guard (0..<settings.slotCount(for: row)).contains(slotIndex) else { return }

        let values = settings.values(for: row)
        let currentValue = values.indices.contains(slotIndex) ? values[slotIndex] : ""
        if currentValue != value,
           let warning = modeChangeKeyWarning(row: row, slotIndex: slotIndex, replacementValue: value) {
            pendingModeChangeKeyEdit = PendingModeChangeKeyEdit(
                row: row,
                slotIndex: slotIndex,
                replacementValue: value,
                removesSlot: false,
                warning: warning
            )
            return
        }

        setKeyValueWithoutModeChangeWarning(value, row: row, slotIndex: slotIndex)
    }

    private func setKeyValueWithoutModeChangeWarning(
        _ value: String,
        row: KeyboardRowKind,
        slotIndex: Int
    ) {
        guard !isLockedEditableKey(row: row, slotIndex: slotIndex) else {
            presentABCUnlockPrompt()
            return
        }

        guard (0..<settings.slotCount(for: row)).contains(slotIndex) else { return }
        settings.updateValue(value, for: row, index: slotIndex)
    }

    private func modeChangeKeyWarning(
        row: KeyboardRowKind,
        slotIndex: Int,
        replacementValue: String
    ) -> String? {
        let values = settings.values(for: row)
        let currentValue = values.indices.contains(slotIndex) ? values[slotIndex] : ""
        let replacementAction = KeyboardSpecialKeyAction.resolved(from: replacementValue)

        if let warning = modeChangeKeyWarning(for: currentValue),
           KeyboardSpecialKeyAction.resolved(from: currentValue) != replacementAction {
            return warning
        }

        if let warning = modeChangeKeyWarning(for: mirroredModeChangeValue(row: row, slotIndex: slotIndex)),
           KeyboardSpecialKeyAction.resolved(from: mirroredModeChangeValue(row: row, slotIndex: slotIndex)) != replacementAction {
            return warning
        }

        return nil
    }

    private func mirroredModeChangeValue(row: KeyboardRowKind, slotIndex: Int) -> String {
        let tapRow = row.tapVariant
        let holdRow = tapRow.holdVariant
        guard tapRow.supportsHoldCustomization, holdRow != tapRow else { return "" }

        let mirrorRow = row.isHoldRow ? tapRow : holdRow
        let values = settings.values(for: mirrorRow)
        return values.indices.contains(slotIndex) ? values[slotIndex] : ""
    }

    private func applyPendingModeChangeKeyEdit(_ edit: PendingModeChangeKeyEdit) {
        if edit.removesSlot {
            deleteKey(row: edit.row, slotIndex: edit.slotIndex)
        } else {
            settings.updateValue(edit.replacementValue, for: edit.row, index: edit.slotIndex)
        }
    }

    private var protectedABCLayerStateID: String {
        [
            settings.layoutLocale.rawValue,
            String(settings.letterTopRowKeyCount),
            String(settings.letterMiddleRowKeyCount),
            String(settings.letterBottomRowKeyCount),
            settings.letterTopRow.joined(separator: "\u{1F}"),
            settings.letterMiddleRow.joined(separator: "\u{1F}"),
            settings.letterBottomRow.joined(separator: "\u{1F}"),
        ].joined(separator: "\u{1E}")
    }

    private var hasProtectedABCLayer: Bool {
        settings.snapshot.hasProtectedABCLayer
    }

    private func presentABCUnlockPrompt() {
        guard !isABCPurchaseLocked else { return }
        guard hasProtectedABCLayer else { return }
        withAnimation(liveEditorSpring) {
            isKeyShelfExpanded = false
            showsABCUnlockPrompt = true
        }
    }

    private func unlockABCLayer() {
        guard !isABCPurchaseLocked else { return }
        guard hasProtectedABCLayer else { return }

        withAnimation(liveEditorSpring) {
            isABCLayerUnlocked = true
            showsABCUnlockPrompt = false
        }
    }

    private func lockABCLayer() {
        showsABCUnlockPrompt = false
        withAnimation(liveEditorSpring) {
            isABCLayerUnlocked = false
            isKeyShelfExpanded = false
        }
    }

    private var shouldShowABCLayerLockButton: Bool {
        !isABCPurchaseLocked && hasProtectedABCLayer && selectedExpandedLayer == .letters && isABCLayerUnlocked
    }

    private func syncABCLayerProtectionState() {
        let hasProtectedLayer = hasProtectedABCLayer

        guard hasProtectedLayer != hadProtectedABCLayer else { return }

        hadProtectedABCLayer = hasProtectedLayer
        showsABCUnlockPrompt = false

        if hasProtectedLayer {
            withAnimation(liveEditorSpring) {
                isABCLayerUnlocked = false
                isKeyShelfExpanded = false
            }
        } else {
            isABCLayerUnlocked = false
        }
    }

    private func rowCountSummary(for layer: ExpandedKeymapLayer) -> String {
        switch layer {
        case .symbols1, .symbols2:
            return "\(settings.symbolTopRowKeyCount)/\(settings.symbolMiddleRowKeyCount)/\(settings.symbolBottomRowKeyCount) keys"
        case .letters:
            return "\(settings.letterTopRowKeyCount)/\(settings.letterMiddleRowKeyCount)/\(settings.letterBottomRowKeyCount) keys"
        }
    }

    private var keymapTemplateLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Templates")
                Spacer()
                if !managedBuiltInTemplates.isEmpty {
                    Menu("Built-in Templates") {
                        ForEach(managedBuiltInTemplates) { preset in
                            Menu(preset.title) {
                                Button("Edit Original") { editTemplateCopy(preset) }
                                Button("Clone Original") { cloneBuiltInTemplate(preset) }
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("keymap.templates.originals")
                }
            }
            if !prominentBuiltInTemplates.isEmpty {
                Text("Edit or clone a starting template. Edited copies appear in My Presets.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                presetGrid
            }
            if let editingTemplateID,
               let preset = settings.savedKeymapPresets.first(where: { $0.id == editingTemplateID }) {
                HStack {
                    Text("Editing \(preset.title)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Save Changes") { saveTemplateEdits() }
                        .disabled(!templateEditingMatchesSelection)
                        .accessibilityIdentifier("keymap.template.save")
                    Button("Done") { self.editingTemplateID = nil }
                }
                if !templateEditingMatchesSelection {
                    Text("Return to the layer you started editing to save this template.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            if let templateLibraryError {
                Text(templateLibraryError)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var managedBuiltInTemplates: [KeyboardLayoutPreset] {
        presetLibrary.filter { preset in
            settings.savedKeymapPresets.contains { $0.builtInTemplateSource == preset.rawValue }
        }
    }

    private var prominentBuiltInTemplates: [KeyboardLayoutPreset] {
        presetLibrary.filter { !managedBuiltInTemplates.contains($0) }
    }

    private var templateEditingMatchesSelection: Bool {
        editingTemplateSurface == selectedPresetTargetSurface && editingTemplateLayerID == selectedCustomLayerID
    }

    private var presetGrid: some View {
        VStack(spacing: 8) {
            ForEach(prominentBuiltInTemplates) { preset in
                presetButton(for: preset)
            }
        }
    }

    private var selectedPresetTargetSurface: KeyboardRowSurface {
        if let selectedCustomLayerID,
           let layer = settings.customKeymapLayers.first(where: { $0.id == selectedCustomLayerID }) {
            return layer.surface
        }

        switch keyboardEditorSurface {
        case .mainRow:
            return .mainRow
        case .letters:
            return .letters
        case .symbols1:
            return .symbols1
        case .symbols2:
            return .symbols2
        }
    }

    private func editTemplateCopy(_ preset: KeyboardLayoutPreset) {
        guard templateTargetCanBeEdited else { return }
        do {
            let copy = try settings.beginBuiltInTemplateEdit(preset)
            editManagedTemplate(copy.id)
        } catch {
            presentTemplateError("The template could not be saved. Check the 20-template library limit and try again.")
        }
    }

    private func cloneBuiltInTemplate(_ preset: KeyboardLayoutPreset) {
        do {
            _ = try settings.cloneBuiltInTemplate(preset)
            templateLibraryError = nil
        } catch {
            presentTemplateError("The template could not be cloned. Check the 20-template library limit and try again.")
        }
    }

    private func cloneManagedTemplate(_ id: UUID) {
        do {
            _ = try settings.cloneSavedPreset(id: id)
            templateLibraryError = nil
        } catch {
            presentTemplateError("The template could not be cloned. Check the 20-template library limit and try again.")
        }
    }

    private var templateTargetCanBeEdited: Bool {
        if selectedCustomLayerID == nil, selectedPresetTargetSurface == .letters, isABCEditingLocked {
            presentABCUnlockPrompt()
            return false
        }
        return true
    }

    private func editManagedTemplate(_ id: UUID) {
        guard templateTargetCanBeEdited else { return }
        guard let preset = settings.savedKeymapPresets.first(where: { $0.id == id }) else { return }
        if selectedCustomLayerID == nil, let transfer = preset.transferLayer,
           (transfer.kind == .mainRow) != (selectedPresetTargetSurface == .mainRow) {
            presentTemplateError("Choose a matching Row or Expanded layer, or a custom layer, before editing this template.")
            return
        }
        applySavedPresetToSelectedLayer(id)
        editingTemplateID = id
        editingTemplateSurface = selectedPresetTargetSurface
        editingTemplateLayerID = selectedCustomLayerID
        templateLibraryError = nil
    }

    private func saveTemplateEdits() {
        guard let editingTemplateID, templateEditingMatchesSelection else { return }
        do {
            try settings.saveEditedPreset(id: editingTemplateID, from: editingTemplateSurface, customLayerID: editingTemplateLayerID)
            templateLibraryError = nil
            self.editingTemplateID = nil
        } catch {
            presentTemplateError("Template changes could not be saved. Your previous saved version is still available.")
        }
    }

    private func presentTemplateError(_ message: String) {
        templateLibraryError = message
        keymapImportResultTitle = "Template Library"
        keymapImportResultMessage = message
        showsKeymapImportResult = true
    }

    private func applySavedPresetToSelectedLayer(_ presetID: UUID) {
        if selectedCustomLayerID == nil,
           selectedPresetTargetSurface == .letters,
           isABCEditingLocked {
            presentABCUnlockPrompt()
            return
        }
        settings.applySavedPreset(
            id: presetID,
            to: selectedPresetTargetSurface,
            customLayerID: selectedCustomLayerID
        )
        if let selectedCustomLayerID,
           let layer = settings.customKeymapLayers.first(where: { $0.id == selectedCustomLayerID }) {
            isKeyboardEditorExpanded = layer.style == .expanded
        }
        syncKeyShelfSectionSelection()
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
    }

    private func cardContainer(content: AnyView) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
    }

    private func presetLibraryRow(title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            Image(systemName: "ellipsis")
        }
        .foregroundColor(.white)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(buttonSurface(fill: buttonBackgroundFill))
        .overlay(buttonSurfaceStroke(Color(red: 0.24, green: 0.24, blue: 0.26)))
    }

    private func presetButton(for preset: KeyboardLayoutPreset) -> some View {
        Menu {
            Button("Edit") { editTemplateCopy(preset) }
            Button("Clone") { cloneBuiltInTemplate(preset) }
        } label: {
            presetLibraryRow(title: preset.title)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("keymap.template.\(preset.rawValue)")
        .accessibilityLabel("\(preset.title) template")
    }

    private func themeButton(for theme: CompanionAppTheme) -> some View {
        let isSelected = theme == settings.appTheme
        let buttonBackground = theme.usesDarkChrome ? darkThemeThemeCardFill : (isSelected ? selectedAccentFill : buttonBackgroundFill)
        let buttonBorder = theme.usesDarkChrome
            ? (isSelected ? darkThemeReferenceAccentColor.opacity(0.72) : darkThemeSectionBorder)
            : (isSelected ? selectedAccentBorderColor : previewTileBorder)

        return Button(action: {
            settings.applyThemeProfile(theme)
        }) {
            let label = VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: themeSymbol(for: theme))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(
                            theme.usesDarkChrome
                                ? (isSelected ? darkThemeReferenceAccentColor : subtleTextColor)
                                : (isSelected ? .white : tabAccentColor)
                        )

                    Spacer(minLength: 8)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(theme.usesDarkChrome ? darkThemeReferenceAccentColor : Color.white.opacity(0.94))
                    }
                }

                Text(theme.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                themeButtonPreview(for: theme)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)

            label
                .background(buttonSurface(fill: buttonBackground))
                .overlay(
                    buttonSurfaceStroke(buttonBorder)
                )
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private var customThemePreview: some View {
        let style = settings.customKeyStyle.normalized
        let shape = RoundedRectangle(cornerRadius: CGFloat(style.cornerRadius), style: .continuous)

        return HStack(spacing: 10) {
            ForEach(["Q", "W", "E"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(customPreviewTextColor(for: style))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        shape
                            .fill(customPreviewFillColor(for: style))
                            .overlay(shape.stroke(customPreviewBorderColor(for: style), lineWidth: 1))
                            .shadow(
                                color: Color.black.opacity(Double(style.shadowDepth) * 0.045),
                                radius: CGFloat(style.shadowDepth),
                                x: 0,
                                y: CGFloat(style.shadowDepth) * 0.45
                            )
                    )
            }
        }
        .padding(12)
        .background(secondaryCardFill)
        .overlay(buttonSurfaceStroke(previewTileBorder))
    }

    private var customKeyFillBinding: Binding<KeyboardCustomKeyFill> {
        Binding(
            get: { settings.customKeyStyle.keyFill },
            set: { nextFill in
                updateCustomKeyStyle { $0.keyFill = nextFill }
            }
        )
    }

    private func customKeyStyleIntBinding(
        _ keyPath: WritableKeyPath<KeyboardCustomKeyStyle, Int>
    ) -> Binding<Int> {
        Binding(
            get: { settings.customKeyStyle[keyPath: keyPath] },
            set: { nextValue in
                updateCustomKeyStyle { $0[keyPath: keyPath] = nextValue }
            }
        )
    }

    private func customKeyStyleBoolBinding(
        _ keyPath: WritableKeyPath<KeyboardCustomKeyStyle, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings.customKeyStyle[keyPath: keyPath] },
            set: { nextValue in
                updateCustomKeyStyle { $0[keyPath: keyPath] = nextValue }
            }
        )
    }

    private func updateCustomKeyStyle(_ update: (inout KeyboardCustomKeyStyle) -> Void) {
        var style = settings.customKeyStyle
        update(&style)
        settings.customKeyStyle = style.normalized
    }

    private func customPreviewFillColor(for style: KeyboardCustomKeyStyle) -> Color {
        switch style.keyFill {
        case .graphite:
            return Color(red: 0.18, green: 0.18, blue: 0.19)
        case .ink:
            return Color(red: 0.09, green: 0.09, blue: 0.10)
        case .paper:
            return Color.white.opacity(0.95)
        case .accent:
            return palettePrimaryColor.opacity(0.82)
        case .adaptive:
            return customPreviewAdaptiveIsLightSurface ? Color.white.opacity(0.92) : Color(red: 0.20, green: 0.20, blue: 0.21)
        }
    }

    private func customPreviewTextColor(for style: KeyboardCustomKeyStyle) -> Color {
        let alpha = Double(style.textBrightness) / 100
        switch style.keyFill {
        case .paper:
            return Color.black.opacity(alpha)
        case .adaptive where customPreviewAdaptiveIsLightSurface:
            return Color.black.opacity(alpha)
        default:
            return Color.white.opacity(alpha)
        }
    }

    private func customPreviewBorderColor(for style: KeyboardCustomKeyStyle) -> Color {
        Color.white.opacity(Double(style.borderStrength) / 100)
    }

    private var customPreviewAdaptiveIsLightSurface: Bool {
        settings.customKeyStyle.followsHostAppearance && colorScheme != .dark
    }

    private var accentMixerPreview: some View {
        let palette = settings.accentPalette

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(palette.isMixed ? "Custom Accent" : "Base Accent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(subtleTextColor)

                    Text(palette.statusTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if palette.isMixed {
                    compactOutlineButton("Reset Mix", systemImage: "arrow.counterclockwise") {
                        settings.accentPalette = KeyboardAccentPalette([palette.components.first ?? .blue])
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    accentSlotCard(at: index)
                }
            }

            HStack(spacing: 6) {
                let swatches = paletteSwatches(for: palette)
                ForEach(swatches.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(swatches[index])
                        .frame(height: 18)
                }
            }
        }
        .padding(14)
        .background(buttonSurface(fill: selectedAccentFill))
        .overlay(buttonSurfaceStroke(selectedAccentBorderColor))
    }

    private func accentSlotCard(at index: Int) -> some View {
        let tone = index < settings.accentPalette.components.count ? settings.accentPalette.components[index] : nil
        let slotTitle = accentSlotTitle(for: index)
        let fillColor = tone.map { color(from: $0.primaryUIColor) } ?? buttonBackgroundFill

        return VStack(alignment: .leading, spacing: 8) {
            Text(slotTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(subtleTextColor)

            HStack(spacing: 8) {
                Circle()
                    .fill(fillColor)
                    .frame(width: 14, height: 14)

                Text(tone?.shortTitle ?? "Open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(
            buttonSurface(fill: tone == nil ? buttonBackgroundFill : accentFill)
        )
        .overlay(
            buttonSurfaceStroke(
                tone == nil ? previewTileBorder : tabAccentColor.opacity(0.42)
            )
        )
    }

    private func accentToneButton(for tone: KeyboardAccentTone) -> some View {
        let selectionIndex = settings.accentPalette.selectionIndex(of: tone)
        let isSelected = selectionIndex != nil

        return Button(action: {
            settings.accentPalette = settings.accentPalette.toggling(tone)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(from: tone.primaryUIColor))
                        .frame(width: 16, height: 16)

                    Spacer(minLength: 0)

                    if let selectionIndex {
                        Text("\(selectionIndex)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(tabAccentColor))
                    }
                }

                Text(tone.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(isSelected ? accentSlotTitle(for: selectionIndex! - 1) : "Tap to add")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(subtleTextColor)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                buttonSurface(fill: isSelected ? selectedAccentFill : buttonBackgroundFill)
            )
            .overlay(
                buttonSurfaceStroke(
                    isSelected ? selectedAccentBorderColor : previewTileBorder
                )
            )
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private func accentSlotTitle(for index: Int) -> String {
        switch index {
        case 0:
            return "Lead"
        case 1:
            return "Depth"
        default:
            return "Glow"
        }
    }

    @ViewBuilder
    private func previewRowSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            content()
        case .dark:
            content()
                .background(darkThemeRowFill)
        }
    }

    @ViewBuilder
    private func themeButtonPreview(for theme: CompanionAppTheme) -> some View {
        switch theme {
        case .classic:
            EmptyView()
        case .dark:
            EmptyView()
        case .chameleon:
            EmptyView()
        case .custom:
            EmptyView()
        }
    }

    private func darkThemePreviewKeyboard(compact: Bool) -> some View {
        let topRow = previewDisplayedValues(for: settings.defaultSymbolLayer ? .symbolTop : .letterTop)
        let middleRow = previewDisplayedValues(for: settings.defaultSymbolLayer ? .symbolMiddle : .letterMiddle)
        let bottomRow = previewDisplayedValues(for: settings.defaultSymbolLayer ? .symbolBottom : .letterBottom)

        return VStack(spacing: 0) {
            darkThemePreviewToolbarRow(compact: compact)
            darkThemePreviewLetterRow(
                values: topRow,
                compact: compact,
                row: .letterTop
            )
            .padding(.horizontal, settings.defaultSymbolLayer ? 0 : classicPreviewLetterTopInset)
            darkThemePreviewLetterRow(
                values: middleRow,
                compact: compact,
                row: .letterMiddle
            )
            .padding(.horizontal, settings.defaultSymbolLayer ? 0 : classicPreviewLetterMiddleInset)
            darkThemePreviewBottomLetterRow(values: bottomRow, compact: compact)
                .padding(.horizontal, settings.defaultSymbolLayer ? 0 : classicPreviewBottomInset)
            darkThemePreviewUtilityRow(compact: compact)
        }
    }

    private func darkThemePreviewToolbarRow(compact: Bool) -> some View {
        HStack(spacing: 0) {
            darkThemeThemeSegment(icon: "mic.fill", compact: compact)
            darkThemeThemeSegment(icon: "face.smiling", compact: compact)
            darkThemeThemeSegment(icon: "keyboard", compact: compact, accent: true, showsGear: true)
            darkThemeThemeSegment(text: "AB|c", compact: compact)
            darkThemeThemeSegment(icon: "doc.on.clipboard", compact: compact)
        }
    }

    private func darkThemePreviewLetterRow(
        values: [String],
        compact: Bool,
        row: KeyboardRowKind
    ) -> some View {
        let widths = previewLetterRowWidths(values: values, row: row)

        return HStack(spacing: 0) {
            ForEach(values.indices, id: \.self) { index in
                darkThemeThemeSegment(
                    text: previewDisplayText(values[index]),
                    compact: compact,
                    fill: Color(red: 0.15, green: 0.15, blue: 0.16),
                    textColor: .white.opacity(0.97),
                    fontSize: compact ? 16 : 28,
                    weight: .light,
                    width: widths[index],
                    contentAlignment: previewDarkPrimaryAlignment(for: row, index: index),
                    textOffsetX: previewDarkPrimaryOffset(for: row, index: index)
                )
            }
        }
    }

    private func darkThemePreviewBottomLetterRow(values: [String], compact: Bool) -> some View {
        let spans = values.map { previewLetterWidthSpan(for: $0, row: .letterBottom) }
        let totalUnits = max(1, spans.reduce(CGFloat(1), +))
        let unitWidth = (CGFloat(values.count) + 1) * 32 / totalUnits
        let deleteWidth = unitWidth
        let widths = spans.map { unitWidth * $0 }

        return HStack(spacing: 0) {
            darkThemeThemeSegment(
                icon: "delete.forward.fill",
                compact: compact,
                fill: Color(red: 0.14, green: 0.14, blue: 0.15),
                textColor: .white.opacity(0.97),
                iconColor: .white.opacity(0.97),
                fontSize: compact ? 15 : 24,
                width: deleteWidth
            )
            ForEach(values.indices, id: \.self) { index in
                darkThemeThemeSegment(
                    text: previewDisplayText(values[index]),
                    compact: compact,
                    fill: Color(red: 0.14, green: 0.14, blue: 0.15),
                    textColor: .white.opacity(0.97),
                    fontSize: compact ? 16 : 28,
                    weight: .light,
                    width: widths[index],
                    contentAlignment: previewDarkPrimaryAlignment(for: .letterBottom, index: index),
                    textOffsetX: previewDarkPrimaryOffset(for: .letterBottom, index: index)
                )
            }
        }
    }

    private func previewLetterRowWidths(
        values: [String],
        row: KeyboardRowKind,
        totalWidth: CGFloat? = nil,
        spacing: CGFloat = 0
    ) -> [CGFloat] {
        let resolvedTotalWidth = totalWidth ?? {
            switch row {
            case .letterTop:
                return 10 * 32
            case .letterMiddle:
                return 10 * 32
            case .letterBottom:
                return 9 * 32
            default:
                return CGFloat(values.count) * 32
            }
        }()
        let spans = values.map { value in
            previewLetterWidthSpan(for: value, row: row)
        }
        let totalUnits = spans.reduce(CGFloat.zero, +)
        guard totalUnits > 0 else { return Array(repeating: 0, count: values.count) }

        let totalSpacing = CGFloat(max(values.count - 1, 0)) * spacing
        let unitWidth = max(0, (resolvedTotalWidth - totalSpacing) / totalUnits)
        return spans.map { unitWidth * $0 }
    }

    private func previewLetterWidthSpan(for value: String, row: KeyboardRowKind) -> CGFloat {
        guard (row == .letterMiddle || row == .letterBottom),
              KeyboardSpecialKeyAction.resolved(from: value) == .enter else {
            return 1
        }

        return 1.18
    }

    private func darkThemePreviewUtilityRow(compact: Bool) -> some View {
        HStack(spacing: 0) {
            darkThemeThemeSegment(
                text: settings.defaultSymbolLayer ? "ABC" : "123",
                compact: compact,
                fill: Color(red: 0.09, green: 0.09, blue: 0.10),
                textColor: .white.opacity(0.97),
                fontSize: compact ? 15 : 22,
                width: compact ? 42 : 86
            )
            if settings.defaultSymbolLayer {
                darkThemeThemeSegment(
                    text: "Tab",
                    compact: compact,
                    fill: Color(red: 0.09, green: 0.09, blue: 0.10),
                    textColor: subtleTextColor,
                    fontSize: compact ? 14 : 22,
                    width: compact ? 34 : 64
                )
                darkThemeThemeSegment(
                    icon: "arrow.left",
                    compact: compact,
                    fill: Color(red: 0.09, green: 0.09, blue: 0.10),
                    textColor: subtleTextColor,
                    iconColor: subtleTextColor,
                    fontSize: compact ? 14 : 22,
                    width: compact ? 34 : 64
                )
            } else {
                darkThemeThemeSegment(
                    text: previewShiftLabel,
                    icon: "shift.fill",
                    compact: compact,
                    fill: Color(red: 0.09, green: 0.09, blue: 0.10),
                    textColor: subtleTextColor,
                    iconColor: subtleTextColor,
                    fontSize: previewShiftLabel == nil ? (compact ? 14 : 22) : (compact ? 7 : 11),
                    width: compact ? 34 : 64
                )
            }
            darkThemeThemeSegment(
                text: previewSpaceLabel,
                compact: compact,
                fill: Color(red: 0.15, green: 0.15, blue: 0.16),
                textColor: subtleTextColor,
                fontSize: previewSpaceLabel == nil ? (compact ? 16 : 24) : (compact ? 8 : 12),
                width: nil
            )
            if settings.defaultSymbolLayer {
                darkThemeThemeSegment(
                    text: previewReturnLabel,
                    icon: "return.left",
                    compact: compact,
                    fill: Color(red: 0.15, green: 0.15, blue: 0.16),
                    textColor: .white.opacity(0.97),
                    iconColor: .white.opacity(0.97),
                    fontSize: previewReturnLabel == nil ? (compact ? 16 : 24) : (compact ? 7 : 10),
                    width: compact ? 46 : 92
                )
            }
            if !settings.defaultSymbolLayer {
                darkThemeThemeSegment(
                    text: previewDeleteLabel,
                    icon: "delete.backward.fill",
                    compact: compact,
                    fill: Color(red: 0.09, green: 0.09, blue: 0.10),
                    textColor: .white.opacity(0.97),
                    iconColor: .white.opacity(0.97),
                    fontSize: previewDeleteLabel == nil ? (compact ? 16 : 24) : (compact ? 7 : 10),
                    width: compact ? 40 : 72
                )
            } else {
                darkThemeThemeSegment(
                    icon: "arrow.right",
                    compact: compact,
                    fill: Color(red: 0.09, green: 0.09, blue: 0.10),
                    textColor: .white.opacity(0.97),
                    iconColor: .white.opacity(0.97),
                    fontSize: compact ? 16 : 24,
                    width: compact ? 40 : 72
                )
            }
            darkThemeThemeSegment(
                icon: "chevron.down",
                compact: compact,
                fill: Color(red: 0.41, green: 0.17, blue: 0.12),
                textColor: .white.opacity(0.97),
                iconColor: .white.opacity(0.97),
                fontSize: compact ? 16 : 24,
                iconFontSize: settings.showControlLabels ? (compact ? 9 : 17) : nil,
                width: compact ? 34 : 60
            )
        }
    }

    private func darkThemeThemeSegment(
        text: String? = nil,
        icon: String? = nil,
        trailingIcon: String? = nil,
        compact: Bool,
        accent: Bool = false,
        showsGear: Bool = false,
        fill: Color? = nil,
        textColor: Color? = nil,
        iconColor: Color? = nil,
        fontSize: CGFloat? = nil,
        iconFontSize: CGFloat? = nil,
        weight: Font.Weight = .regular,
        width: CGFloat? = nil,
        contentAlignment: Alignment = .center,
        textOffsetX: CGFloat = 0
    ) -> some View {
        let cellFill = fill ?? Color(red: 0.16, green: 0.16, blue: 0.17)
        let labelColor = textColor ?? (accent ? darkThemeReferenceAccentColor : previewTextColor)
        let symbolColor = iconColor ?? (accent ? darkThemeReferenceAccentColor : subtleTextColor)
        let cellHeight: CGFloat = compact ? 24 : 56

        return ZStack(alignment: .trailing) {
            Rectangle()
                .fill(cellFill)

            Rectangle()
                .fill(darkThemeRowBorder)
                .frame(width: 1)

            Group {
                if let icon {
                    if let text {
                        VStack(spacing: compact ? 1 : 2) {
                            HStack(spacing: compact ? 5 : 14) {
                                Image(systemName: icon)
                                    .font(.system(size: iconFontSize ?? (compact ? 9 : 17), weight: .regular))
                                if let trailingIcon {
                                    Image(systemName: trailingIcon)
                                        .font(.system(size: iconFontSize ?? (compact ? 9 : 17), weight: .regular))
                                }
                            }

                            Text(text)
                                .font(.system(size: fontSize ?? (compact ? 15 : 24), weight: weight))
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .padding(.horizontal, compact ? 1 : 2)
                        }
                        .foregroundColor(symbolColor)
                    } else {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: icon)
                                .font(.system(size: iconFontSize ?? (compact ? 11 : 23), weight: .regular))
                                .foregroundColor(symbolColor)

                            if showsGear {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: compact ? 5 : 9, weight: .bold))
                                    .foregroundColor(subtleTextColor)
                                    .offset(x: compact ? 5 : 9, y: compact ? -4 : -7)
                            }
                        }
                    }
                } else if let text {
                    Text(text)
                        .font(.system(size: fontSize ?? (compact ? 13 : 18), weight: weight))
                        .foregroundColor(labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, compact ? 2 : 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
                        .offset(x: textOffsetX)
                }
            }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(height: cellHeight)
    }

    private func previewDarkPrimaryAlignment(for row: KeyboardRowKind, index: Int) -> Alignment {
        switch row {
        case .letterTop, .letterMiddle:
            return index <= 4 ? .topTrailing : .topLeading
        case .letterBottom:
            return index <= 3 ? .topTrailing : .topLeading
        default:
            return .center
        }
    }

    private func previewDarkPrimaryOffset(for row: KeyboardRowKind, index: Int) -> CGFloat {
        switch row {
        case .letterTop, .letterMiddle:
            return index > 4 ? -2 : 0
        case .letterBottom:
            return index > 3 ? -2 : 0
        default:
            return 0
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(subtleTextColor.opacity(0.9))
    }

    private var previewTileFill: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return settings.highContrastKeys
                ? Color(red: 0.08, green: 0.08, blue: 0.09)
                : Color(red: 0.17, green: 0.17, blue: 0.18)
        case .dark:
            return Color(red: 0.14, green: 0.14, blue: 0.14)
        }
    }

    private var previewToolbarSpacing: CGFloat {
        settings.appTheme.usesDarkChrome ? 0 : 4
    }

    private var previewQuickRowSpacing: CGFloat {
        settings.appTheme.usesDarkChrome ? 0 : 8
    }

    private var previewRowSpacing: CGFloat {
        settings.appTheme.usesDarkChrome ? 0 : 5
    }

    private var darkPreviewBottomTrailingWidth: CGFloat {
        max(58, min(82, keyboardEditorToolbarHeight * 1.22))
    }

    private var mainRowMenuControlWidth: CGFloat {
        max(44, min(62, CGFloat(KeyboardLayoutBounds.clampedToolbarHeight(settings.toolbarHeight)) * 1.22))
    }

    private var previewTileCornerRadius: CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 9
        case .dark:
            return 0
        }
    }

    private var previewTileBorder: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return settings.highContrastKeys
                ? Color.white.opacity(0.36)
                : Color.white.opacity(0.10)
        case .dark:
            return darkThemeSectionBorder
        }
    }

    private var previewTextColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return settings.highContrastKeys
                ? Color.white
                : Color.white.opacity(0.92)
        case .dark:
            return Color.white.opacity(0.96)
        }
    }

    private var previewIconColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return settings.highContrastKeys
                ? Color.white.opacity(0.96)
                : Color.white.opacity(0.82)
        case .dark:
            return Color.white.opacity(0.66)
        }
    }

    private var backgroundColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color(red: 0.07, green: 0.08, blue: 0.09)
        case .dark:
            return Color(red: 0.05, green: 0.05, blue: 0.06)
        }
    }

    private func buttonSurface(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
            .fill(fill)
    }

    private func buttonSurfaceStroke(_ color: Color, lineWidth: CGFloat = 1) -> some View {
        RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
            .stroke(color, lineWidth: lineWidth)
    }

    private var secondaryCardFill: some View {
        buttonSurface(fill: buttonBackgroundFill)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(cardFillColor)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .stroke(cardStrokeColor, lineWidth: 0.5)
    }

    private var accentFill: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return palettePrimaryColor.opacity(0.28)
        case .dark:
            return darkThemeReferenceAccentColor.opacity(0.20)
        }
    }

    private var selectedAccentFill: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return palettePrimaryColor.opacity(0.16)
        case .dark:
            return darkThemeReferenceAccentColor.opacity(0.12)
        }
    }

    private var selectedAccentBorderColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return tabAccentColor.opacity(0.92)
        case .dark:
            return darkThemeReferenceAccentColor.opacity(0.76)
        }
    }

    private var mainRowSelectionFill: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color(red: 0.62, green: 0.40, blue: 0.08).opacity(0.42)
        case .dark:
            return Color(red: 0.62, green: 0.40, blue: 0.08).opacity(0.28)
        }
    }

    private var mainRowSelectionBorder: Color {
        Color(red: 0.94, green: 0.69, blue: 0.18)
    }

    private var accentBorder: some View {
        buttonSurfaceStroke(tabAccentColor)
    }

    private var subtleTextColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color.white.opacity(0.72)
        case .dark:
            return Color(red: 0.70, green: 0.70, blue: 0.70)
        }
    }

    private var buttonBackgroundFill: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color(red: 0.15, green: 0.15, blue: 0.17)
        case .dark:
            return Color(red: 0.11, green: 0.11, blue: 0.11)
        }
    }

    private var cardFillColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .dark:
            return Color(red: 0.08, green: 0.08, blue: 0.09)
        }
    }

    private var cardStrokeColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color.white.opacity(0.12)
        case .dark:
            return Color.white.opacity(0.09)
        }
    }

    private var cardCornerRadius: CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 12
        case .dark:
            return 1
        }
    }

    private var buttonCornerRadius: CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 10
        case .dark:
            return 1
        }
    }

    private var keyboardCanvasSurfaceCornerRadius: CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 12
        case .dark:
            return 1
        }
    }

    private var keyboardCanvasSurfaceBorderColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color.white.opacity(0.08)
        case .dark:
            return darkThemeKeyboardShellBorder
        }
    }

    private var keyboardCanvasTopSeparatorColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return .clear
        case .dark:
            return Color.white.opacity(0.18)
        }
    }

    private var keyboardCanvasBottomSeparatorColor: Color {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return .clear
        case .dark:
            return Color(red: 0.14, green: 0.14, blue: 0.15)
        }
    }

    private var darkThemeThemeCardFill: Color {
        Color(red: 0.09, green: 0.09, blue: 0.10)
    }

    private var darkThemeKeyboardShellFill: Color {
        Color(red: 0.08, green: 0.08, blue: 0.09)
    }

    private var darkThemeKeyboardShellBorder: Color {
        Color(red: 0.17, green: 0.17, blue: 0.18)
    }

    private var darkThemeRowFill: Color {
        Color(red: 0.11, green: 0.11, blue: 0.11)
    }

    private var darkThemeRowBorder: Color {
        Color(red: 0.21, green: 0.21, blue: 0.22)
    }

    private var darkThemeSectionBorder: Color {
        Color(red: 0.19, green: 0.19, blue: 0.20)
    }

    private var darkThemeReferenceAccentColor: Color {
        palettePrimaryColor
    }

    private var tabAccentColor: Color {
        palettePrimaryColor
    }

    private var palettePrimaryColor: Color {
        color(from: settings.accentPalette.primaryUIColor)
    }

    private var paletteSecondaryColor: Color {
        color(from: settings.accentPalette.secondaryUIColor)
    }

    private var paletteGlowColor: Color {
        color(from: settings.accentPalette.glowUIColor)
    }

    private func themeSymbol(for theme: CompanionAppTheme) -> String {
        switch theme {
        case .classic:
            return "square.grid.3x3.fill"
        case .dark:
            return "keyboard"
        case .chameleon:
            return "eyedropper.halffull"
        case .custom:
            return "slider.horizontal.3"
        }
    }

    private func paletteSwatches(for palette: KeyboardAccentPalette) -> [Color] {
        [
            color(from: palette.secondaryUIColor),
            color(from: palette.primaryUIColor),
            color(from: palette.glowUIColor),
        ]
    }

    private func color(from uiColor: UIColor) -> Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return Color(.sRGB, red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
        }

        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            return Color(.sRGB, red: Double(white), green: Double(white), blue: Double(white), opacity: Double(alpha))
        }

        return Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
    }
}

#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
private struct HardwareLabCaptureTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequestAt: Double
    let isEnabled: Bool
    let onKeyEvent: (KeyEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> HardwareLabCaptureUITextField {
        let field = HardwareLabCaptureUITextField(frame: .zero)
        field.placeholder = placeholder
        field.text = text
        field.isEnabled = isEnabled
        field.inputView = nil
        field.accessibilityIdentifier = "hardware-lab-capture-field"
        field.onKeyEvent = onKeyEvent
        field.onTextChange = { text in
            context.coordinator.parent.text = text
        }
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textColor = .white
        field.tintColor = .white
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: HardwareLabCaptureUITextField, context: Context) {
        context.coordinator.parent = self
        uiView.onKeyEvent = onKeyEvent
        uiView.isEnabled = isEnabled
        uiView.onTextChange = { text in
            context.coordinator.parent.text = text
        }
        if uiView.text != text {
            uiView.text = text
        }
        if !isEnabled, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        requestFocusIfNeeded(uiView, context: context)
    }

    private func requestFocusIfNeeded(_ uiView: HardwareLabCaptureUITextField, context: Context) {
        guard isEnabled else { return }
        guard focusRequestAt > 0 else { return }
        guard focusRequestAt != context.coordinator.handledFocusRequestAt else { return }
        context.coordinator.handledFocusRequestAt = focusRequestAt

        DispatchQueue.main.async {
            uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject {
        var parent: HardwareLabCaptureTextField
        var handledFocusRequestAt = 0.0

        init(_ parent: HardwareLabCaptureTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }
    }
}

private final class HardwareLabCaptureUITextField: UITextField {
    var onKeyEvent: ((KeyEvent) -> Void)?
    var onTextChange: ((String) -> Void)?
    private var hardwareInputGate = HardwareKeyboardTextInputGate()

    override func insertText(_ text: String) {
        guard hardwareInputGate.consumeInsertAllowance() else { return }
        super.insertText(text)
        notifyHardwareLabTextChange()
    }

    override func deleteBackward() {
        guard hardwareInputGate.consumeDeleteAllowance() else { return }
        super.deleteBackward()
        notifyHardwareLabTextChange()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        hardwareInputGate.arm(for: presses)
        recordPresses(presses, source: .pressesBegan, phase: .down, event: event)
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        recordPresses(presses, source: .pressesEnded, phase: .up, event: event)
        super.pressesEnded(presses, with: event)
        hardwareInputGate.end(for: presses)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        recordPresses(presses, source: .pressesEnded, phase: .up, event: event)
        super.pressesCancelled(presses, with: event)
        hardwareInputGate.end(for: presses)
    }

    private func recordPresses(
        _ presses: Set<UIPress>,
        source: KeyEventSource,
        phase: KeyPhase,
        event: UIPressesEvent?
    ) {
        for press in presses {
            guard let key = press.key else { continue }
            let flags = key.modifierFlags.union(event?.modifierFlags ?? [])
            onKeyEvent?(
                KeyEvent(
                    source: source,
                    phase: phase,
                    characters: normalizedHardwareCharacters(key.characters),
                    charactersIgnoringModifiers: normalizedHardwareCharacters(key.charactersIgnoringModifiers),
                    keyCode: Int(key.keyCode.rawValue),
                    modifiers: hardwareModifiers(from: flags),
                    isRepeat: false
                )
            )
        }
    }

    private func notifyHardwareLabTextChange() {
        onTextChange?(text ?? "")
    }

    private func normalizedHardwareCharacters(_ characters: String?) -> String? {
        guard let characters, !characters.isEmpty else { return nil }
        return characters
    }

    private func hardwareModifiers(from flags: UIKeyModifierFlags) -> Set<KeyModifier> {
        var modifiers = Set<KeyModifier>()

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.alternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.alphaShift) {
            modifiers.insert(.capsLock)
            modifiers.insert(.alphaShift)
        }
        if flags.contains(.numericPad) {
            modifiers.insert(.numericPad)
        }

        return modifiers
    }
}
#endif

private struct HardwareKeyboardTextInputGate {
    private static let allowanceDuration: TimeInterval = 0.20
    private var insertAllowanceExpiresAt = 0.0
    private var remainingInsertMutations = 0
    private var activeDeletePressIDs = Set<ObjectIdentifier>()

    mutating func arm(for presses: Set<UIPress>) {
        let eligibleInsertPressCount = presses.reduce(into: 0) { count, press in
            guard let key = press.key else { return }
            if Self.isDeleteKey(key) {
                activeDeletePressIDs.insert(ObjectIdentifier(press))
                return
            }
            guard Self.canInsertText(key) else { return }
            count += 1
        }
        guard eligibleInsertPressCount > 0 else { return }

        remainingInsertMutations = max(remainingInsertMutations, eligibleInsertPressCount)
        insertAllowanceExpiresAt = ProcessInfo.processInfo.systemUptime + Self.allowanceDuration
    }

    mutating func end(for presses: Set<UIPress>) {
        for press in presses {
            activeDeletePressIDs.remove(ObjectIdentifier(press))
        }
    }

    mutating func consumeInsertAllowance() -> Bool {
        guard remainingInsertMutations > 0,
              ProcessInfo.processInfo.systemUptime <= insertAllowanceExpiresAt else {
            remainingInsertMutations = 0
            insertAllowanceExpiresAt = 0
            return false
        }

        remainingInsertMutations -= 1
        return true
    }

    func consumeDeleteAllowance() -> Bool {
        !activeDeletePressIDs.isEmpty
    }

    private static func isDeleteKey(_ key: UIKey) -> Bool {
        switch key.keyCode {
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward:
            return true
        default:
            return false
        }
    }

    private static func canInsertText(_ key: UIKey) -> Bool {
        !key.characters.isEmpty
    }
}

#if !HWC_INTERNAL_BUILD && !HWC_HARDWARE_CAPTURE
private struct HardwareKeyboardOnlyTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> HardwareKeyboardOnlyUITextField {
        let field = HardwareKeyboardOnlyUITextField(frame: .zero)
        field.placeholder = placeholder
        field.text = text
        field.isEnabled = isEnabled
        field.inputView = nil
        field.accessibilityIdentifier = "hardware-keyboard-test-field"
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textColor = .white
        field.tintColor = .white
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: HardwareKeyboardOnlyUITextField, context: Context) {
        context.coordinator.parent = self
        uiView.isEnabled = isEnabled
        if uiView.text != text {
            uiView.text = text
        }
        if !isEnabled, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject {
        var parent: HardwareKeyboardOnlyTextField

        init(_ parent: HardwareKeyboardOnlyTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }
    }
}

private final class HardwareKeyboardOnlyUITextField: UITextField {
    private var hardwareInputGate = HardwareKeyboardTextInputGate()

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        hardwareInputGate.arm(for: presses)
        super.pressesBegan(presses, with: event)
    }

    override func insertText(_ text: String) {
        guard hardwareInputGate.consumeInsertAllowance() else { return }
        super.insertText(text)
    }

    override func deleteBackward() {
        guard hardwareInputGate.consumeDeleteAllowance() else { return }
        super.deleteBackward()
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        hardwareInputGate.end(for: presses)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesCancelled(presses, with: event)
        hardwareInputGate.end(for: presses)
    }
}
#endif
