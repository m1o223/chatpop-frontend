import UIKit
import ImageIO
import AVFoundation

final class NativeCreativeStudioCard: UIControl {
    var playbackEnabled = false { didSet { collage.playbackEnabled = playbackEnabled } }

    private let collage = CreativeShowcaseGallery()
    private let shade = CAGradientLayer()
    private let eyebrow = UILabel()
    private let heading = UILabel()
    private let callToAction = UILabel()
    private let arrow = UIImageView(image: UIImage(systemName: "arrow.right"))
    private let actionSurface = UIView()
    private var measuredWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous
        layer.borderColor = UIColor.white.withAlphaComponent(0.13).cgColor
        layer.borderWidth = 0.5
        clipsToBounds = true
        accessibilityIdentifier = "studio.card"
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Creative Studio. Create images and videos."
        accessibilityHint = "Opens Creative Studio"

        collage.isUserInteractionEnabled = false
        addSubview(collage)
        shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.65).cgColor,
                        UIColor.black.withAlphaComponent(0.86).cgColor, UIColor.black.withAlphaComponent(0.95).cgColor]
        shade.locations = [0, 0.28, 0.7, 1]
        layer.addSublayer(shade)

        eyebrow.text = "Create Images & Videos with AI"
        eyebrow.textColor = UIColor.white.withAlphaComponent(0.88)
        eyebrow.numberOfLines = 0
        heading.text = "Creative Studio"
        heading.textColor = .white
        heading.numberOfLines = 0
        callToAction.text = "Try it"
        callToAction.textColor = .white
        actionSurface.backgroundColor = ChatPopPreferences.blue
        actionSurface.layer.cornerRadius = 22
        actionSurface.layer.cornerCurve = .continuous
        arrow.tintColor = .white
        arrow.contentMode = .scaleAspectFit
        for label in [eyebrow, heading, callToAction] {
            label.adjustsFontForContentSizeCategory = true
            label.isAccessibilityElement = false
        }
        for item in [eyebrow, heading, actionSurface] {
            item.isUserInteractionEnabled = false
            addSubview(item)
        }
        actionSurface.addSubview(callToAction)
        actionSurface.addSubview(arrow)
        updateFonts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 350
        let text = textLayout(width: width)
        return CGSize(width: UIView.noIntrinsicMetric, height: max(280, text.totalHeight + 150))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(measuredWidth - bounds.width) > 0.5 {
            measuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        collage.frame = bounds
        let text = textLayout(width: bounds.width)
        let top = bounds.height - text.totalHeight - 22
        eyebrow.frame = CGRect(x: 20, y: top, width: bounds.width - 40, height: text.eyebrowHeight)
        let titleY = eyebrow.frame.maxY + 6
        heading.frame = CGRect(x: 20, y: titleY, width: text.titleWidth, height: text.titleHeight)
        actionSurface.frame = CGRect(x: bounds.width - text.actionWidth - 20,
                                     y: bounds.height - text.actionHeight - 22,
                                     width: text.actionWidth, height: text.actionHeight)
        actionSurface.layer.cornerRadius = text.actionHeight / 2
        let arrowSize: CGFloat = 16
        callToAction.frame = CGRect(x: 16, y: 0, width: text.actionWidth - 52, height: text.actionHeight)
        arrow.frame = CGRect(x: text.actionWidth - arrowSize - 14, y: (text.actionHeight - arrowSize) / 2,
                             width: arrowSize, height: arrowSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = CGRect(x: 0, y: max(0, top - 65), width: bounds.width, height: bounds.height - max(0, top - 65))
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateFonts()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            collage.interactionPaused = isHighlighted
            let target: CGAffineTransform = isHighlighted && !UIAccessibility.isReduceMotionEnabled
                ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.transform = target
                self.actionSurface.alpha = self.isHighlighted ? 0.82 : 1
            }
        }
    }

    private func updateFonts() {
        eyebrow.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .medium), compatibleWith: traitCollection)
        heading.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 32, weight: .semibold), compatibleWith: traitCollection)
        callToAction.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection).pointSize, weight: .semibold)
    }

    private func textLayout(width: CGFloat) -> (eyebrowHeight: CGFloat, titleWidth: CGFloat, titleHeight: CGFloat,
                                               actionWidth: CGFloat, actionHeight: CGFloat, totalHeight: CGFloat) {
        let available = max(1, width - 40)
        let actionWidth = min(available, max(94, ceil(callToAction.intrinsicContentSize.width) + 52))
        let actionHeight = max(44, ceil(callToAction.font.lineHeight) + 20)
        let vertical = traitCollection.preferredContentSizeCategory.isAccessibilityCategory || available - actionWidth - 12 < 145
        let titleWidth = vertical ? available : available - actionWidth - 12
        let eyebrowHeight = ceil(eyebrow.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)).height)
        let titleHeight = ceil(heading.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height)
        let totalHeight = eyebrowHeight + 6 + (vertical ? titleHeight + 14 + actionHeight : max(titleHeight, actionHeight))
        return (eyebrowHeight, titleWidth, titleHeight, actionWidth, actionHeight, totalHeight)
    }
}

