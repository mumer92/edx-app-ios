
//
//  VideoPlayer.swift
//  edX
//
//  Created by Salman on 05/03/2018.
//  Copyright © 2018 edX. All rights reserved.
//

import UIKit
import AVKit
import GoogleCast

private enum PlayerState {
    case playing,
         paused,
         stop,
         resume,
         ended,
         chromeCastConnected,
         playingOnChromeCast,
         pausedOnChromeCast,
         readyForRemotePlay
}

private let currentItemStatusKey = "currentItem.status"
private let currentItemPlaybackLikelyToKeepUpKey = "currentItem.playbackLikelyToKeepUp"

protocol VideoPlayerDelegate: class {
    func turnOnVideoTranscripts()
    func turnOffVideoTranscripts()
    func playerDidLoadTranscripts(videoPlayer:VideoPlayer, transcripts: [TranscriptObject])
    func playerWillMoveFromWindow(videoPlayer: VideoPlayer)
    func playerDidTimeout(videoPlayer: VideoPlayer)
    func playerDidFinishPlaying(videoPlayer: VideoPlayer)
    func playerDidFailedPlaying(videoPlayer: VideoPlayer, errorMessage: String)
}

private var playbackLikelyToKeepUpContext = 0
class VideoPlayer: UIViewController,VideoPlayerControlsDelegate,TranscriptManagerDelegate,InterfaceOrientationOverriding {
    
    typealias Environment = OEXInterfaceProvider & OEXAnalyticsProvider & OEXStylesProvider & NetworkManagerProvider
    
    private let environment : Environment
    fileprivate var controls: VideoPlayerControls?
    weak var playerDelegate : VideoPlayerDelegate?
    var isFullScreen : Bool = false {
        didSet {
            controls?.updateFullScreenButtonImage()
        }
    }
    fileprivate let playerView = PlayerView()
    private var timeObserver : AnyObject?
    fileprivate let player = AVPlayer()
    let loadingIndicatorView = UIActivityIndicatorView(style: .white)
    private var lastElapsedTime: TimeInterval = 0
    private var transcriptManager: TranscriptManager?
    private let videoSkipBackwardsDuration: Double = 30
    private var playerTimeBeforeSeek:TimeInterval = 0
    private var playerState: PlayerState = .stop
    private var isObserverAdded: Bool = false
    private let playerTimeOutInterval:TimeInterval = 60.0
    private let preferredTimescale:Int32 = 100
    fileprivate var fullScreenContainerView: UIView?
    
    private var mediaControlsContainerView: UIView!
    private var miniMediaControlsHeightConstraint: NSLayoutConstraint!
    private var miniMediaControlsViewController: GCKUIMiniMediaControlsViewController!
    
    private var overlayLabel: UILabel?
    
    // UIPageViewController keep multiple viewControllers simultanously for smooth switching
    // on view transitioning this method calls for every viewController which cause framing issue for fullscreen mode
    // as we are using rootViewController of keyWindow for fullscreen mode.
    // We introduce the variable isVisible to track the visible viewController during pagination.
    fileprivate var isVisible: Bool = false
    
    var videoTitle: String = Strings.untitled
    
    private let loadingIndicatorViewSize = CGSize(width: 50.0, height: 50.0)
    
    fileprivate var video: OEXHelperVideoDownload? {
        didSet {
            initializeSubtitles()
        }
    }
    
    lazy fileprivate var movieBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0.5
        return view
    }()
    
    var rate: Float {
        get {
            return player.rate
        }
        set {
            player.rate = newValue
        }
    }
    
    var duration: CMTime {
        return player.currentItem?.duration ?? CMTime()
    }
    
    var isPlaying: Bool {
        return rate != 0
    }
    
    var currentTime: TimeInterval {
        return player.currentItem?.currentTime().seconds ?? 0
    }
    
    var playableDuration: TimeInterval {
        var result: TimeInterval = 0
        if let loadedTimeRanges = player.currentItem?.loadedTimeRanges, loadedTimeRanges.count > 0  {
            let timeRange = loadedTimeRanges[0].timeRangeValue
            let startSeconds: Float64 = CMTimeGetSeconds(timeRange.start)
            let durationSeconds: Float64 = CMTimeGetSeconds(timeRange.duration)
            result =  TimeInterval(startSeconds) + TimeInterval(durationSeconds)
        }
        return result
    }
    
    private lazy var leftSwipeGestureRecognizer : UISwipeGestureRecognizer = {
        let gesture = UISwipeGestureRecognizer()
        gesture.direction = .left
        gesture.addAction { [weak self] _ in
            self?.controls?.nextButtonClicked()
        }
        
        return gesture
    }()
    
    private lazy var rightSwipeGestureRecognizer : UISwipeGestureRecognizer = {
        let gesture = UISwipeGestureRecognizer()
        gesture.direction = .right
        gesture.addAction { [weak self] _ in
            self?.controls?.previousButtonClicked()
        }
        
        return gesture
    }()
    
    // Adding this accessibilityPlayerView for the player accessibility voice over
    private let accessibilityPlayerView : UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.clear
        
        return view
    }()
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    fileprivate let castManager = ChromeCastManager.shared
    
    init(environment : Environment) {
        self.environment = environment
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        createPlayer()
        view.backgroundColor = .black
        loadingIndicatorView.hidesWhenStopped = true
        listenForCastConnection()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let parentController = self.parent?.parent as? CastButtonDelegate {
                let button = parentController.castButton
                self.castManager.presentInductoryOverlay(with: button)
            }
        }
        
        
