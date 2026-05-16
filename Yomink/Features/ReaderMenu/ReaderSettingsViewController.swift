import UIKit

final class ReaderSettingsViewController: UIViewController {
    var onApply: ((ReadingSettings) -> Void)?

    private enum DetailMode: Int {
        case pageTurn
        case typography
        case more
    }

    private enum NumericField: Hashable {
        case fontSize
        case characterSpacing
        case lineSpacing
        case paragraphSpacing
        case topInset
        case bottomInset
        case leftInset
        case rightInset
        case bodyFontWeight
        case firstLineIndent
        case titleCharacterSpacing
        case titleLineSpacing
        case titleParagraphSpacing
        case titleFontWeight
        case titleFontSizeDelta
        case widgetLeftInset
        case widgetRightInset
        case widgetBottomInset
        case widgetTitleTopInset
        case widgetTitleLeftInset
    }

    private var pendingSettings: ReadingSettings
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let detailStack = UIStackView()
    private let themeControl = UISegmentedControl(items: ReadingTheme.allCases.map(\.displayName))
    private let detailModeControl = UISegmentedControl(
        items: [
            "\u{7FFB}\u{9875}",
            "\u{6392}\u{7248}",
            "\u{66F4}\u{591A}"
        ]
    )
    private let pageTurnControl = UISegmentedControl(
        items: ReadingPageTurnMode.allCases.map(\.displayName)
    )
    private let layoutDensityControl = UISegmentedControl(
        items: ReadingLayoutDensity.allCases.map(\.displayName)
    )
    private let keepAwakeSwitch = UISwitch()
    private let homeIndicatorSwitch = UISwitch()
    private let swipeBackSwitch = UISwitch()
    private var numericFields: [NumericField: UITextField] = [:]
    private var statusSwitches: [ReadingStatusBarItem: UISwitch] = [:]

    init(settings: ReadingSettings) {
        self.pendingSettings = settings.normalized()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = YominkTheme.background
        title = "\u{9605}\u{8BFB}\u{8BBE}\u{7F6E}"
        configureNavigationItems()
        configureControls()
        configureLayout()
        refreshControlValues()
        rebuildDetailLayer()
    }

