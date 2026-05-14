import UIKit

final class ReaderSettingsViewController: UIViewController {
    var onApply: ((ReadingSettings) -> Void)?

    private var pendingSettings: ReadingSettings
    private let themeControl = UISegmentedControl(items: ReadingTheme.allCases.map(\.displayName))
    private let fontSizeLabel = UILabel()
    private let lineSpacingLabel = UILabel()
    private let fontSizeStepper = UIStepper()
    private let lineSpacingStepper = UIStepper()

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
        themeControl.selectedSegmentIndex = ReadingTheme.allCases.firstIndex(of: pendingSettings.theme) ?? 0
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)

        configureStepper(fontSizeStepper, range: ReadingSettings.fontSizeRange)
        configureStepper(lineSpacingStepper, range: ReadingSettings.lineSpacingRange)
        fontSizeStepper.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)
        lineSpacingStepper.addTarget(self, action: #selector(lineSpacingChanged), for: .valueChanged)

        [fontSizeLabel, lineSpacingLabel].forEach { label in
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = YominkTheme.primaryText
            label.adjustsFontForContentSizeCategory = true
        }
    }

    private func configureStepper(_ stepper: UIStepper, range: ClosedRange<Double>) {
        stepper.minimumValue = range.lowerBound
        stepper.maximumValue = range.upperBound
        stepper.stepValue = 1
        stepper.wraps = false
        stepper.autorepeat = false
    }

    private func configureLayout() {
        let stackView = UIStackView(arrangedSubviews: [
            makeSegmentedRow(title: "\u{4E3B}\u{9898}", control: themeControl),
            makeStepperRow(titleLabel: fontSizeLabel, stepper: fontSizeStepper),
            makeStepperRow(titleLabel: lineSpacingLabel, stepper: lineSpacingStepper)
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20)

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
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

    private func makeStepperRow(titleLabel: UILabel, stepper: UIStepper) -> UIView {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, stepper])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 12
        return stackView
    }

    private func refreshControlValues() {
        fontSizeStepper.value = Double(pendingSettings.layout.fontSize)
        lineSpacingStepper.value = Double(pendingSettings.layout.lineSpacing)
        fontSizeLabel.text = "\u{5B57}\u{53F7} \(Int(fontSizeStepper.value))"
        lineSpacingLabel.text = "\u{884C}\u{8DDD} \(Int(lineSpacingStepper.value))"
    }

    @objc private func themeChanged() {
        let index = max(0, themeControl.selectedSegmentIndex)
        pendingSettings.theme = ReadingTheme.allCases[index]
    }

    @objc private func fontSizeChanged() {
        pendingSettings.layout.fontSize = CGFloat(fontSizeStepper.value)
        refreshControlValues()
    }

    @objc private func lineSpacingChanged() {
        pendingSettings.layout.lineSpacing = CGFloat(lineSpacingStepper.value)
        refreshControlValues()
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func apply() {
        onApply?(pendingSettings.normalized())
        dismiss(animated: true)
    }
}