//        NotificationCenter.default.addObserver(self, selector: #selector(castDeviceDidChange),
//                                               name: NSNotification.Name.gckCastStateDidChange,
//                                               object: castManager)
    }
    
    @objc func castDeviceDidChange(_: Notification) {
        if GCKCastContext.sharedInstance().castState != .noDevicesAvailable {
           
        }
    }
    
    func checkIfChromecastIsConnected() {
        if castManager.isconnectedToChromeCast {
            playerState = .chromeCastConnected
        }
    }
    
    private func playRemotely(video: OEXHelperVideoDownload) {
        guard let videoURL = video.summary?.videoURL, var url = URL(string: videoURL) else {
            return
        }
        
        self.video = video
        
        let fileManager = FileManager.default
        let path = "\(video.filePath).mp4"
        let fileExists : Bool = fileManager.fileExists(atPath: path)
        if fileExists {
            url = URL(fileURLWithPath: path)
        }
        loadingIndicatorView.stopAnimating()

        var elapsedtime = 0.0
        
        if let video = self.video {
            elapsedtime = Double(environment.interface?.lastPlayedInterval(forVideo: video) ?? Float(lastElapsedTime))
        }
        
        var thumbnail = video.summary?.videoThumbnailURL
        
        if thumbnail == nil {
            var courseImageURL: String?
            if let courseID = video.course_id,
                let course = environment.interface?.enrollmentForCourse(withID: courseID)?.course {
                courseImageURL = course.courseImageURL
                
                if let relativeImageURL = courseImageURL,
                    let imageURL = URL(string: relativeImageURL, relativeTo: self.environment.networkManager.baseURL) {
                    thumbnail = imageURL.absoluteString
                }
            }
        }
       
        let castMediaInfo = castManager.buildMediaInformation(contentID: url.absoluteString, title: video.summary?.name ?? "", description: "", studio: "", duration: 0, streamType: GCKMediaStreamType.buffered, thumbnailUrl: thumbnail, customData: nil)
        
        castManager.startPlayingItemOnChromeCast(mediaInfo: castMediaInfo, at: elapsedtime) { done in
            if done {
                print("done")
            } else {
                print("something went wrong")
            }
        }
        playerState = .playingOnChromeCast
    }
    
    private func pauseCastPlay() {
        playerState = .pausedOnChromeCast
        castManager.pauseItemOnChromeCast(at: nil) { (done) in
            if !done {
                self.playerState = .paused
            }
        }
    }
    
    private func continueCastPlay() {
        playerState = .playingOnChromeCast
        castManager.playItemOnChromeCast(to: nil) { (done) in
            if !done {
                self.playerState = .paused
            }
        }
    }
    
    private func addObservers() {
        if !isObserverAdded {
            isObserverAdded = true
            player.addObserver(self, forKeyPath: currentItemPlaybackLikelyToKeepUpKey,
                               options: .new, context: &playbackLikelyToKeepUpContext)
            
            
            player.addObserver(self, forKeyPath: currentItemStatusKey,
                               options: .new, context: nil)
            
            let timeInterval: CMTime = CMTimeMakeWithSeconds(1.0, preferredTimescale: 10)
            timeObserver = player.addPeriodicTimeObserver(forInterval: timeInterval, queue: DispatchQueue.main) { [weak self]
                (elapsedTime: CMTime) -> Void in
                self?.observeProgress(elapsedTime: elapsedTime)
                } as AnyObject
            
            NotificationCenter.default.oex_addObserver(observer: self, name: UIApplication.willResignActiveNotification.rawValue) {(notification, observer, _) in
                observer.pause()
                observer.controls?.setPlayPauseButtonState(isSelected: true)
            }
            
            NotificationCenter.default.oex_addObserver(observer: self, name: UIAccessibilityVoiceOverStatusChanged, action: { (_, observer, _) in
                observer.voiceOverStatusChanged()
            })
        }
    }
    
    private func voiceOverStatusChanged() {
        hideAndShowControls(isHidden: !UIAccessibility.isVoiceOverRunning)
    }
    
    private func observeProgress(elapsedTime: CMTime) {
        let duration = CMTimeGetSeconds(self.duration)
        if duration.isFinite {
            let elapsedTime = CMTimeGetSeconds(elapsedTime)
            controls?.durationSliderValue = Float(elapsedTime / duration)
            controls?.updateTimeLabel(elapsedTime: elapsedTime, duration: duration)
        }
    }
    
    private func createPlayer() {
        view.addSubview(playerView)
        
        // Adding this accessibilityPlayerView just for the accibility voice over
        playerView.addSubview(accessibilityPlayerView)
        accessibilityPlayerView.isAccessibilityElement = true
        accessibilityPlayerView.accessibilityLabel = Strings.accessibilityVideo
        
        playerView.playerLayer.player = player
        view.layer.insertSublayer(playerView.playerLayer, at: 0)
        playerView.addSubview(loadingIndicatorView)
        
        if #available(iOS 10.0, *) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
        } else {
            // Fallback on earlier versions
            // Workaround until https://forums.swift.org/t/using-methods-marked-unavailable-in-swift-4-2/14949 isn't fixed
            AVAudioSession.sharedInstance().perform(NSSelectorFromString("setCategory:error:"), with: AVAudioSession.Category.playback)
            
        }
        setConstraints()
    }
    
    private func createControls(isSelected: Bool = false) {
        controls = VideoPlayerControls(environment: environment, player: self)
        controls?.setPlayPauseButtonState(isSelected: isSelected)
        controls?.delegate = self
        if let controls = controls {
            controls.tag = 100
            playerView.addSubview(controls)
        }
        controls?.snp.makeConstraints() { make in
            make.edges.equalTo(playerView)
        }
    }
    
    private func removeControls() {
        UIView.animate(withDuration: 0.2) {
            if let view = self.playerView.viewWithTag(100) {
                view.removeFromSuperview()
            }
        }
    }
    
    private func addOverlyForRemotePlay() {
        if overlayLabel == nil {
            overlayLabel = UILabel(frame: view.frame)
            overlayLabel?.text = "Video is casting to remote device"
            overlayLabel?.textAlignment = .center
            overlayLabel?.textColor = .white
            overlayLabel?.center = self.view.center
            overlayLabel?.tag = 120
            self.view.addSubview(overlayLabel!)
        }
       
        overlayLabel?.isHidden = false
    }
    
    private func removeOverlayForRemotePlay() {
        overlayLabel?.isHidden = true
    }
    
    private func initializeSubtitles() {
        if let video = video, transcriptManager == nil {
            transcriptManager = TranscriptManager(environment: environment, video: video)
            transcriptManager?.delegate = self
            
            if let ccSelectedLanguage = OEXInterface.getCCSelectedLanguage(), let transcriptURL = video.summary?.transcripts?[ccSelectedLanguage] as? String, !ccSelectedLanguage.isEmpty, !transcriptURL.isEmpty {
                controls?.activateSubTitles()
            }
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        playerView.frame = view.bounds
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &playbackLikelyToKeepUpContext, let currentItem = player.currentItem {
            if currentItem.isPlaybackLikelyToKeepUp {
                loadingIndicatorView.stopAnimating()
            } else {
                loadingIndicatorView.startAnimating()
            }
        }
        else if keyPath == currentItemStatusKey {
            if let newStatusAsNumber = change?[NSKeyValueChangeKey.newKey] as? NSNumber, let newStatus = AVPlayerItem.Status(rawValue: newStatusAsNumber.intValue) {
                switch newStatus {
                case .readyToPlay:
                    //This notification call specifically for test cases in readyToPlay state
                    perform(#selector(t_postNotification))
                    
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(movieTimedOut), object: nil)
                    controls?.isTapButtonHidden = false
                    break
                case .unknown:
                    controls?.isTapButtonHidden = true
                    break
                case .failed:
                    controls?.isTapButtonHidden = true
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func setConstraints() {
        loadingIndicatorView.snp.makeConstraints() { make in
            make.center.equalToSuperview()
            make.height.equalTo(loadingIndicatorViewSize.height)
            make.width.equalTo(loadingIndicatorViewSize.width)
        }
        
        accessibilityPlayerView.snp.makeConstraints { make in
            make.edges.equalTo(playerView)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        applyScreenOrientation()
        checkIfChromecastIsConnected()
        
        if mediaControlsContainerView == nil {
            castManager.isMiniPlayerAdded = true
            createContainer()
            createMiniMediaControl()
        }
    }
    
    private func applyScreenOrientation() {
        if isVerticallyCompact() {
            DispatchQueue.main.async {[weak self] in
                self?.setFullscreen(fullscreen: true, animated: false, with: .portrait, forceRotate: false)
            }
        }
    }
    
    func play(video: OEXHelperVideoDownload) {
        if castManager.isconnectedToChromeCast {
            playRemotely(video: video)
        } else {
            applyScreenOrientation()
            createControls()
            playerDelegate?.turnOnVideoTranscripts()
            playLocally(video: video)
        }
    }
    
    private func playLocally(video: OEXHelperVideoDownload, at timeInterval: Double = 0.0) {
        guard let videoURL = video.summary?.videoURL, var url = URL(string: videoURL) else {
            return
        }
        self.video = video
        controls?.video = video
        let fileManager = FileManager.default
        let path = "\(video.filePath).mp4"
        let fileExists : Bool = fileManager.fileExists(atPath: path)
        if fileExists {
            url = URL(fileURLWithPath: path)
        } else if video.downloadState == .complete {
            playerDelegate?.playerDidFailedPlaying(videoPlayer: self, errorMessage: Strings.videoContentNotAvailable)
        }
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        loadingIndicatorView.startAnimating()
        removeOverlayForRemotePlay()
        addObservers()
        //let timeInterval = TimeInterval(environment.interface?.lastPlayedInterval(forVideo: video) ?? 0)
        play(at: timeInterval)
        controls?.isTapButtonHidden = true
        NotificationCenter.default.oex_addObserver(observer: self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime.rawValue, object: player.currentItem as Any) {(notification, observer, _) in
            observer.playerDidFinishPlaying(note: notification)
        }
        perform(#selector(movieTimedOut), with: nil, afterDelay: playerTimeOutInterval)
        playerState = .playing
    }
    
    private func play(at timeInterval: TimeInterval) {
        player.play()
        lastElapsedTime = timeInterval
        var resumeObserver: AnyObject?
        resumeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 3), queue: DispatchQueue.main) { [weak self]
            (elapsedTime: CMTime) -> Void in
            if self?.player.currentItem?.status == .readyToPlay {
                self?.playerState = .playing
                self?.resume(at: timeInterval)
                if let observer = resumeObserver {
                    self?.player.removeTimeObserver(observer)
                }
            }
            } as AnyObject
    }
    
    @objc private func movieTimedOut() {
        stop()
        playerDelegate?.playerDidTimeout(videoPlayer: self)
    }
    
    fileprivate func resume() {
        resume(at: lastElapsedTime)
    }
    
    func resume(at time: TimeInterval) {
        if player.currentItem?.status == .readyToPlay {
            player.currentItem?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: preferredTimescale), toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero) { [weak self]
                (completed: Bool) -> Void in
                self?.player.play()
                self?.playerState = .playing
                let speed = OEXInterface.getCCSelectedPlaybackSpeed()
                self?.rate = OEXInterface.getOEXVideoSpeed(speed)
            }
        }
    }
    
    fileprivate func pause() {
        player.pause()
        playerState = .paused
        saveCurrentTime()
    }
    
    private func saveCurrentTime() {
        lastElapsedTime = currentTime
        if let video = video {
            environment.interface?.markLastPlayedInterval(Float(currentTime), forVideo: video)
            let state = doublesWithinEpsilon(left: duration.seconds, right: currentTime) ? OEXPlayedState.watched : OEXPlayedState.partiallyWatched
            environment.interface?.markVideoState(state, forVideo: video)
        }
    }
    
    fileprivate func stop() {
        saveCurrentTime()
        player.actionAtItemEnd = .pause
        player.replaceCurrentItem(with: nil)
        playerState = .stop
    }
    
    func subTitle(at elapseTime: Float64) -> String {
        return transcriptManager?.transcript(at: elapseTime) ?? ""
    }
    
    fileprivate func addGestures() {
        
        if let _ = playerView.gestureRecognizers?.contains(leftSwipeGestureRecognizer), let _ = playerView.gestureRecognizers?.contains(rightSwipeGestureRecognizer) {
            removeGestures()
        }
        
        playerView.addGestureRecognizer(leftSwipeGestureRecognizer)
        playerView.addGestureRecognizer(rightSwipeGestureRecognizer)
        
        if let videoId = video?.summary?.videoID, let courseId = video?.course_id, let unitUrl = video?.summary?.unitURL {
            environment.analytics.trackVideoOrientation(videoId, courseID: courseId, currentTime: CGFloat(currentTime), mode: true, unitURL: unitUrl)
        }
    }
    
    private func removeGestures() {
        playerView.removeGestureRecognizer(leftSwipeGestureRecognizer)
        playerView.removeGestureRecognizer(rightSwipeGestureRecognizer)
        
        if let videoId = video?.summary?.videoID, let courseId = video?.course_id, let unitUrl = video?.summary?.unitURL {
            environment.analytics.trackVideoOrientation(videoId, courseID: courseId, currentTime: CGFloat(currentTime), mode: false, unitURL: unitUrl)
        }
    }
    
    private func removeObservers() {
        if isObserverAdded {
            if let observer = timeObserver {
                player.removeTimeObserver(observer)
                timeObserver = nil
            }
            player.removeObserver(self, forKeyPath: currentItemPlaybackLikelyToKeepUpKey)
            player.removeObserver(self, forKeyPath: currentItemStatusKey)
            NotificationCenter.default.removeObserver(self)
            isObserverAdded = false
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        pause()
        removeMiniMediaContainerView()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        resetPlayer()
    }
        
    private func resetPlayer() {
        movieBackgroundView.removeFromSuperview()
        stop()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(movieTimedOut), object: nil)
        controls?.reset()
    }
    
    func resetPlayerView() {
        if !(view.subviews.contains(playerView)) {
            playerDelegate?.playerWillMoveFromWindow(videoPlayer: self)
            view.addSubview(playerView)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            removeGestures()
            controls?.showHideNextPrevious(isHidden: true)
        }
    }
    
    func playerDidFinishPlaying(note: NSNotification) {
        playerDelegate?.playerDidFinishPlaying(videoPlayer: self)
    }
    
    // MARK:- TransctiptManagerDelegate method
    func transcriptsLoaded(manager: TranscriptManager, transcripts: [TranscriptObject]) {
        playerDelegate?.playerDidLoadTranscripts(videoPlayer: self, transcripts: transcripts)
    }
    
    // MARK:- Player control delegate method
    func playPausePressed(playerControls: VideoPlayerControls, isPlaying: Bool) {
        if playerState == .readyForRemotePlay {
            removeControls()
            playRemotely(video: video!)
            environment.interface?.sendAnalyticsEvents(.play, withCurrentTime: currentTime, forVideo: video)
        } else if playerState == .playing {
            pause()
            environment.interface?.sendAnalyticsEvents(.pause, withCurrentTime: currentTime, forVideo: video)
        }
        else {
            resume()
            environment.interface?.sendAnalyticsEvents(.play, withCurrentTime: currentTime, forVideo: video)
        }
    }
    
    func seekBackwardPressed(playerControls: VideoPlayerControls) {
        let oldTime = currentTime
        let videoDuration = CMTimeGetSeconds(duration)
        let elapsedTime: Float64 = videoDuration * Float64(playerControls.durationSliderValue)
        let backTime = elapsedTime > videoSkipBackwardsDuration ? elapsedTime - videoSkipBackwardsDuration : 0.0
        playerControls.updateTimeLabel(elapsedTime: backTime, duration: videoDuration)
        seek(to: backTime)

        if let videoId = video?.summary?.videoID, let courseId = video?.course_id, let unitUrl = video?.summary?.unitURL {
            environment.analytics.trackVideoSeekRewind(videoId, requestedDuration:-videoSkipBackwardsDuration, oldTime:oldTime, newTime: currentTime, courseID: courseId, unitURL: unitUrl, skipType: "skip")
        }
    }
    
    func fullscreenPressed(playerControls: VideoPlayerControls) {
        DispatchQueue.main.async {[weak self] in
            if let weakSelf = self {
                weakSelf.setFullscreen(fullscreen: !weakSelf.isFullScreen, animated: true, with: UIInterfaceOrientation.landscapeLeft, forceRotate:!weakSelf.isVerticallyCompact())
            }
        }
    }
    
    func sliderValueChanged(playerControls: VideoPlayerControls) {
        let videoDuration = CMTimeGetSeconds(duration)
        let elapsedTime: Float64 = videoDuration * Float64(playerControls.durationSliderValue)
        playerControls.updateTimeLabel(elapsedTime: elapsedTime, duration: videoDuration)
    }
    
    func sliderTouchBegan(playerControls: VideoPlayerControls) {
        playerTimeBeforeSeek = currentTime
        player.pause()
        NSObject.cancelPreviousPerformRequests(withTarget: playerControls)
    }
    
    func sliderTouchEnded(playerControls: VideoPlayerControls) {
        let videoDuration = CMTimeGetSeconds(duration)
        let elapsedTime: Float64 = videoDuration * Float64(playerControls.durationSliderValue)
        playerControls.updateTimeLabel(elapsedTime: elapsedTime, duration: videoDuration)
        seek(to: elapsedTime)
        if let videoId = video?.summary?.videoID, let courseId = video?.course_id, let unitUrl = video?.summary?.unitURL {
            environment.analytics.trackVideoSeekRewind(videoId, requestedDuration:currentTime - playerTimeBeforeSeek, oldTime:playerTimeBeforeSeek, newTime: currentTime, courseID: courseId, unitURL: unitUrl, skipType: "slide")
        }
    }
    
    func seek(to time: Double) {
        if player.currentItem?.status != .readyToPlay { return }

        player.currentItem?.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: preferredTimescale), toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero) { [weak self]
            (completed: Bool) -> Void in
            if self?.playerState == .playing {
                self?.controls?.autoHide()
                self?.player.play()
            }
            else {
                self?.saveCurrentTime()
            }
        }
    }
    
    fileprivate func setVideoSpeed(speed: OEXVideoSpeed) {
        pause()
        OEXInterface.setCCSelectedPlaybackSpeed(speed)
        resume()
    }
    
    func hideAndShowControls(isHidden: Bool) {
        controls?.hideAndShowControls(isHidden: isHidden)
    }
    
    // MARK:- VideoPlayer Controls Delegate Methods
    func setPlayBackSpeed(playerControls: VideoPlayerControls, speed: OEXVideoSpeed) {
        let oldSpeed = rate
        setVideoSpeed(speed: speed)
        
        if let videoId = video?.summary?.videoID, let courseId = video?.course_id, let unitUrl = video?.summary?.unitURL {
            environment.analytics.trackVideoSpeed(videoId, currentTime: currentTime, courseID: courseId, unitURL: unitUrl, oldSpeed: String(format: "%.1f", oldSpeed), newSpeed: String(format: "%.1f", OEXInterface.getOEXVideoSpeed(speed)))
        }
    }
    
    func captionUpdate(playerControls: VideoPlayerControls, language: String) {
        OEXInterface.setCCSelectedLanguage(language)
        if language.isEmpty {
            playerControls.deAvtivateSubTitles()
        }
        else {
            transcriptManager?.loadTranscripts()
            playerControls.activateSubTitles()
            if let videoId = video?.summary?.videoID, let courseId = video?.course_id, let unitUrl = video?.summary?.unitURL {
                environment.analytics.trackTranscriptLanguage(videoId, currentTime: currentTime, language: language, courseID: courseId, unitURL: unitUrl)
            }
        }
    }

    func setVideo(video: OEXHelperVideoDownload){
        self.video = video
    }

    deinit {
        removeObservers()
    }
    
    func setFullscreen(fullscreen: Bool, animated: Bool, with deviceOrientation: UIInterfaceOrientation, forceRotate rotate: Bool) {
        if !isVisible { return }
        isFullScreen = fullscreen
        if fullscreen {
            
            fullScreenContainerView = UIApplication.shared.keyWindow?.rootViewController?.view ?? UIApplication.shared.windows[0].rootViewController?.view
            
            if movieBackgroundView.frame == .zero {
                movieBackgroundView.frame = movieBackgroundFrame
            }
            
            if let subviews = fullScreenContainerView?.subviews, !subviews.contains(movieBackgroundView){
                fullScreenContainerView?.addSubview(movieBackgroundView)
            }
            
            UIView.animate(withDuration: animated ? 0.1 : 0.0, delay: 0.0, options: .curveLinear, animations: {[weak self]() -> Void in
                self?.movieBackgroundView.alpha = 1.0
                }, completion: {[weak self](_ finished: Bool) -> Void in
                    self?.view.alpha = 0.0
                    if let owner = self {
                        if !(owner.movieBackgroundView.subviews.contains(owner.playerView)) {
                            owner.movieBackgroundView.addSubview(owner.playerView)
                            owner.movieBackgroundView.layer.insertSublayer(owner.playerView.playerLayer, at: 0)
                            owner.addGestures()
                            owner.controls?.showHideNextPrevious(isHidden: false)
                        }
                    }
                    self?.rotateMoviePlayer(for: deviceOrientation, animated: animated, forceRotate: rotate, completion: {[weak self]() -> Void in
                        UIView.animate(withDuration: animated ? 0.1 : 0.0, delay: 0.0, options: .curveLinear, animations: {[weak self]() -> Void in
                            self?.view.alpha = 1.0
                            }, completion: nil)
                    })
            })
        }
        else {
            UIView.animate(withDuration: animated ? 0.1 : 0.0, delay: 0.0, options: .curveLinear, animations: {[weak self]() -> Void in
                self?.view.alpha = 0.0
                }, completion: {[weak self](_ finished: Bool) -> Void in
                    self?.view.alpha = 1.0
                    UIView.animate(withDuration: animated ? 0.1 : 0.0, delay: 0.0, options: .curveLinear, animations: {[weak self]() -> Void in
                        self?.movieBackgroundView.alpha = 0.0
                        }, completion: {[weak self](_ finished: Bool) -> Void in
                            self?.movieBackgroundView.removeFromSuperview()
                            self?.resetPlayerView()
                    })
            })
        }
    }
}

