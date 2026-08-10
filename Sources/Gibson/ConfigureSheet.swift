import AppKit

/// Options sheet, built in code so the bundle stays free of nib resources.
///
/// It is a view controller rather than a loose window on purpose: the window
/// then retains the controller, sizes itself from the content, and the button
/// targets stay alive for as long as the sheet is on screen. Losing any of
/// those is enough to make the host present nothing at all.
final class ConfigureSheetController: NSViewController {
    var onDismiss: (() -> Void)?

    private let preferences = Preferences.shared
    private let paletteButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let liveMetrics = NSButton(checkboxWithTitle: "Read live system metrics", target: nil, action: nil)
    private let maskInfo = NSButton(checkboxWithTitle: "Mask host name, user and addresses", target: nil, action: nil)
    private let scanlines = NSButton(checkboxWithTitle: "CRT scanlines and vignette", target: nil, action: nil)
    private let glitches = NSButton(checkboxWithTitle: "Occasional signal glitches", target: nil, action: nil)

    private static let contentWidth: CGFloat = 380

    override func loadView() {
        paletteButton.addItems(withTitles: Palette.allCases.map(\.title))

        let paletteRow = NSStackView(views: [label("Colour scheme"), paletteButton])
        paletteRow.orientation = .horizontal
        paletteRow.spacing = 12

        let footnote = label("Process, CPU, memory, disk and network figures are read "
            + "from this Mac. Account, file and log panels are decorative.")
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        footnote.lineBreakMode = .byWordWrapping
        footnote.usesSingleLineMode = false
        footnote.maximumNumberOfLines = 0

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let done = NSButton(title: "Done", target: self, action: #selector(save))
        done.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttons = NSStackView(views: [spacer, cancel, done])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [
            paletteRow, liveMetrics, maskInfo, scanlines, glitches,
            NSBox.separator(), footnote, buttons
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            // Both wide elements get an explicit width so the stack has one
            // unambiguous content width to lay everything else against.
            footnote.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            buttons.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        ])

        view = content
        // NSWindow(contentViewController:) sizes itself from the frame, not
        // from the constraints, so the fitting size has to be resolved here or
        // the sheet comes up one point wide.
        content.layoutSubtreeIfNeeded()
        let fitting = content.fittingSize
        content.frame = CGRect(origin: .zero, size: fitting)
        preferredContentSize = fitting
        load()
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    // MARK: - State

    private func load() {
        let index = Palette.allCases.firstIndex(of: preferences.palette) ?? 0
        paletteButton.selectItem(at: index)
        liveMetrics.state = preferences.liveMetrics ? .on : .off
        maskInfo.state = preferences.maskSensitiveInfo ? .on : .off
        scanlines.state = preferences.scanlines ? .on : .off
        glitches.state = preferences.glitches ? .on : .off
    }

    @objc private func save() {
        let index = max(0, paletteButton.indexOfSelectedItem)
        preferences.palette = Palette.allCases[min(index, Palette.allCases.count - 1)]
        preferences.liveMetrics = liveMetrics.state == .on
        preferences.maskSensitiveInfo = maskInfo.state == .on
        preferences.scanlines = scanlines.state == .on
        preferences.glitches = glitches.state == .on
        preferences.save()
        close(.OK)
    }

    @objc private func cancel() {
        load()
        close(.cancel)
    }

    /// The host may present this as a sheet, as a modal window, or as a plain
    /// window. Ending the wrong way leaves it believing a sheet is still up,
    /// after which every further click on Options does nothing.
    private func close(_ response: NSApplication.ModalResponse) {
        defer { onDismiss?() }
        guard let window = view.window else { return }

        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: response)
        } else if NSApp.modalWindow === window {
            NSApp.stopModal(withCode: response)
            window.orderOut(nil)
        } else {
            window.orderOut(nil)
        }
    }
}

private extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
