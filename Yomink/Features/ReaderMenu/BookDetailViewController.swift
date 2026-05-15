import UIKit

final class BookDetailViewController: UIViewController {
    var onBookUpdated: ((BookRecord) -> Void)?

    private let bookID: UUID
    private let detailService: BookDetailService
    private var currentDetail: BookDetailSummary?
    private let stackView = UIStackView()

    init(bookID: UUID, detailService: BookDetailService) {
        self.bookID = bookID
        self.detailService = detailService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\u{4E66}\u{7C4D}\u{8BE6}\u{60C5}"
        view.backgroundColor = YominkTheme.background
        configureNavigation()
        configureLayout()
        loadDetail()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "\u{7F16}\u{8F91}",
            style: .plain,
            target: self,
            action: #selector(editBook)
        )
    }

    private func configureLayout() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 20, bottom: 24, trailing: 20)
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func loadDetail() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                currentDetail = try await detailService.detail(for: bookID)
                rebuildContent()
            } catch {
                showError()
            }
        }
    }

    private func rebuildContent() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let detail = currentDetail else {
            return
        }

        stackView.addArrangedSubview(makeValueLabel(title: "\u{4E66}\u{540D}", value: detail.book.title))
        stackView.addArrangedSubview(makeValueLabel(title: "\u{4F5C}\u{8005}", value: detail.book.author ?? "\u{672A}\u{8BBE}\u{7F6E}"))
        stackView.addArrangedSubview(makeValueLabel(
            title: "\u{5B57}\u{6570}",
            value: NumberFormatter.localizedString(from: NSNumber(value: detail.estimatedCharacterCount), number: .decimal)
        ))
        stackView.addArrangedSubview(makeValueLabel(title: "\u{7B80}\u{4ECB}", value: detail.book.summary ?? "\u{672A}\u{8BBE}\u{7F6E}"))
        let catalogText = detail.chapters.isEmpty
            ? "\u{76EE}\u{5F55}\u{89E3}\u{6790}\u{4E2D}"
            : detail.chapters.map(\.title).joined(separator: "\n")
        stackView.addArrangedSubview(makeValueLabel(title: "\u{76EE}\u{5F55}", value: catalogText))
    }

    private func makeValueLabel(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = YominkTheme.primaryText
        titleLabel.adjustsFontForContentSizeCategory = true

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.textColor = YominkTheme.secondaryText
        valueLabel.numberOfLines = 0
        valueLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    @objc private func editBook() {
        guard let detail = currentDetail else {
            return
        }

        let alert = UIAlertController(title: "\u{7F16}\u{8F91}\u{4E66}\u{7C4D}", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "\u{4E66}\u{540D}"
            textField.text = detail.book.title
        }
        alert.addTextField { textField in
            textField.placeholder = "\u{4F5C}\u{8005}"
            textField.text = detail.book.author
        }
        alert.addTextField { textField in
            textField.placeholder = "\u{7B80}\u{4ECB}"
            textField.text = detail.book.summary
        }
        alert.addAction(UIAlertAction(title: "\u{53D6}\u{6D88}", style: .cancel))
        alert.addAction(UIAlertAction(title: "\u{4FDD}\u{5B58}", style: .default) { [weak self, weak alert] _ in
            guard let self else {
                return
            }
            let title = alert?.textFields?[0].text ?? detail.book.title
            let author = alert?.textFields?[1].text
            let summary = alert?.textFields?[2].text
            saveBook(title: title, author: author, summary: summary)
        })
        present(alert, animated: true)
    }

    private func saveBook(title: String, author: String?, summary: String?) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                if let updatedBook = try await detailService.updateBook(
                    bookID: bookID,
                    title: title,
                    author: author,
                    summary: summary
                ) {
                    onBookUpdated?(updatedBook)
                }
                loadDetail()
            } catch {
                showError()
            }
        }
    }

    private func showError() {
        let alert = UIAlertController(title: "\u{4E66}\u{7C4D}\u{8BE6}\u{60C5}\u{52A0}\u{8F7D}\u{5931}\u{8D25}", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        present(alert, animated: true)
    }
}