final class NativeCreativeStudioViewController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        view.accessibilityIdentifier = "studio.screen"
        view.accessibilityViewIsModal = true

        let close = NativeMaterial.button(symbol: "xmark", label: "Close Creative Studio") { [weak self] in
            self?.dismiss(animated: true)
        }
        close.accessibilityIdentifier = "studio.close"
        let closeSurface = NativeMaterial.wrap(close)
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        let content = UIView()
        let collage = CreativeMediaComposition()
        let heading = UILabel()
        heading.text = "Creative Studio"
        heading.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 34, weight: .bold))
        heading.textColor = .white
        heading.numberOfLines = 0
        heading.adjustsFontForContentSizeCategory = true
        heading.accessibilityTraits = .header
        let status = UILabel()
        status.text = "Image and video creation is not available yet."
        status.font = .preferredFont(forTextStyle: .body)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        status.adjustsFontForContentSizeCategory = true

        [scroll, closeSurface].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        [collage, heading, status].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            closeSurface.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeSurface.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            closeSurface.widthAnchor.constraint(equalToConstant: 44),
            scroll.topAnchor.constraint(equalTo: closeSurface.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            collage.topAnchor.constraint(equalTo: content.topAnchor),
            collage.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            collage.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            collage.heightAnchor.constraint(equalTo: collage.widthAnchor, multiplier: 0.9),
            heading.topAnchor.constraint(equalTo: collage.bottomAnchor, constant: 28),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            status.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -32)
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func accessibilityPerformEscape() -> Bool { dismiss(animated: true); return true }
}

private struct CreativeShowcaseManifest: Decodable {
    let cycleDuration: TimeInterval
    let items: [CreativeShowcaseItem]

    static func bundled() -> CreativeShowcaseManifest? {
        guard let url = Bundle.main.url(forResource: "gallery", withExtension: "json", subdirectory: "public/media/creative"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Self.self, from: data),
              manifest.cycleDuration.isFinite, manifest.cycleDuration >= 12,
              !manifest.items.isEmpty, manifest.items.count <= 32,
              manifest.items.allSatisfy({ $0.aspectRatio.isFinite && $0.aspectRatio > 0 && (1...2).contains($0.columnSpan) }) else {
            return nil
        }
        return manifest
    }
}

private struct CreativeShowcaseItem: Decodable {
    enum Kind: String, Decodable { case image, video }
    let id: String
    let type: Kind
    let source: String
    let poster: String?
    let aspectRatio: CGFloat
    let altText: String
    let columnSpan: Int
}

private final class CreativeShowcaseTile: UIView {
    let item: CreativeShowcaseItem
    private let preview = CALayer()

    init(item: CreativeShowcaseItem, copy: Int) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true
        accessibilityIdentifier = "studio.gallery.\(item.id).\(copy)"
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        preview.contentsGravity = .resizeAspectFill
        layer.addSublayer(preview)
        if let source = item.type == .image ? item.source : item.poster {
            CreativeMediaCache.loadFile(source) { [weak self] image in
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self?.preview.contents = image?.cgImage
                CATransaction.commit()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.forEach { $0.frame = bounds }
        CATransaction.commit()
    }
}

private final class CreativeShowcaseDisplayTarget: NSObject {
    weak var gallery: CreativeShowcaseGallery?
    @objc func tick() { gallery?.refreshVisibility() }
}

private final class CreativeShowcaseGallery: UIView {
    var playbackEnabled = false { didSet { refreshVisibility() } }
    var interactionPaused = false { didSet { refreshVisibility() } }

