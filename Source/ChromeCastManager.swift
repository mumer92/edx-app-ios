//
//  ChromeCastManager.swift
//  edX
//
//  Created by Muhammad Umer on 10/9/19.
//  Copyright © 2019 edX. All rights reserved.
//

import Foundation
import GoogleCast

enum ChromeCastSessionStatus {
    case initial
    case started
    case resumed
    case suspended
    case ended
    case failed(Error)
    case connected
}

typealias CastItemCompletion = (Bool) -> Void
var status = ChromeCastSessionStatus.initial

class ChromeCastManager: NSObject {
    static let shared = ChromeCastManager()
    
    private let castContext = GCKCastContext.sharedInstance()
    
    // change following to applicationID obtained by Cast Developer Console
    private let castReceiverAppID = kGCKDefaultMediaReceiverApplicationID
    private let castDebugLoggingEnabled = true
    
    private var status = ChromeCastSessionStatus.initial
    private var castSessionManager: GCKSessionManager!
    var castDiscoveryManager: GCKDiscoveryManager!
    
    var isconnectedToChromeCast: Bool {
        return castSessionManager.hasConnectedSession()
    }
    
    private override init() {
        super.init()
        self.initialize()
    }
    
    func initialize() {
        createCastContext()
        createCastSessionManager()
        createDiscoveryManager()
        createRemoteMediaListnerManager()
    }
    
    private func createCastContext() {
        let criteria = GCKDiscoveryCriteria(applicationID: castReceiverAppID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)
        castContext.useDefaultExpandedMediaControls = true
    }
    
    private func createCastSessionManager() {
        castSessionManager = castContext.sessionManager
        castSessionManager.add(self)
    }
    
    private func createDiscoveryManager() {
        castDiscoveryManager = castContext.discoveryManager
        castDiscoveryManager.add(self)
        castDiscoveryManager.passiveScan = false
        castDiscoveryManager.startDiscovery()
    }
    
    private func createRemoteMediaListnerManager() {
        guard let currenctSession = castSessionManager.currentCastSession else { return }
        currenctSession.remoteMediaClient?.add(self)
    }
    
    func buildMediaInformation(contentID: String, title: String, description: String, studio: String, duration: TimeInterval, streamType: GCKMediaStreamType, thumbnailUrl: String?, customData: Any?) -> GCKMediaInformation {
        let metadata = buildMetadata(title: title, description: description, studio: studio, thumbnailUrl: thumbnailUrl)
        
        let mediaInformationBuilder = GCKMediaInformationBuilder()
        mediaInformationBuilder.contentID = contentID
        mediaInformationBuilder.streamType = streamType
        mediaInformationBuilder.contentType = ""
        mediaInformationBuilder.metadata = metadata
        mediaInformationBuilder.adBreaks = nil
        mediaInformationBuilder.adBreakClips = nil
        mediaInformationBuilder.streamDuration = duration
        mediaInformationBuilder.mediaTracks = nil
        mediaInformationBuilder.textTrackStyle = nil
        mediaInformationBuilder.customData = nil
        let mediaInformation = mediaInformationBuilder.build()
        
        return mediaInformation
    }
    
    private func buildMetadata(title: String, description: String, studio: String, thumbnailUrl: String?) -> GCKMediaMetadata {
        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        metadata.setString(description, forKey: "description")
        let deviceName = castSessionManager.currentCastSession?.device.friendlyName ?? studio
        metadata.setString(deviceName, forKey: kGCKMetadataKeyStudio)
        
        if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
            metadata.addImage(GCKImage(url: url, width: 480, height: 360))
        }
        
