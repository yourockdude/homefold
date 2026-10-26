import SwiftUI

/// Что создаём голосом.
enum VoiceTarget {
    case shopping, task

    var title: String { self == .shopping ? "Список голосом" : "Дело голосом" }

    var example: String {
        switch self {
        case .shopping: "молоко два литра, хлеб, яйца десять штук и яблоки килограмм"
        case .task: "завтра в 18:30 забрать Соню с танцев, напомнить за час"
        }
    }
}

/// Дело, разобранное из фразы, для формы создания.
struct VoiceTaskResult: Hashable {
    var draft: TaskDraft
    /// Что не удалось применить (например, повтор на бесплатном тарифе).
    var note: String?
}

/// Лист голосового ввода: слушает, показывает текст (его можно править), разбирает фразу.
/// Покупки проверяются тут же списком, дело открывается в обычной форме с заполненными полями.
struct VoiceCaptureSheet: View {
    let target: VoiceTarget
    let members: [MemberRecord]
    let currentUserId: UUID?
    var onShopping: ([ParsedShoppingItem]) -> Void = { _ in }
    var onTask: (ParsedTask) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var capture = SpeechCapture(engine: SpeechEngines.make())
    @State private var phase: Phase = .capture
    @State private var items: [ParsedShoppingItem] = []
    @State private var nothingRecognized = false
    @FocusState private var textFocused: Bool

    private enum Phase { case capture, review }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch phase {
                case .capture: captureView
                case .review: reviewView
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(RYColor.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RYColor.background)
        .presentationCornerRadius(RYRadius.sheet)
        .task {
            capture.onFinished = { finish() }
            await capture.start()
        }
        .onDisappear { capture.stop() }
        .onChange(of: capture.transcript) { _, _ in nothingRecognized = false }
        .sensoryFeedback(.impact(weight: .light), trigger: capture.isListening)
    }