    private let manifest = CreativeShowcaseManifest.bundled()
    private let track = UIView()
    private var tiles: [CreativeShowcaseTile] = []
    private var cycleHeight: CGFloat = 0
    private var laidOutSize = CGSize.zero
    private var savedPhase: Double = 0
    private var motionStarted: CFTimeInterval = 0
    private var runningRate: Double = 0
    private var displayLink: CADisplayLink?
    private let displayTarget = CreativeShowcaseDisplayTarget()
    private var scrollObservers: [NSKeyValueObservation] = []
    private let parentScrollViews = NSHashTable<UIScrollView>.weakObjects()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private let videoLayer = AVPlayerLayer()
    private var readyObserver: NSKeyValueObservation?
    private var playingSource: String?
    private weak var activeVideoTile: CreativeShowcaseTile?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "studio.gallery"
        track.accessibilityIdentifier = "studio.gallery.track"
        track.isUserInteractionEnabled = false
        addSubview(track)
        videoLayer.videoGravity = .resizeAspectFill
        displayTarget.gallery = self
        NotificationCenter.default.addObserver(self, selector: #selector(refreshVisibility), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopForBackground), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshVisibility), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshVisibility), name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
        player?.pause()
        looper?.disableLooping()
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scrollObservers.removeAll()
        parentScrollViews.removeAllObjects()
        if window != nil {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    parentScrollViews.add(scroll)
                    scrollObservers.append(scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                        self?.refreshVisibility()
                    })
                }
                ancestor = view.superview
            }
        }
        refreshVisibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0,
              let manifest else { return }
        setMotion(rate: 0)
        laidOutSize = bounds.size
        activeVideoTile = nil
        videoLayer.removeFromSuperlayer()
        tiles.forEach { $0.removeFromSuperview() }
        tiles.removeAll()

        let gap: CGFloat = 6
        let columnWidth = (bounds.width - gap) / 2
        var columns: [CGFloat] = [0, 0]
        var frames: [CGRect] = []
        for item in manifest.items {
            let wide = item.columnSpan == 2
            let column = columns[0] <= columns[1] ? 0 : 1
            let width = wide ? bounds.width : columnWidth
            let y = wide ? max(columns[0], columns[1]) : columns[column]
            let frame = CGRect(x: wide ? 0 : CGFloat(column) * (columnWidth + gap), y: y,
                               width: width, height: width / item.aspectRatio)
            frames.append(frame)
            if wide { columns = [frame.maxY + gap, frame.maxY + gap] }
            else { columns[column] = frame.maxY + gap }
        }
        cycleHeight = max(columns[0], columns[1])
        // Additional copies are only needed at large accessibility sizes; media decoding remains shared.
        let copies = max(2, Int(ceil(bounds.height / cycleHeight)) + 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: cycleHeight * CGFloat(copies))
        track.center = CGPoint(x: bounds.midX, y: track.bounds.height / 2)
        for copy in 0..<copies {
            for (item, frame) in zip(manifest.items, frames) {
                let tile = CreativeShowcaseTile(item: item, copy: copy)
                tile.frame = frame.offsetBy(dx: 0, dy: cycleHeight * CGFloat(copy))
                track.addSubview(tile)
                tiles.append(tile)
            }
        }
        track.transform = CGAffineTransform(translationX: 0, y: -cycleHeight * savedPhase)
        CATransaction.commit()
        refreshVisibility()
    }

    @objc fileprivate func refreshVisibility() {
        let eligible = playbackEnabled && window != nil && UIApplication.shared.applicationState == .active
            && !ProcessInfo.processInfo.isLowPowerModeEnabled && cycleHeight > 0
        let visible = eligible && isVisibleInWindow()
        let interacting = interactionPaused || parentScrollViews.allObjects.contains { $0.isTracking || $0.isDragging || $0.isDecelerating }
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        let desiredRate = visible && !interacting ? (reducedMotion ? (manifest?.cycleDuration ?? 20) / 100 : 1) : 0
        setMotion(rate: desiredRate)
        if visible {
            if displayLink == nil {
                let link = CADisplayLink(target: displayTarget, selector: #selector(CreativeShowcaseDisplayTarget.tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 2, maximum: 5, preferred: 5)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
        updateVideo(playing: visible && !interacting && !reducedMotion)
    }

    @objc private func stopForBackground() {
        setMotion(rate: 0)
        player?.pause()
        displayLink?.invalidate()
        displayLink = nil
    }

    private func isVisibleInWindow() -> Bool {
        guard let window else { return false }
        var visible = convert(bounds, to: window).intersection(window.bounds)
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.01 { return false }
            if view.clipsToBounds { visible = visible.intersection(view.convert(view.bounds, to: window)) }
            ancestor = view.superview
        }
        return !visible.isNull && visible.width > 1 && visible.height > 1
    }

    private var phase: Double {
        let duration = manifest?.cycleDuration ?? 20
        let elapsed = runningRate == 0 ? 0 : (CACurrentMediaTime() - motionStarted) * runningRate / duration
        return (savedPhase + elapsed).truncatingRemainder(dividingBy: 1)
    }

    private func setMotion(rate: Double) {
        guard runningRate != rate else { return }
        savedPhase = phase
        runningRate = rate
        motionStarted = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.layer.removeAnimation(forKey: "studio.gallery.upward")
        track.transform = CGAffineTransform(translationX: 0, y: -cycleHeight * savedPhase)
        if rate > 0 {
            let movement = CABasicAnimation(keyPath: "transform.translation.y")
            movement.fromValue = 0
            movement.toValue = -cycleHeight
            movement.duration = manifest?.cycleDuration ?? 20
            movement.beginTime = track.layer.convertTime(motionStarted, from: nil)
            movement.timeOffset = savedPhase * movement.duration
            movement.speed = Float(rate)
            movement.repeatCount = .infinity
            movement.timingFunction = CAMediaTimingFunction(name: .linear)
            track.layer.add(movement, forKey: "studio.gallery.upward")
        }
        CATransaction.commit()
    }

    private func updateVideo(playing: Bool) {
        guard playing else { player?.pause(); return }
        let offset = -cycleHeight * phase
        let visibleTile = tiles.first { tile in
            tile.item.type == .video && tile.frame.offsetBy(dx: 0, dy: offset).intersects(bounds)
        }
        guard let tile = visibleTile else {
            player?.pause()
            videoLayer.removeFromSuperlayer()
            activeVideoTile = nil
            return
        }
        if playingSource != tile.item.source { preparePlayer(source: tile.item.source) }
        guard let player else { return }
        if activeVideoTile !== tile {
            activeVideoTile = tile
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.removeFromSuperlayer()
            tile.layer.addSublayer(videoLayer)
            videoLayer.frame = tile.bounds
            videoLayer.opacity = videoLayer.isReadyForDisplay ? 1 : 0
            CATransaction.commit()
        }
        if player.rate == 0 { player.play() }
    }

    private func preparePlayer(source: String) {
        guard let url = CreativeMediaCache.fileURL(source) else { return }
        readyObserver = nil
        player?.pause()
        looper?.disableLooping()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        self.player = player
        playingSource = source
        videoLayer.player = player
        videoLayer.opacity = 0
        readyObserver = videoLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.videoLayer.opacity = layer.isReadyForDisplay ? 1 : 0
                CATransaction.commit()
            }
        }
    }
}