extension VideoPlayer {
    
    var movieBackgroundFrame: CGRect {
        if #available(iOS 11, *) {
            if let safeBounds = fullScreenContainerView?.safeAreaLayoutGuide.layoutFrame {
                return safeBounds
            }
        }
        else if let containerBounds = fullScreenContainerView?.bounds {
            return containerBounds
        }
        return .zero
    }
    
    func rotateMoviePlayer(for orientation: UIInterfaceOrientation, animated: Bool, forceRotate rotate: Bool, completion: (() -> Void)? = nil) {
        var angle: Double = 0
        var movieFrame: CGRect = CGRect(x: movieBackgroundFrame.maxX, y: movieBackgroundFrame.maxY, width: movieBackgroundFrame.width, height: movieBackgroundFrame.height)
        
        // Used to rotate the view on Fulscreen button click
        // Rotate it forcefully as the orientation is on the UIDeviceOrientation
        if rotate && orientation == .landscapeLeft {
            angle = Double.pi/2
            // MOB-1053
            movieFrame = CGRect(x: movieBackgroundFrame.maxX, y: movieBackgroundFrame.maxY, width: movieBackgroundFrame.height, height: movieBackgroundFrame.width)
        }
        else if rotate && orientation == .landscapeRight {
            angle = -Double.pi/2
            // MOB-1053
            movieFrame = CGRect(x: movieBackgroundFrame.maxX, y: movieBackgroundFrame.maxY, width: movieBackgroundFrame.height, height: movieBackgroundFrame.width)
        }
        
        if animated {
            UIView.animate(withDuration: 0.1, delay: 0.0, options: .curveEaseInOut, animations: { [weak self] in
                if let weakSelf = self {
                    weakSelf.movieBackgroundView.transform = CGAffineTransform(rotationAngle: CGFloat(angle))
                    weakSelf.movieBackgroundView.frame = weakSelf.movieBackgroundFrame
                    weakSelf.view.frame = movieFrame
                }
                }, completion: nil)
        }
        else {
            movieBackgroundView.transform = CGAffineTransform(rotationAngle: CGFloat(angle))
            movieBackgroundView.frame = movieBackgroundFrame
            view.frame = movieFrame
        }
    }
}