    private var topBar: some View {
        ZStack {
            Text(target.title).ryFont(.headline).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            HStack {
                Button("Отмена") { capture.stop(); dismiss() }
                    .ryFont(.body).foregroundStyle(RYColor.accent).accessibilityIdentifier("voice.cancel")
                Spacer()
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 22).padding(.bottom, 10)
    }

    // MARK: Запись

    private var captureView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            microphone
            statusText
            transcriptField
            Text("Например: «\(target.example)»")
                .ryFont(.caption).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            if nothingRecognized {
                RYNotice(systemImage: "questionmark.circle", title: "Ничего не разобрали",
                         text: "Назовите, что купить: «молоко, хлеб, яйца десять штук».")
            }
            if let notice { notice }
            Spacer(minLength: 0)
            Button(action: finish) { Text(target == .shopping ? "Разобрать список" : "Создать дело") }
                .buttonStyle(.ryPrimary)
                .disabled(trimmed.isEmpty)
                .accessibilityIdentifier("voice.done")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.bottom, 12)
    }

    private var trimmed: String { capture.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var microphone: some View {
        Button {
            if capture.isListening { capture.stop() } else { Task { await capture.start() } }
        } label: {
            ZStack {
                Circle().fill(RYColor.accentFill.opacity(0.14))
                    .frame(width: 150, height: 150)
                    .scaleEffect(capture.isListening ? 1 + CGFloat(capture.level) * 0.35 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: capture.level)
                Circle().fill(RYColor.accentFill.opacity(0.22)).frame(width: 118, height: 118)
                Circle().fill(RYColor.accentFill).frame(width: 88, height: 88)
                Image(systemName: capture.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 32, weight: .regular)).foregroundStyle(RYColor.onAccent)
                    .symbolEffect(.variableColor.iterative, isActive: capture.isListening && !reduceMotion)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(capture.isListening ? "Остановить запись" : "Начать запись")
        .accessibilityIdentifier("voice.mic")
    }

    private var statusText: some View {
        Text(statusMessage).ryFont(.callout).foregroundStyle(RYColor.muted)
            .accessibilityIdentifier("voice.status")
    }

    private var statusMessage: String {
        switch capture.state {
        case .requesting: "Запрашиваем доступ…"
        case .listening: "Слушаю…"
        case .idle: trimmed.isEmpty ? "Нажмите на микрофон и говорите" : "Проверьте текст"
        case .denied, .restricted, .unavailable, .failed: "Можно ввести текст вручную"
        }
    }

    private var transcriptField: some View {
        TextField("Скажите или напишите", text: $capture.transcript, axis: .vertical)
            .lineLimit(3...6)
            .focused($textFocused)
            .ryFont(.body).foregroundStyle(RYColor.ink)
            .ryField(isFocused: textFocused)
            .accessibilityIdentifier("voice.transcript")
    }

    private var notice: AnyView? {
        switch capture.state {
        case .denied:
            AnyView(VStack(spacing: 10) {
                RYNotice(systemImage: "mic.slash", title: "Нет доступа к микрофону",
                         text: "Разрешите микрофон и распознавание речи в настройках — или введите текст вручную.")
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.rySecondary).accessibilityIdentifier("voice.settings")
            })
        case .restricted:
            AnyView(RYNotice(systemImage: "mic.slash", title: "Голосовой ввод ограничен",
                             text: "Распознавание речи на этом устройстве запрещено настройками. Введите текст вручную."))
        case .unavailable:
            AnyView(RYNotice(systemImage: "waveform.slash", title: "Распознавание речи недоступно",
                             text: "Сейчас оно не работает (нужна сеть или русский язык диктовки). Введите текст вручную."))
        case .failed:
            AnyView(RYNotice(systemImage: "exclamationmark.triangle", title: "Не удалось начать запись",
                             text: "Попробуйте ещё раз или введите текст вручную.", tint: RYColor.danger.opacity(0.12), ink: RYColor.danger))
        default:
            nil
        }
    }

    // MARK: Проверка списка

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Проверьте список").ryFont(.section).foregroundStyle(RYColor.ink)
            ScrollView {
                RYListGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RYListDivider() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).ryFont(.body).foregroundStyle(RYColor.ink)
                                Text("\(ShoppingFormat.quantity(item.quantity)) \(item.unit.rawValue) · \(item.category.rawValue)")
                                    .ryFont(.subhead).foregroundStyle(RYColor.muted)
                            }
                            Spacer()
                            Button { items.removeAll { $0.id == item.id } } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 22)).foregroundStyle(RYColor.danger.opacity(0.85))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Убрать: \(item.name)")
                            .accessibilityIdentifier("voice.remove.\(index)")
                        }
                        .frame(minHeight: 58)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("voice.item.\(index)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 8) {
                Button { onShopping(items); dismiss() } label: {
                    Text(items.isEmpty ? "Список пуст" : "Добавить \(items.count) \(ShoppingFormatBridge.goods(items.count))")
                }
                .buttonStyle(.ryPrimary).disabled(items.isEmpty)
                .accessibilityIdentifier("voice.confirm")
                Button("Назад к записи") { phase = .capture }
                    .buttonStyle(.ryLink).frame(minHeight: 36).accessibilityIdentifier("voice.back")
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.bottom, 12)
    }

    // MARK: Действия

    private func finish() {
        capture.stop()
        guard !trimmed.isEmpty, phase == .capture else { return }
        switch target {
        case .shopping:
            let parsed = VoiceShoppingParser.parse(trimmed)
            nothingRecognized = parsed.isEmpty
            guard !parsed.isEmpty else { return }
            items = parsed
            withAnimation(reduceMotion ? nil : RYMotion.smooth) { phase = .review }
        case .task:
            let parsed = VoiceTaskParser.parse(trimmed, now: .now, calendar: .current,
                                               members: members.map { ($0.id, $0.displayName) }, currentUserId: currentUserId)
            onTask(parsed)
            dismiss()
        }
    }
}