private final class CreativeMediaComposition: UIView {
    private enum MotionMode { case full, crossfade, paused }
    var playbackEnabled = false { didSet { updatePlayback() } }
    private let tiles = [
        CreativeMediaTile(name: "coast", alternate: "landscape", index: 0),
        CreativeMediaTile(name: "portrait", index: 1),
        CreativeMediaTile(name: "product", index: 2),
        CreativeMediaTile(name: "architecture", index: 3),
        CreativeMediaTile(name: "landscape", index: 4)
    ]
    private var motionConfigured: MotionMode?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        tiles.forEach(addSubview)
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayback), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pausePlayback), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayback), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayback), name: .NSProcessInfoPowerStateDidChange, object: nil)
        pausePlayback()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 4
        let focalWidth = floor(bounds.width * 0.62)
        let focalHeight = floor(bounds.height * 0.62)
        let upperRightHeight = floor(bounds.height * 0.34)
        let lowerLeftWidth = floor(bounds.width * 0.4)
        let rightWidth = bounds.width - focalWidth - gap
        let frames = [
            CGRect(x: 0, y: 0, width: focalWidth, height: focalHeight),
            CGRect(x: focalWidth + gap, y: 0, width: rightWidth, height: upperRightHeight),
            CGRect(x: focalWidth + gap, y: upperRightHeight + gap, width: rightWidth, height: bounds.height - upperRightHeight - gap),
            CGRect(x: 0, y: focalHeight + gap, width: lowerLeftWidth, height: bounds.height - focalHeight - gap),
            CGRect(x: lowerLeftWidth + gap, y: focalHeight + gap, width: focalWidth - lowerLeftWidth - gap, height: bounds.height - focalHeight - gap)
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (tile, frame) in zip(tiles, frames) { tile.frame = frame }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    @objc private func updatePlayback() {
        let mode: MotionMode = ProcessInfo.processInfo.isLowPowerModeEnabled ? .paused
            : UIAccessibility.isReduceMotionEnabled ? .crossfade : .full
        if motionConfigured != mode {
            motionConfigured = mode
            tiles.forEach { $0.configureMotion(spatial: mode == .full, crossfade: mode != .paused) }
        }
        let running = mode != .paused && playbackEnabled && window != nil && UIApplication.shared.applicationState == .active
        guard running else { pausePlayback(); return }
        guard layer.speed == 0 else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }

    @objc private func pausePlayback() {
        guard layer.speed != 0 else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
    }
}

