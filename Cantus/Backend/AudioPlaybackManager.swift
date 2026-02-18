import Foundation
import AVFoundation
import GRDB
import MediaPlayer
import MusicKit

final class AudioPlaybackManager {
    static let sfxDidFinishNotification = Notification.Name("AudioPlaybackManager.sfxDidFinish")
    static let systemVolumeDidChangeNotification = Notification.Name("AudioPlaybackManager.systemVolumeDidChange")
    static let systemVolumeUserInfoKey = "volume"

    private let dbQueue: DatabaseQueue
    private let engine = AVAudioEngine()
    private let atmosphereMixer = AVAudioMixerNode()
    private let sfxMixer = AVAudioMixerNode()
    private var loopPlayers: [String: LoopingPlayer] = [:]
    private var stoppingLoopPlayers: [String: LoopingPlayer] = [:]
    private var sfxNodes: [String: AVAudioPlayerNode] = [:]
    private var fadingSFXNodeIDs: Set<ObjectIdentifier> = []
    private let queue = DispatchQueue(label: "audio.playback.queue", qos: .userInitiated)
    private var hasConfiguredSession = false
    private var masterVolume: Float = 1.0
    private var atmosphereVolume: Float = 1.0
    private var sfxVolume: Float = 1.0
    private var musicVolume: Float = 1.0
    private var sfxDuckingActive = false
    private let sfxDuckingFactor: Float = 0.55
    private let duckingRampDuration: TimeInterval = 0.24
    private let duckingRampStepCount: Int = 12
    private var atmosphereRampGeneration: UInt64 = 0
    private let userAtmosphereStopFadeDuration: TimeInterval = 0.2
    private let userSFXStopFadeDuration: TimeInterval = 0.5
    private let fadeStepCount: Int = 20
    #if os(iOS)
    private var outputVolumeObservation: NSKeyValueObservation?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var lastPublishedSystemVolume: Float = -1
    private var appliedSessionCategoryOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    #endif

