import UIKit

final class AutoReadSpeedPanelView: UIView {
    var onSpeedChanged: ((CGFloat) -> Void)?
    var onExit: (() -> Void)?

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let speedSlider = UISlider()
    private let exitButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        setVisible(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(speed: CGFloat, theme: ReadingTheme) {
        let clampedSpeed = min(CGFloat(speedSlider.maximumValue), max(CGFloat(speedSlider.minimumValue), speed))
        speedSlider.value = Float(clampedSpeed)
        valueLabel.text = "\(Int(clampedSpeed.rounded())) pt/s"
        applyTheme(theme)
    }

    func setVisible(_ isVisible: Bool, animated: Bool) {
        let updates = {
            self.alpha = isVisible ? 1 : 0
            self.transform = isVisible ? .identity : CGAffineTransform(translationX: 0, y: 18)
        }

        isHidden = false
        isUserInteractionEnabled = isVisible
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                updates()
            } completion: { _ in
                self.isHidden = !isVisible
            }
        } else {
            updates()
            isHidden = !isVisible
        }
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 0

        titleLabel.text = "\u{81EA}\u{52A8}\u{9605}\u{8BFB}\u{901F}\u{5EA6}"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.font = .preferredFont(forTextStyle: .caption1)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textAlignment = .right

        speedSlider.minimumValue = 12
        speedSlider.maximumValue = 240
        speedSlider.isContinuous = true
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = "\u{9000}\u{51FA}\u{81EA}\u{52A8}\u{9605}\u{8BFB}"
        buttonConfiguration.image = UIImage(systemName: "stop.circle")
        buttonConfiguration.imagePadding = 6
        exitButton.configuration = buttonConfiguration
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.distribution = .fill
        headerStack.spacing = 12

        let stackView = UIStackView(arrangedSubviews: [headerStack, speedSlider, exitButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func applyTheme(_ theme: ReadingTheme) {
        let palette = ReadingThemePalette.palette(for: theme)
        backgroundColor = palette.chromeBackground
        titleLabel.textColor = palette.primaryText
        valueLabel.textColor = palette.secondaryText
        speedSlider.tintColor = palette.primaryText
        exitButton.tintColor = palette.primaryText
    }

    @objc private func speedChanged() {
        let speed = CGFloat(speedSlider.value)
        valueLabel.text = "\(Int(speed.rounded())) pt/s"
        onSpeedChanged?(speed)
    }

    @objc private func exitTapped() {
        onExit?()
    }
}