private final class CreativeMediaTile: UIView {
    private let imageLayer = CALayer()
    private let alternateLayer = CALayer()
    private let index: Int
    private let hasAlternate: Bool

    init(name: String, alternate: String? = nil, index: Int) {
        self.index = index
        hasAlternate = alternate != nil
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        clipsToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        alternateLayer.contentsGravity = .resizeAspectFill
        alternateLayer.opacity = 0
        layer.addSublayer(imageLayer)
        layer.addSublayer(alternateLayer)
        CreativeMediaCache.load(name) { [weak self] image in
            self?.setImage(image, alternate: false)
        }
        if let alternate {
            CreativeMediaCache.load(alternate) { [weak self] image in
                self?.setImage(image, alternate: true)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = bounds.insetBy(dx: -bounds.width * 0.07, dy: -bounds.height * 0.07)
        // Set geometry without touching transforms, preserving the running animation phase.
        for image in [imageLayer, alternateLayer] {
            image.bounds = CGRect(origin: .zero, size: frame.size)
            image.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func configureMotion(spatial: Bool, crossfade: Bool) {
        for image in [imageLayer, alternateLayer] {
            image.removeAnimation(forKey: "studio.pan")
            guard spatial else { continue }
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let from = CATransform3DTranslate(CATransform3DMakeScale(1.01, 1.01, 1), -4 * direction, -3, 0)
            let to = CATransform3DTranslate(CATransform3DMakeScale(1.075, 1.075, 1), 5 * direction, 4, 0)
            let motion = CABasicAnimation(keyPath: "transform")
            motion.fromValue = NSValue(caTransform3D: from)
            motion.toValue = NSValue(caTransform3D: to)
            motion.duration = 12 + Double(index) * 1.7
            motion.autoreverses = true
            motion.repeatCount = .infinity
            motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            image.add(motion, forKey: "studio.pan")
        }
        alternateLayer.removeAnimation(forKey: "studio.crossfade")
        if crossfade && hasAlternate {
            let dissolve = CAKeyframeAnimation(keyPath: "opacity")
            dissolve.values = [0, 0, 1, 1]
            dissolve.keyTimes = [0, 0.32, 0.47, 1]
            dissolve.duration = spatial ? 10 : 14
            dissolve.autoreverses = true
            dissolve.repeatCount = .infinity
            dissolve.timingFunctions = [.init(name: .linear), .init(name: .easeInEaseOut), .init(name: .linear)]
            alternateLayer.add(dissolve, forKey: "studio.crossfade")
        }
    }

    private func setImage(_ image: UIImage?, alternate: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        (alternate ? alternateLayer : imageLayer).contents = image?.cgImage
        CATransaction.commit()
    }
}

private enum CreativeMediaCache {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    static let queue = DispatchQueue(label: "com.chatpop.studio.media", qos: .userInitiated)

    static func load(_ name: String, completion: @escaping (UIImage?) -> Void) {
        loadFile("\(name).jpg", maximumPixelSize: 840, completion: completion)
    }

    static func fileURL(_ name: String) -> URL? {
        guard !name.contains("/"), !name.contains("\\"), !name.hasPrefix(".") else { return nil }
        let filename = name as NSString
        return Bundle.main.url(forResource: filename.deletingPathExtension, withExtension: filename.pathExtension,
                               subdirectory: "public/media/creative")
    }

    static func loadFile(_ name: String, maximumPixelSize: Int = 640, completion: @escaping (UIImage?) -> Void) {
        let key = "\(maximumPixelSize):\(name)" as NSString
        if let image = cache.object(forKey: key) { completion(image); return }
        queue.async {
            if let image = cache.object(forKey: key) {
                DispatchQueue.main.async { completion(image) }
                return
            }
            // The bundled previews are shared with the web fallback and decoded off the main thread.
            guard let url = fileURL(name),
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
                  ] as CFDictionary) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let image = UIImage(cgImage: bitmap)
            cache.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height)
            DispatchQueue.main.async { completion(image) }
        }
    }
}