    #if os(iOS)
    private static let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: .zero)
        view.isHidden = true
        view.alpha = 0.01
        return view
    }()
    #endif

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        engine.attach(atmosphereMixer)
        engine.attach(sfxMixer)
        engine.connect(atmosphereMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: nil)
        #if os(iOS)
        DispatchQueue.main.async {
            self.configureSystemVolumeObservationIfNeeded()
        }
        #endif
        startEngineIfNeeded()
    }

    func playAtmosphere(title: String) {
        queue.async {
            guard let file = self.loadFile(kind: .atmosphere, title: title) else { return }
            if let stopping = self.stoppingLoopPlayers.removeValue(forKey: title) {
                stopping.stop(fadeOutDuration: 0)
            }
            if self.loopPlayers[title] != nil {
                return
            }
            self.ensureMixerConnected(self.atmosphereMixer)
            let player = LoopingPlayer(
                engine: self.engine,
                file: file,
                outputMixer: self.atmosphereMixer,
                schedulingQueue: self.queue
            )
            self.loopPlayers[title] = player
            self.startEngineIfNeeded()
            player.start()
        }
    }

    func stopAtmosphere(title: String) {
        queue.async {
            guard let player = self.loopPlayers.removeValue(forKey: title) else { return }
            self.stoppingLoopPlayers[title] = player
            player.stop(fadeOutDuration: self.userAtmosphereStopFadeDuration) { [weak self] in
                self?.queue.async {
                    self?.stoppingLoopPlayers.removeValue(forKey: title)
                }
            }
        }
    }

    func playSFX(title: String) {
        queue.async {
            guard let file = self.loadFile(kind: .sfx, title: title) else { return }
            if let existing = self.sfxNodes[title] {
                self.fadingSFXNodeIDs.remove(ObjectIdentifier(existing))
                existing.stop()
                self.engine.detach(existing)
                self.sfxNodes.removeValue(forKey: title)
            }
            let node = AVAudioPlayerNode()
            self.sfxNodes[title] = node
            self.engine.attach(node)
            self.ensureMixerConnected(self.sfxMixer)
            self.ensureNodeConnected(node, format: file.processingFormat, mixer: self.sfxMixer)
            self.startEngineIfNeeded()
            node.volume = 1
            node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                NotificationCenter.default.post(name: Self.sfxDidFinishNotification, object: title)
                self.queue.async {
                    let nodeID = ObjectIdentifier(node)
                    guard !self.fadingSFXNodeIDs.contains(nodeID) else { return }
                    if self.engine.attachedNodes.contains(node) {
                        node.stop()
                        self.engine.detach(node)
                    }
                    self.sfxNodes.removeValue(forKey: title)
                }
            }
            node.play()
        }
    }

    func stopSFX(title: String) {
        queue.async {
            guard let node = self.sfxNodes.removeValue(forKey: title) else { return }
            self.fadeOutAndDetachSFXNode(node, duration: self.userSFXStopFadeDuration)
        }
    }

    func reconcileAtmospheres(to desired: Set<String>) {
        queue.async {
            let active = Set(self.loopPlayers.keys)
            let toStop = active.subtracting(desired)
            for title in toStop {
                guard let player = self.loopPlayers.removeValue(forKey: title) else { continue }
                self.stoppingLoopPlayers[title] = player
                player.stop(fadeOutDuration: self.userAtmosphereStopFadeDuration) { [weak self] in
                    self?.queue.async {
                        self?.stoppingLoopPlayers.removeValue(forKey: title)
                    }
                }
            }
            let toStart = desired.subtracting(active)
            for title in toStart {
                guard let file = self.loadFile(kind: .atmosphere, title: title) else { continue }
                if let stopping = self.stoppingLoopPlayers.removeValue(forKey: title) {
                    stopping.stop(fadeOutDuration: 0)
                }
                self.ensureMixerConnected(self.atmosphereMixer)
                let player = LoopingPlayer(
                    engine: self.engine,
                    file: file,
                    outputMixer: self.atmosphereMixer,
                    schedulingQueue: self.queue
                )
                self.loopPlayers[title] = player
                self.startEngineIfNeeded()
                player.start()
            }
        }
    }

    func reconcileSFX(to desired: Set<String>) {
        queue.async {
            let active = Set(self.sfxNodes.keys)
            let toStop = active.subtracting(desired)
            for title in toStop {
                guard let node = self.sfxNodes.removeValue(forKey: title) else { continue }
                self.fadeOutAndDetachSFXNode(node, duration: self.userSFXStopFadeDuration)
            }
        }
    }

    func prepareAudioSessionForPlayback() async {
        await withCheckedContinuation { continuation in
            queue.async {
                _ = self.configureAudioSessionIfNeeded()
                self.startEngineIfNeeded()
                continuation.resume()
            }
        }
    }

    private func fadeOutAndDetachSFXNode(_ node: AVAudioPlayerNode, duration: TimeInterval) {
        let nodeID = ObjectIdentifier(node)
        fadingSFXNodeIDs.insert(nodeID)

        let safeDuration = max(0, duration)
        let start = max(0, node.volume)
        guard safeDuration > 0.001, start > 0.001 else {
            if engine.attachedNodes.contains(node) {
                node.stop()
                engine.detach(node)
            }
            fadingSFXNodeIDs.remove(nodeID)
            return
        }

        let steps = max(1, fadeStepCount)
        let stepDuration = safeDuration / Double(steps)
        for step in 1...steps {
            queue.asyncAfter(deadline: .now() + stepDuration * Double(step)) { [weak self] in
                guard let self else { return }
                guard self.fadingSFXNodeIDs.contains(nodeID) else { return }
                guard self.engine.attachedNodes.contains(node) else {
                    self.fadingSFXNodeIDs.remove(nodeID)
                    return
                }
                let progress = Float(step) / Float(steps)
                node.volume = start * (1 - progress)
            }
        }

        queue.asyncAfter(deadline: .now() + safeDuration) { [weak self] in
            guard let self else { return }
            guard self.fadingSFXNodeIDs.contains(nodeID) else { return }
            if self.engine.attachedNodes.contains(node) {
                node.stop()
                self.engine.detach(node)
            }
            self.fadingSFXNodeIDs.remove(nodeID)
        }
    }

    private func startEngineIfNeeded() {
        if engine.isRunning { return }
        do {
            _ = configureAudioSessionIfNeeded()
            engine.prepare()
            try engine.start()
            applyStoredVolumes()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    @discardableResult
    private func configureAudioSessionIfNeeded() -> Bool {
        var didConfigure = true
#if os(iOS)
        didConfigure = false
        let session = AVAudioSession.sharedInstance()
        do {
            let categoryOptions = desiredSessionCategoryOptions()
            if !hasConfiguredSession || categoryOptions != appliedSessionCategoryOptions {
                try session.setCategory(.playback, options: categoryOptions)
                appliedSessionCategoryOptions = categoryOptions
            }
            try session.setActive(true)
            didConfigure = true
        } catch {
            print("Failed to configure audio session: \(error)")
        }
#endif
        if didConfigure && !hasConfiguredSession {
            hasConfiguredSession = true
            #if os(iOS)
            DispatchQueue.main.async {
                self.configureSystemVolumeObservationIfNeeded()
                self.handleObservedSystemVolume(Self.currentSystemVolume())
            }
            #endif
        }
        return didConfigure
    }

    func prewarmAudioSession() {
        queue.async {
            _ = self.configureAudioSessionIfNeeded()
            self.startEngineIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startEngineIfNeeded()
            }
        }
    }

    func syncMasterVolumeWithSystem() {
        #if os(iOS)
        DispatchQueue.main.async {
            self.configureSystemVolumeObservationIfNeeded()
            self.handleObservedSystemVolume(Self.currentSystemVolume())
        }
        #endif
    }

    func currentSystemVolumeValue() -> Double {
        #if os(iOS)
        return Double(Self.currentSystemVolume())
        #else
        return Double(masterVolume)
        #endif
    }

    func setAtmosphereVolume(_ volume: Double) {
        let clamped = max(0.0, min(1.0, volume))
        queue.async {
            self.atmosphereVolume = Float(clamped)
            self.applyAtmosphereOutputVolume()
        }
    }

    func setSFXVolume(_ volume: Double) {
        let clamped = max(0.0, min(1.0, volume))
        queue.async {
            self.sfxVolume = Float(clamped)
            self.sfxMixer.outputVolume = self.sfxVolume
        }
    }

    func setSFXDuckingActive(_ isActive: Bool) {
        queue.async {
            guard self.sfxDuckingActive != isActive else { return }
            self.sfxDuckingActive = isActive
#if os(iOS)
            self.updateSessionCategoryForSFXDuckingIfNeeded()
#endif
            self.applyAtmosphereOutputVolume(animated: true)
        }
    }

    func setMusicVolume(_ volume: Double) {
        let clamped = max(0.0, min(1.0, volume))
        queue.async {
            self.musicVolume = Float(clamped)
        }
#if os(iOS)
        // ApplicationMusicPlayer does not expose a volume API; system volume is handled via MPVolumeView.
#endif
    }

    func setMasterVolume(_ volume: Double) {
        let clamped = max(0.0, min(1.0, volume))
        queue.async {
            self.masterVolume = Float(clamped)
            self.engine.mainMixerNode.outputVolume = self.masterVolume
        }
        DispatchQueue.main.async {
            Self.setSystemVolume(Float(clamped))
        }
    }

    private func applyStoredVolumes() {
        applyAtmosphereOutputVolume()
        sfxMixer.outputVolume = sfxVolume
        #if os(iOS)
        let systemVolume = Self.currentSystemVolume()
        masterVolume = systemVolume
        engine.mainMixerNode.outputVolume = systemVolume
        DispatchQueue.main.async {
            self.publishSystemVolumeChanged(systemVolume)
        }
        #else
        engine.mainMixerNode.outputVolume = masterVolume
        #endif
    }

    private func applyAtmosphereOutputVolume(animated: Bool = false) {
        let target = atmosphereTargetVolume()
        guard animated else {
            atmosphereRampGeneration &+= 1
            atmosphereMixer.outputVolume = target
            return
        }

        let start = atmosphereMixer.outputVolume
        guard abs(start - target) > 0.0005 else {
            atmosphereRampGeneration &+= 1
            atmosphereMixer.outputVolume = target
            return
        }

        atmosphereRampGeneration &+= 1
        let generation = atmosphereRampGeneration
        let steps = max(1, duckingRampStepCount)
        let stepDuration = duckingRampDuration / Double(steps)
        for step in 1...steps {
            queue.asyncAfter(deadline: .now() + stepDuration * Double(step)) { [weak self] in
                guard let self, self.atmosphereRampGeneration == generation else { return }
                let progress = Float(step) / Float(steps)
                self.atmosphereMixer.outputVolume = start + (target - start) * progress
            }
        }
    }

    private func atmosphereTargetVolume() -> Float {
        let duckMultiplier: Float = sfxDuckingActive ? sfxDuckingFactor : 1.0
        return atmosphereVolume * duckMultiplier
    }

    private static func setSystemVolume(_ value: Float) {
        #if os(iOS)
        Self.ensureVolumeViewAttached()
        let volumeView = Self.volumeView
        if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
            slider.value = value
        }
        #endif
    }

    #if os(iOS)
    private func desiredSessionCategoryOptions() -> AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if sfxDuckingActive {
            options.insert(.duckOthers)
        }
        return options
    }

    private func updateSessionCategoryForSFXDuckingIfNeeded() {
        guard hasConfiguredSession else { return }
        let desiredOptions = desiredSessionCategoryOptions()
        guard desiredOptions != appliedSessionCategoryOptions else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: desiredOptions)
            appliedSessionCategoryOptions = desiredOptions
        } catch {
            print("Failed to update audio session ducking options: \(error)")
        }
    }

    private func configureSystemVolumeObservationIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        if outputVolumeObservation == nil {
            outputVolumeObservation = session.observe(\.outputVolume, options: [.initial, .new]) { [weak self] _, change in
                guard let self else { return }
                let value = change.newValue ?? session.outputVolume
                self.handleObservedSystemVolume(value)
            }
        }
        if appDidBecomeActiveObserver == nil {
            appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.handleObservedSystemVolume(Self.currentSystemVolume())
            }
        }
        if routeChangeObserver == nil {
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.handleObservedSystemVolume(Self.currentSystemVolume())
            }
        }
    }

    private static func ensureVolumeViewAttached() {
        let volumeView = Self.volumeView
        if volumeView.superview == nil {
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first {
                window.addSubview(volumeView)
            }
        }
    }

    private static func currentSystemVolume() -> Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    private func handleObservedSystemVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        queue.async {
            self.masterVolume = clamped
            self.engine.mainMixerNode.outputVolume = clamped
        }
        publishSystemVolumeChanged(clamped)
    }

    private func publishSystemVolumeChanged(_ volume: Float) {
        let clamped = max(0, min(1, volume))
        guard abs(lastPublishedSystemVolume - clamped) > 0.0005 else { return }
        lastPublishedSystemVolume = clamped
        NotificationCenter.default.post(
            name: Self.systemVolumeDidChangeNotification,
            object: nil,
            userInfo: [Self.systemVolumeUserInfoKey: Double(clamped)]
        )
    }
    #endif

    private func ensureMixerConnected(_ mixer: AVAudioMixerNode) {
        if !engine.attachedNodes.contains(mixer) {
            engine.attach(mixer)
        }
        let outputs = engine.outputConnectionPoints(for: mixer, outputBus: 0)
        if outputs.isEmpty {
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        }
    }

    private func ensureNodeConnected(_ node: AVAudioPlayerNode, format: AVAudioFormat, mixer: AVAudioMixerNode) {
        if !engine.attachedNodes.contains(node) {
            engine.attach(node)
        }
        let outputs = engine.outputConnectionPoints(for: node, outputBus: 0)
        if outputs.isEmpty {
            engine.connect(node, to: mixer, format: format)
        }
    }

    private func loadFile(kind: LibraryKind, title: String) -> AVAudioFile? {
        if let localURL = localAssetURL(kind: kind, title: title) {
            if !isFileReadable(localURL) {
                try? FileManager.default.removeItem(at: localURL)
            } else {
            do {
                return try AVAudioFile(forReading: localURL)
            } catch {
                print("Failed to load local audio file: \(error)")
                print("Local file URL: \(localURL.path)")
                try? FileManager.default.removeItem(at: localURL)
            }
            }
        } else {
            print("No local path found for \(kind.rawValue) '\(title)'")
        }

        Task {
        }

        if let bundleURL = bundleAssetURL(kind: kind, title: title) {
            do {
                return try AVAudioFile(forReading: bundleURL)
            } catch {
                print("Failed to load bundled audio file: \(error)")
            }
        }

        return nil
    }

    private func localAssetURL(kind: LibraryKind, title: String) -> URL? {
        guard let path = fetchLocalPath(kind: kind, title: title) else { return nil }
        return AppFilePaths.applicationSupportURL().appendingPathComponent(path)
    }

    private func bundleAssetURL(kind: LibraryKind, title: String) -> URL? {
        let subdirectory: String
        switch kind {
        case .atmosphere:
            subdirectory = "Audio/Atmospheres"
        case .sfx:
            subdirectory = "Audio/SFX"
        default:
            return nil
        }

        let candidates = [title, title.replacingOccurrences(of: " ", with: "_")]
        for candidate in candidates {
            if let url = Bundle.main.url(forResource: candidate, withExtension: "wav", subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }

    private func fetchLocalPath(kind: LibraryKind, title: String) -> String? {
        do {
            return try dbQueue.read { db in
                let sql = """
                SELECT local_asset.local_path
                FROM library_item li
                JOIN item_local_audio ila ON ila.item_id = li.id
                JOIN local_asset ON local_asset.id = ila.asset_id
                WHERE li.kind = ? AND li.title = ?
                LIMIT 1
                """
                let args: [DatabaseValueConvertible] = [kind.rawValue, title]
                return try String.fetchOne(db, SQLRequest(sql: sql, arguments: StatementArguments(args)))
            }
        } catch {
            print("Failed to resolve local path: \(error)")
            return nil
        }
    }

    private func isFileReadable(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }
}

private final class LoopingPlayer {
    private let engine: AVAudioEngine
    private let file: AVAudioFile
    private let nodes: [AVAudioPlayerNode] = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let outputMixer: AVAudioMixerNode
    private let schedulingQueue: DispatchQueue
    private let minimumOverlapDuration: TimeInterval = 2.0
    private let fadeStepCount: Int = 30
    private let fileDuration: TimeInterval

    private var isStopped = true
    private var generation: UInt64 = 0
    private var activeNodeIndex = 0
    private var scheduledWorkItems: [DispatchWorkItem] = []

    init(
        engine: AVAudioEngine,
        file: AVAudioFile,
        outputMixer: AVAudioMixerNode,
        schedulingQueue: DispatchQueue
    ) {
        self.engine = engine
        self.file = file
        self.outputMixer = outputMixer
        self.schedulingQueue = schedulingQueue
        self.fileDuration = max(0, Double(file.length) / file.processingFormat.sampleRate)

        for node in nodes {
            prepareNode(node)
        }
    }

    func start() {
        isStopped = false
        generation &+= 1
        cancelScheduledWorkItems()
        activeNodeIndex = 0

        let firstNode = nodes[activeNodeIndex]
        let secondNode = nodes[1 - activeNodeIndex]
        prepareNode(firstNode)
        prepareNode(secondNode)

        firstNode.stop()
        secondNode.stop()
        firstNode.volume = 1.0
        secondNode.volume = 0.0
        firstNode.scheduleFile(file, at: nil, completionHandler: nil)
        firstNode.play()

        scheduleNextCrossfade(for: generation)
    }

    func stop(fadeOutDuration: TimeInterval = 0, completion: (() -> Void)? = nil) {
        isStopped = true
        generation &+= 1
        let stopGeneration = generation
        cancelScheduledWorkItems()

        let duration = max(0, fadeOutDuration)
        let startingVolumes = nodes.map { max(0, $0.volume) }
        let hasAudibleNode = startingVolumes.contains { $0 > 0.001 }

        guard duration > 0.001, hasAudibleNode else {
            stopAndDetachAllNodes()
            completion?()
            return
        }

        let steps = max(1, fadeStepCount)
        let stepDuration = duration / Double(steps)
        for step in 1...steps {
            scheduleWork(after: stepDuration * Double(step)) { [weak self] in
                guard let self, self.generation == stopGeneration else { return }
                let progress = Float(step) / Float(steps)
                for (index, node) in self.nodes.enumerated() {
                    node.volume = startingVolumes[index] * (1 - progress)
                }
            }
        }

        scheduleWork(after: duration) { [weak self] in
            guard let self, self.generation == stopGeneration else { return }
            self.stopAndDetachAllNodes()
            completion?()
        }
    }

    private func scheduleNextCrossfade(for generation: UInt64) {
        guard !isStopped, self.generation == generation else { return }
        let leadTime = max(0.02, fileDuration - resolvedOverlapDuration)
        scheduleWork(after: leadTime) { [weak self] in
            self?.beginCrossfade(for: generation)
        }
    }

    private func beginCrossfade(for generation: UInt64) {
        guard !isStopped, self.generation == generation else { return }

        let fromIndex = activeNodeIndex
        let toIndex = 1 - fromIndex
        let fromNode = nodes[fromIndex]
        let toNode = nodes[toIndex]

        prepareNode(toNode)
        toNode.stop()
        toNode.volume = 0
        toNode.scheduleFile(file, at: nil, completionHandler: nil)
        toNode.play()

        let overlap = resolvedOverlapDuration
        let steps = max(1, fadeStepCount)
        let stepDuration = max(overlap / Double(steps), 0.01)
        let fromStart = max(0, fromNode.volume)
        let toStart = max(0, toNode.volume)

        for step in 1...steps {
            scheduleWork(after: stepDuration * Double(step)) { [weak self] in
                guard let self, !self.isStopped, self.generation == generation else { return }
                let progress = Float(step) / Float(steps)
                fromNode.volume = fromStart * (1 - progress)
                toNode.volume = toStart + (1 - toStart) * progress
            }
        }

        scheduleWork(after: overlap) { [weak self] in
            guard let self, !self.isStopped, self.generation == generation else { return }
            fromNode.stop()
            fromNode.volume = 0
            toNode.volume = 1
            self.activeNodeIndex = toIndex
            self.scheduleNextCrossfade(for: generation)
        }
    }

    private var resolvedOverlapDuration: TimeInterval {
        let maxAvailable = max(0.05, fileDuration - 0.05)
        return min(minimumOverlapDuration, maxAvailable)
    }

    private func prepareNode(_ node: AVAudioPlayerNode) {
        if !engine.attachedNodes.contains(node) {
            engine.attach(node)
        }
        if engine.outputConnectionPoints(for: node, outputBus: 0).isEmpty {
            engine.connect(node, to: outputMixer, format: file.processingFormat)
        }
    }

    private func stopAndDetachAllNodes() {
        cancelScheduledWorkItems()
        for node in nodes {
            node.stop()
            node.volume = 0
            if engine.attachedNodes.contains(node) {
                engine.detach(node)
            }
        }
    }

    private func cancelScheduledWorkItems() {
        for item in scheduledWorkItems {
            item.cancel()
        }
        scheduledWorkItems.removeAll(keepingCapacity: false)
    }

    private func scheduleWork(after delay: TimeInterval, action: @escaping () -> Void) {
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            action()
            guard let self, let workItem else { return }
            self.scheduledWorkItems.removeAll { $0 === workItem }
        }
        guard let workItem else { return }
        scheduledWorkItems.append(workItem)
        schedulingQueue.asyncAfter(deadline: .now() + max(0, delay), execute: workItem)
    }
}