extension VideoPlayer {
    private func listenForCastConnection() {
        let sessionStatusListener: (ChromeCastSessionStatus) -> Void = { status in
            print("Chromecast Status: \(status)")
            switch status {
            case .playing:
                self.playerDelegate?.turnOffVideoTranscripts()
                self.addOverlyForRemotePlay()
            case .started:
                self.playerDelegate?.turnOffVideoTranscripts()
                self.stop()
                self.hideAndShowControls(isHidden: true)
//                self.removeControls()
                self.addOverlyForRemotePlay()
                self.playRemotely(video: self.video!)
            case .resumed:
                self.playerDelegate?.turnOffVideoTranscripts()
                self.stop()
                self.hideAndShowControls(isHidden: true)
//                self.removeControls()
                self.addOverlyForRemotePlay()
                self.continueCastPlay()
            case .ended, .failed:
                self.playerDelegate?.turnOnVideoTranscripts()
                self.removeOverlayForRemotePlay()
//                self.createControls()
                self.controls?.hideAndShowControlsExceptPlayPause(isHidden: true)
                if self.playerState == .playingOnChromeCast {
                    self.playerState = .paused
                } else {
                    self.playerState = .playing
                    self.castManager.getPlayBackTimeFromChromeCast { timeInterval in
                        self.playLocally(video: self.video!, at: timeInterval ?? 0.0)
                    }
                }
            case .finishedPlaying:
                self.playerState = .readyForRemotePlay
                self.applyScreenOrientation()
                self.removeOverlayForRemotePlay()
                self.controls?.hideAndShowControlsExceptPlayPause(isHidden: true)

//                self.createControls(isSelected: true)
            default: break
            }
        }
        
        castManager.addChromeCastSessionStatusListener(listener: sessionStatusListener)
    }
}