        return metadata
    }
    
    func startPlayingItemOnChromeCast(mediaInfo: GCKMediaInformation, at time: TimeInterval, completion: CastItemCompletion) {
        guard let currentCastSession = castSessionManager.currentSession else {
            completion(false)
            return
        }
        
        let mediaSeekOptions = GCKMediaLoadOptions()
        mediaSeekOptions.playPosition = time
        currentCastSession.remoteMediaClient?.loadMedia(mediaInfo, with: mediaSeekOptions)
        
        status = .connected
        
        completion(true)
    }
    
    func playItemOnChromeCast(to time: TimeInterval?, completion: CastItemCompletion) {
        guard let currentCastSession = castSessionManager.currentSession else {
            completion(false)
            return
        }
        
        let remoteMediaClient = currentCastSession.remoteMediaClient
        
        if let time = time {
            let mediaSeekOptions = GCKMediaSeekOptions()
            mediaSeekOptions.interval = time
            mediaSeekOptions.resumeState = .play
            remoteMediaClient?.seek(with: mediaSeekOptions)
        } else {
            remoteMediaClient?.play()
        }
        
        completion(true)
    }
    
    func pauseItemOnChromeCast(at time: TimeInterval?, completion: CastItemCompletion) {
        guard let currentCastSession = castSessionManager.currentCastSession else {
            completion(false)
            return
        }
        
        let remoteMediaClient = currentCastSession.remoteMediaClient
        if let time = time {
            let mediaSeekOptions = GCKMediaSeekOptions()
            mediaSeekOptions.interval = time
            mediaSeekOptions.resumeState = .pause
            remoteMediaClient?.seek(with: mediaSeekOptions)
        } else {
            remoteMediaClient?.pause()
        }
        
        completion(true)
    }
    
    func getPlayBackTimeFromChromeCast(completion: @escaping (TimeInterval?) -> Void) {
        guard let castSession = castSessionManager.currentCastSession else {
            completion(nil)
            return
        }
        
        let approximateStreamPosition = castSession.remoteMediaClient?.approximateStreamPosition()
        
        completion(approximateStreamPosition)
    }
    
    func getMediaPlayerStateFromChromeCast(completion: @escaping (GCKMediaPlayerState) -> Void) {
        guard let currentCastSession = castSessionManager.currentCastSession else {
            completion(GCKMediaPlayerState.unknown)
            return
        }
        
        if let remoteClient = currentCastSession.remoteMediaClient,
            let mediaStatus = remoteClient.mediaStatus {
            completion(mediaStatus.playerState)
        }
    }
    
    func createMiniMediaControl() {
        let castContext = GCKCastContext.sharedInstance()
        let miniMediaControlsViewController = castContext.createMiniMediaControlsViewController()
//        miniMediaControlsViewController.delegate = self
//        mediaControlsContainerView.alpha = 0
//        miniMediaControlsViewController.view.alpha = 0
//        miniMediaControlsHeightConstraint.constant = miniMediaControlsViewController.minHeight
//        installViewController(miniMediaControlsViewController, inContainerView: mediaControlsContainerView)
//        updateControlBarsVisibility()
    }
}

extension ChromeCastManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, willStart session: GCKSession) {
        print("will start session manager")
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        print("did start session manager")
        status = .started
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, willEnd session: GCKSession) {
        print("will end session manager")
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, willResumeSession session: GCKSession) {
        print("will resume session manager")
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        print("did resume session manager")
        status = .resumed
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, willEnd session: GCKCastSession) {
        print("will end session manager")
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        print("did end session manager")
        status = .ended
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        print("did fail to start session manager")
        status = .failed(error)
    }
    
    func sessionManager(_ sessionManager: GCKSessionManager, didSuspend session: GCKSession, with reason: GCKConnectionSuspendReason) {
        print("did suspend session manager")
        status = .suspended
    }
    
}


extension ChromeCastManager: GCKDiscoveryManagerListener {
    func didStartDiscovery(forDeviceCategory deviceCategory: String) {
        print("did start discovery")
    }
}

extension ChromeCastManager: GCKRemoteMediaClientListener {
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didStartMediaSessionWithID sessionID: Int) {
        
    }
    
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        
    }
    
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaMetadata: GCKMediaMetadata?) {
        
    }
    
    func remoteMediaClientDidUpdateQueue(_ client: GCKRemoteMediaClient) {
        
    }
    
    func remoteMediaClientDidUpdatePreloadStatus(_ client: GCKRemoteMediaClient) {
        
    }
}


extension ChromeCastManager: GCKLoggerDelegate {
    func logMessage(_ message: String, at level: GCKLoggerLevel, fromFunction function: String, location: String) {
        if (castDebugLoggingEnabled) {
            print(function + " - " + message)
        }
    }
}