    private func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "\u{5E94}\u{7528}",
            style: .done,
            target: self,
            action: #selector(apply)
        )
    }

    private func configureControls() {
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)
        detailModeControl.selectedSegmentIndex = DetailMode.pageTurn.rawValue
        detailModeControl.addTarget(self, action: #selector(detailModeChanged), for: .valueChanged)
        pageTurnControl.addTarget(self, action: #selector(pageTurnChanged), for: .valueChanged)
        layoutDensityControl.addTarget(self, action: #selector(layoutDensityChanged), for: .valueChanged)

        keepAwakeSwitch.addAction(
            UIAction { [weak self] _ in
                guard let self else {
                    return
                }
                pendingSettings.keepScreenAwake = keepAwakeSwitch.isOn
            },
            for: .valueChanged
        )
        homeIndicatorSwitch.addAction(
            UIAction { [weak self] _ in
                guard let self else {
                    return
                }
                pendingSettings.autoHideHomeIndicator = homeIndicatorSwitch.isOn
            },
            for: .valueChanged
        )
        swipeBackSwitch.addAction(
            UIAction { [weak self] _ in
                guard let self else {
                    return
                }
                pendingSettings.allowsSwipeBack = swipeBackSwitch.isOn
            },
            for: .valueChanged
        )
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 20,
            leading: 20,
            bottom: 24,
            trailing: 20
        )
        scrollView.addSubview(contentStack)

        detailStack.axis = .vertical
        detailStack.spacing = 14

        contentStack.addArrangedSubview(makeSectionLabel("\u{5B57}\u{4F53}\u{4E0E}\u{4E3B}\u{9898}"))
        contentStack.addArrangedSubview(makeNumericRow(
            title: "\u{5B57}\u{53F7}",
            field: .fontSize,
            range: ReadingSettings.fontSizeRange
        ))
        contentStack.addArrangedSubview(makeSegmentedRow(
            title: "\u{4E3B}\u{9898}",
            control: themeControl
        ))
        contentStack.addArrangedSubview(makeSectionLabel("\u{5FEB}\u{6377}\u{8BBE}\u{7F6E}"))
        contentStack.addArrangedSubview(detailModeControl)
        contentStack.addArrangedSubview(detailStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func rebuildDetailLayer() {
        removeArrangedSubviews(from: detailStack)
        numericFields = numericFields.filter { $0.key == .fontSize }
        statusSwitches.removeAll()

        switch currentDetailMode {
        case .pageTurn:
            detailStack.addArrangedSubview(makeSegmentedRow(
                title: "\u{7FFB}\u{9875}\u{65B9}\u{5F0F}",
                control: pageTurnControl
            ))
        case .typography:
            detailStack.addArrangedSubview(makeSegmentedRow(
                title: "\u{6392}\u{7248}\u{5BC6}\u{5EA6}",
                control: layoutDensityControl
            ))
            detailStack.addArrangedSubview(makeSectionLabel("\u{6B63}\u{6587}"))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{5B57}\u{95F4}\u{8DDD}",
                field: .characterSpacing,
                range: ReadingSettings.characterSpacingRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{884C}\u{8DDD}",
                field: .lineSpacing,
                range: ReadingSettings.lineSpacingRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{6BB5}\u{8DDD}",
                field: .paragraphSpacing,
                range: ReadingSettings.paragraphSpacingRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{4E0A}\u{8FB9}\u{8DDD}",
                field: .topInset,
                range: ReadingSettings.verticalInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{4E0B}\u{8FB9}\u{8DDD}",
                field: .bottomInset,
                range: ReadingSettings.verticalInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{5DE6}\u{8FB9}\u{8DDD}",
                field: .leftInset,
                range: ReadingSettings.horizontalInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{53F3}\u{8FB9}\u{8DDD}",
                field: .rightInset,
                range: ReadingSettings.horizontalInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{5B57}\u{4F53}\u{7C97}\u{7EC6}",
                field: .bodyFontWeight,
                range: ReadingSettings.fontWeightRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{9996}\u{884C}\u{7F29}\u{8FDB}",
                field: .firstLineIndent,
                range: ReadingSettings.firstLineIndentRange
            ))
            detailStack.addArrangedSubview(makeSectionLabel("\u{7AE0}\u{8282}\u{6807}\u{9898}"))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{5B57}\u{95F4}\u{8DDD}",
                field: .titleCharacterSpacing,
                range: ReadingSettings.characterSpacingRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{884C}\u{8DDD}",
                field: .titleLineSpacing,
                range: ReadingSettings.lineSpacingRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{6BB5}\u{8DDD}",
                field: .titleParagraphSpacing,
                range: ReadingSettings.paragraphSpacingRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{5B57}\u{4F53}\u{7C97}\u{7EC6}",
                field: .titleFontWeight,
                range: ReadingSettings.fontWeightRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{5B57}\u{53F7}\u{589E}\u{91CF}",
                field: .titleFontSizeDelta,
                range: ReadingSettings.titleFontSizeDeltaRange
            ))
            detailStack.addArrangedSubview(makeSectionLabel("\u{5C0F}\u{90E8}\u{4EF6}"))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{5DE6}\u{8FB9}\u{8DDD}",
                field: .widgetLeftInset,
                range: ReadingSettings.widgetHorizontalInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{53F3}\u{8FB9}\u{8DDD}",
                field: .widgetRightInset,
                range: ReadingSettings.widgetHorizontalInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{4E0B}\u{8FB9}\u{8DDD}",
                field: .widgetBottomInset,
                range: ReadingSettings.widgetBottomInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{6807}\u{9898}\u{4E0A}\u{8FB9}\u{8DDD}",
                field: .widgetTitleTopInset,
                range: ReadingSettings.widgetTitleTopInsetRange
            ))
            detailStack.addArrangedSubview(makeNumericRow(
                title: "\u{6807}\u{9898}\u{5DE6}\u{8FB9}\u{8DDD}",
                field: .widgetTitleLeftInset,
                range: ReadingSettings.widgetHorizontalInsetRange
            ))
        case .more:
            detailStack.addArrangedSubview(makeSwitchRow(
                title: "\u{5C4F}\u{5E55}\u{5E38}\u{4EAE}",
                toggle: keepAwakeSwitch
            ))
            detailStack.addArrangedSubview(makeSwitchRow(
                title: "\u{81EA}\u{52A8}\u{9690}\u{85CF}\u{5E95}\u{90E8}\u{5C0F}\u{6A2A}\u{6761}",
                toggle: homeIndicatorSwitch
            ))
            detailStack.addArrangedSubview(makeSwitchRow(
                title: "\u{4FA7}\u{6ED1}\u{8FD4}\u{56DE}",
                toggle: swipeBackSwitch
            ))
            detailStack.addArrangedSubview(makeSectionLabel("\u{72B6}\u{6001}\u{680F}\u{663E}\u{793A}"))
            for item in ReadingStatusBarItem.allCases {
                let toggle = UISwitch()
                toggle.isOn = pendingSettings.statusBarItems.contains(item)
                toggle.addAction(
                    UIAction { [weak self, weak toggle] _ in
                        guard let self, let toggle else {
                            return
                        }
                        updateStatusBarItem(item, isEnabled: toggle.isOn)
                    },
                    for: .valueChanged
                )
                statusSwitches[item] = toggle
                detailStack.addArrangedSubview(makeSwitchRow(title: item.displayName, toggle: toggle))
            }
        }

        refreshControlValues()
    }

    private var currentDetailMode: DetailMode {
        DetailMode(rawValue: detailModeControl.selectedSegmentIndex) ?? .pageTurn
    }

    private func makeSectionLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = YominkTheme.primaryText
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func makeSegmentedRow(title: String, control: UISegmentedControl) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = YominkTheme.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true

        let stackView = UIStackView(arrangedSubviews: [titleLabel, control])
        stackView.axis = .vertical
        stackView.spacing = 8
        return stackView
    }

    private func makeNumericRow(
        title: String,
        field: NumericField,
        range: ClosedRange<Double>
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = YominkTheme.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true

        let minusButton = makeIconButton(systemName: "minus") { [weak self] in
            self?.adjustNumericField(field, delta: -1, range: range)
        }
        let textField = makeValueField(for: field)
        let plusButton = makeIconButton(systemName: "plus") { [weak self] in
            self?.adjustNumericField(field, delta: 1, range: range)
        }

        let controls = UIStackView(arrangedSubviews: [minusButton, textField, plusButton])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 10

        NSLayoutConstraint.activate([
            minusButton.widthAnchor.constraint(equalToConstant: 38),
            minusButton.heightAnchor.constraint(equalToConstant: 38),
            plusButton.widthAnchor.constraint(equalToConstant: 38),
            plusButton.heightAnchor.constraint(equalToConstant: 38),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        let row = UIStackView(arrangedSubviews: [titleLabel, controls])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.spacing = 12
        return row
    }

    private func makeValueField(for field: NumericField) -> UITextField {
        let textField = UITextField()
        textField.borderStyle = .roundedRect
        textField.keyboardType = .decimalPad
        textField.textAlignment = .center
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = self
        textField.addAction(
            UIAction { [weak self, weak textField] _ in
                guard let self, let textField else {
                    return
                }
                commitTextField(textField)
            },
            for: .editingDidEnd
        )
        numericFields[field] = textField
        return textField
    }

    private func makeSwitchRow(title: String, toggle: UISwitch) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = YominkTheme.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2

        let row = UIStackView(arrangedSubviews: [titleLabel, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.spacing = 12
        return row
    }

    private func makeIconButton(systemName: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(
            UIAction { _ in
                action()
            },
            for: .touchUpInside
        )
        return button
    }

    private func removeArrangedSubviews(from stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func refreshControlValues() {
        themeControl.selectedSegmentIndex = ReadingTheme.allCases.firstIndex(of: pendingSettings.theme) ?? 0
        pageTurnControl.selectedSegmentIndex = ReadingPageTurnMode.allCases.firstIndex(
            of: pendingSettings.pageTurnMode
        ) ?? 0
        layoutDensityControl.selectedSegmentIndex = ReadingLayoutDensity.allCases.firstIndex(
            of: pendingSettings.layoutDensity
        ) ?? 0
        keepAwakeSwitch.isOn = pendingSettings.keepScreenAwake
        homeIndicatorSwitch.isOn = pendingSettings.autoHideHomeIndicator
        swipeBackSwitch.isOn = pendingSettings.allowsSwipeBack

        for (item, toggle) in statusSwitches {
            toggle.isOn = pendingSettings.statusBarItems.contains(item)
        }

        for (field, textField) in numericFields {
            textField.text = formattedValue(value(for: field))
        }
    }

    private func value(for field: NumericField) -> CGFloat {
        switch field {
        case .fontSize:
            return pendingSettings.layout.fontSize
        case .characterSpacing:
            return pendingSettings.layout.characterSpacing
        case .lineSpacing:
            return pendingSettings.layout.lineSpacing
        case .paragraphSpacing:
            return pendingSettings.layout.paragraphSpacing
        case .topInset:
            return pendingSettings.layout.contentInsets.top
        case .bottomInset:
            return pendingSettings.layout.contentInsets.bottom
        case .leftInset:
            return pendingSettings.layout.contentInsets.left
        case .rightInset:
            return pendingSettings.layout.contentInsets.right
        case .bodyFontWeight:
            return pendingSettings.layout.bodyFontWeight
        case .firstLineIndent:
            return pendingSettings.layout.firstLineIndent
        case .titleCharacterSpacing:
            return pendingSettings.layout.chapterTitleCharacterSpacing
        case .titleLineSpacing:
            return pendingSettings.layout.chapterTitleLineSpacing
        case .titleParagraphSpacing:
            return pendingSettings.layout.chapterTitleParagraphSpacing
        case .titleFontWeight:
            return pendingSettings.layout.chapterTitleFontWeight
        case .titleFontSizeDelta:
            return pendingSettings.layout.chapterTitleFontSizeDelta
        case .widgetLeftInset:
            return pendingSettings.layout.widgetLayout.leftInset
        case .widgetRightInset:
            return pendingSettings.layout.widgetLayout.rightInset
        case .widgetBottomInset:
            return pendingSettings.layout.widgetLayout.bottomInset
        case .widgetTitleTopInset:
            return pendingSettings.layout.widgetLayout.titleTopInset
        case .widgetTitleLeftInset:
            return pendingSettings.layout.widgetLayout.titleLeftInset
        }
    }

    private func setValue(_ value: CGFloat, for field: NumericField) {
        switch field {
        case .fontSize:
            pendingSettings.layout.fontSize = value
        case .characterSpacing:
            pendingSettings.layout.characterSpacing = value
            pendingSettings.layoutDensity = .custom
        case .lineSpacing:
            pendingSettings.layout.lineSpacing = value
            pendingSettings.layoutDensity = .custom
        case .paragraphSpacing:
            pendingSettings.layout.paragraphSpacing = value
            pendingSettings.layoutDensity = .custom
        case .topInset:
            pendingSettings.layout.contentInsets.top = value
            pendingSettings.layoutDensity = .custom
        case .bottomInset:
            pendingSettings.layout.contentInsets.bottom = value
            pendingSettings.layoutDensity = .custom
        case .leftInset:
            pendingSettings.layout.contentInsets.left = value
            pendingSettings.layoutDensity = .custom
        case .rightInset:
            pendingSettings.layout.contentInsets.right = value
            pendingSettings.layoutDensity = .custom
        case .bodyFontWeight:
            pendingSettings.layout.bodyFontWeight = value
            pendingSettings.layoutDensity = .custom
        case .firstLineIndent:
            pendingSettings.layout.firstLineIndent = value
            pendingSettings.layoutDensity = .custom
        case .titleCharacterSpacing:
            pendingSettings.layout.chapterTitleCharacterSpacing = value
            pendingSettings.layoutDensity = .custom
        case .titleLineSpacing:
            pendingSettings.layout.chapterTitleLineSpacing = value
            pendingSettings.layoutDensity = .custom
        case .titleParagraphSpacing:
            pendingSettings.layout.chapterTitleParagraphSpacing = value
            pendingSettings.layoutDensity = .custom
        case .titleFontWeight:
            pendingSettings.layout.chapterTitleFontWeight = value
            pendingSettings.layoutDensity = .custom
        case .titleFontSizeDelta:
            pendingSettings.layout.chapterTitleFontSizeDelta = value
            pendingSettings.layoutDensity = .custom
        case .widgetLeftInset:
            pendingSettings.layout.widgetLayout.leftInset = value
            pendingSettings.layoutDensity = .custom
        case .widgetRightInset:
            pendingSettings.layout.widgetLayout.rightInset = value
            pendingSettings.layoutDensity = .custom
        case .widgetBottomInset:
            pendingSettings.layout.widgetLayout.bottomInset = value
            pendingSettings.layoutDensity = .custom
        case .widgetTitleTopInset:
            pendingSettings.layout.widgetLayout.titleTopInset = value
            pendingSettings.layoutDensity = .custom
        case .widgetTitleLeftInset:
            pendingSettings.layout.widgetLayout.titleLeftInset = value
            pendingSettings.layoutDensity = .custom
        }
        pendingSettings = pendingSettings.normalized()
    }

    private func adjustNumericField(
        _ field: NumericField,
        delta: CGFloat,
        range: ClosedRange<Double>
    ) {
        let step = stepValue(for: field)
        let direction = delta < 0 ? -step : step
        let updatedValue = clamped(Double(value(for: field) + direction), in: range)
        setValue(CGFloat(updatedValue), for: field)
        refreshControlValues()
    }

    private func commitTextField(_ textField: UITextField) {
        guard let field = numericFields.first(where: { $0.value === textField })?.key else {
            return
        }

        guard let text = textField.text,
              let value = Double(text) else {
            refreshControlValues()
            return
        }

        setValue(CGFloat(clamped(value, in: range(for: field))), for: field)
        refreshControlValues()
    }

    private func range(for field: NumericField) -> ClosedRange<Double> {
        switch field {
        case .fontSize:
            return ReadingSettings.fontSizeRange
        case .characterSpacing:
            return ReadingSettings.characterSpacingRange
        case .lineSpacing:
            return ReadingSettings.lineSpacingRange
        case .paragraphSpacing:
            return ReadingSettings.paragraphSpacingRange
        case .topInset, .bottomInset:
            return ReadingSettings.verticalInsetRange
        case .leftInset, .rightInset:
            return ReadingSettings.horizontalInsetRange
        case .bodyFontWeight, .titleFontWeight:
            return ReadingSettings.fontWeightRange
        case .firstLineIndent:
            return ReadingSettings.firstLineIndentRange
        case .titleCharacterSpacing:
            return ReadingSettings.characterSpacingRange
        case .titleLineSpacing:
            return ReadingSettings.lineSpacingRange
        case .titleParagraphSpacing:
            return ReadingSettings.paragraphSpacingRange
        case .titleFontSizeDelta:
            return ReadingSettings.titleFontSizeDeltaRange
        case .widgetLeftInset, .widgetRightInset, .widgetTitleLeftInset:
            return ReadingSettings.widgetHorizontalInsetRange
        case .widgetBottomInset:
            return ReadingSettings.widgetBottomInsetRange
        case .widgetTitleTopInset:
            return ReadingSettings.widgetTitleTopInsetRange
        }
    }

    private func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private func formattedValue(_ value: CGFloat) -> String {
        let roundedValue = (Double(value) * 10).rounded() / 10
        if roundedValue.rounded() == roundedValue {
            return String(Int(roundedValue))
        }
        return String(format: "%.1f", roundedValue)
    }

    private func stepValue(for field: NumericField) -> CGFloat {
        switch field {
        case .characterSpacing,
             .titleCharacterSpacing:
            return 0.1
        default:
            return 1
        }
    }

    private func applyDensity(_ density: ReadingLayoutDensity) {
        guard density != .custom else {
            return
        }

        switch density {
        case .compact:
            applyPresetLayout(.compactPhone)
        case .standard:
            applyPresetLayout(.defaultPhone)
        case .loose:
            applyPresetLayout(.loosePhone)
        case .custom:
            break
        }
        pendingSettings = pendingSettings.normalized()
    }

    private func applyPresetLayout(_ layout: ReadingLayout) {
        let fontSize = pendingSettings.layout.fontSize
        pendingSettings.layout = layout
        pendingSettings.layout.fontSize = fontSize
    }

    private func updateStatusBarItem(_ item: ReadingStatusBarItem, isEnabled: Bool) {
        if isEnabled {
            pendingSettings.statusBarItems.insert(item)
        } else {
            pendingSettings.statusBarItems.remove(item)
        }
    }

    @objc private func themeChanged() {
        let index = max(0, themeControl.selectedSegmentIndex)
        pendingSettings.theme = ReadingTheme.allCases[index]
    }

    @objc private func detailModeChanged() {
        rebuildDetailLayer()
    }

    @objc private func pageTurnChanged() {
        let index = max(0, pageTurnControl.selectedSegmentIndex)
        pendingSettings.pageTurnMode = ReadingPageTurnMode.allCases[index]
    }

    @objc private func layoutDensityChanged() {
        let index = max(0, layoutDensityControl.selectedSegmentIndex)
        let density = ReadingLayoutDensity.allCases[index]
        pendingSettings.layoutDensity = density
        applyDensity(density)
        refreshControlValues()
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func apply() {
        view.endEditing(true)
        onApply?(pendingSettings.normalized())
        dismiss(animated: true)
    }
}

extension ReaderSettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