extension VideoPlayer: GCKUIMiniMediaControlsViewControllerDelegate {
    public func miniMediaControlsViewController(_ miniMediaControlsViewController: GCKUIMiniMediaControlsViewController, shouldAppear: Bool) {
        updateControlBarsVisibility()
    }
}

extension VideoPlayer {
    fileprivate func updateControlBarsVisibility() {
        guard let parent = self.parent?.parent as? CourseContentPageViewController else { return }
        
        if mediaControlsContainerView == nil {
            castManager.isMiniPlayerAdded = true
            createContainer()
            createMiniMediaControl()
        }

        if miniMediaControlsViewController.active {
            miniMediaControlsHeightConstraint.constant = miniMediaControlsViewController.minHeight
            parent.view.bringSubviewToFront(mediaControlsContainerView)
        } else {
            miniMediaControlsHeightConstraint.constant = 0
        }
        
        UIView.animate(withDuration: 0.3, animations: {
            parent.view.layoutIfNeeded()
        }) { _ in
            if self.mediaControlsContainerView != nil {
                self.mediaControlsContainerView.alpha = 1
                self.miniMediaControlsViewController.view.alpha = 1
            }
        }
    }
    
    private func createContainer() {
        guard let parent = self.parent?.parent as? CourseContentPageViewController else { return }

        mediaControlsContainerView = UIView(frame: CGRect(x: 0, y: view.frame.maxY, width: view.frame.width, height: 0))
        mediaControlsContainerView.accessibilityIdentifier = "mediaControlsContainerView"
        mediaControlsContainerView.tag = 300
        
        parent.view.addSubview(mediaControlsContainerView)
        
        
        mediaControlsContainerView.snp.makeConstraints { make in
            var bottomSafeArea: CGFloat
            
            if #available(iOS 11.0, *) {
                let window = UIApplication.shared.keyWindow
                bottomSafeArea = window?.safeAreaInsets.bottom ?? 34
            } else {
                bottomSafeArea = bottomLayoutGuide.length
            }
            
            let toolbarHeight = parent.navigationController?.toolbar.frame.size.height ?? 50
            
            let bottomContrainHeight = bottomSafeArea + toolbarHeight
            
            make.bottom.equalTo(parent.view.snp.bottom).offset(-1 * (bottomContrainHeight))
            make.leading.equalTo(parent.view)
            make.trailing.equalTo(parent.view)
            make.height.equalTo(mediaControlsContainerView)
        }
        miniMediaControlsHeightConstraint = mediaControlsContainerView.heightAnchor.constraint(equalToConstant: 0)
        miniMediaControlsHeightConstraint.isActive = true
    }
    
    private func createMiniMediaControl() {
        miniMediaControlsViewController = castManager.createMiniMediaControl()
        miniMediaControlsViewController.delegate = self
        mediaControlsContainerView.alpha = 0
        miniMediaControlsViewController.view.alpha = 0
        miniMediaControlsHeightConstraint.constant = miniMediaControlsViewController.minHeight
        
        addViewController(miniMediaControlsViewController, in: mediaControlsContainerView)
        
        updateControlBarsVisibility()
    }
    
    private func addViewController(_ viewController: UIViewController?, in containerView: UIView) {
        guard let parent = self.parent?.parent as? CourseContentPageViewController else { return }

        if let viewController = viewController {
            viewController.view.isHidden = true
            parent.addChild(viewController)
            viewController.view.frame = containerView.bounds
            containerView.addSubview(viewController.view)
            viewController.didMove(toParent: self)
            viewController.view.isHidden = false
        }
    }
    
    private func removeMiniMediaContainerView() {
        guard let parent = self.parent?.parent as? CourseContentPageViewController else { return }
        if let viewWithTag = parent.view.viewWithTag(300) {
            viewWithTag.removeFromSuperview()
        }
        if miniMediaControlsViewController != nil {
            miniMediaControlsViewController.delegate = nil
            miniMediaControlsViewController.willMove(toParent: nil)
            miniMediaControlsViewController.removeFromParent()
            miniMediaControlsViewController.view.removeFromSuperview()
            mediaControlsContainerView = nil
        }
        castManager.isMiniPlayerAdded = false
    }
}

// Specific for test cases
extension VideoPlayer {
    var t_controls: VideoPlayerControls? {
        return controls
    }
    
    var t_video: OEXHelperVideoDownload? {
        return video
    }
    
    var t_playerCurrentState: AVPlayerItem.Status {
        return player.currentItem?.status ?? .unknown
    }
    
    var t_playBackSpeed: OEXVideoSpeed {
        set {
            setVideoSpeed(speed: newValue)
        }
        get {
            return OEXInterface.getCCSelectedPlaybackSpeed()
        }
    }
    
    var t_subtitleActivated: Bool {
        return controls?.t_subtitleActivated ?? false
    }
    
    var t_captionLanguage: String {
        set {
            controls?.setCaption(language: newValue)
        }
        get {
            return OEXInterface.getCCSelectedLanguage() ?? "en"
        }
    }
    
    func t_pause() {
        pause()
    }
    
    func t_stop() {
        stop()
    }
    
    func t_resume() {
        resume()
    }
    
    @objc fileprivate func t_postNotification() {
        //This notification call specifically for test cases in readyToPlay state
        NotificationCenter.default.post(name: Notification.Name.init("TestPlayerStatusDidChangedToReadyState"), object: nil)
    }
}
