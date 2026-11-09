//
//  FLTUnityViewController.swift
//  flutter_unity_widget
//
//  Created by Rex Raphael on 30/01/2021.
//

import Foundation
import UnityFramework

// Defines unity controllable from Flutter.
public class FLTUnityWidgetController: NSObject, FLTUnityOptionsSink, FlutterPlatformView {
    private var _rootView: FLTUnityView
    private var viewId: Int64 = 0
    private var channel: FlutterMethodChannel?
    private weak var registrar: (NSObjectProtocol & FlutterPluginRegistrar)?
    
    private var _disposed = false

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        registrar: NSObjectProtocol & FlutterPluginRegistrar
    ) {
        self._rootView = FLTUnityView(frame: frame)
        super.init()

        globalControllers.append(self)

        self.viewId = viewId

        let channelName = String(format: "plugin.xraph.com/unity_view_%lld", viewId)
        self.channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())

        self.channel?.setMethodCallHandler(self.methodHandler)
        self.attachView()
    }

    func methodHandler(_ call: FlutterMethodCall, result: FlutterResult) {
        if call.method == "unity#dispose" {
            self.dispose()
            result(nil)
        } else {
            self.reattachView()
            if call.method == "unity#isReady" {
                result(GetUnityPlayerUtils().unityIsInitiallized())
            } else if call.method == "unity#isLoaded" {
                let _isUnloaded = GetUnityPlayerUtils().isUnityLoaded()
                result(_isUnloaded)
            } else if call.method == "unity#createUnityPlayer" {
                startUnityIfNeeded()
                result(nil)
            } else if call.method == "unity#isPaused" {
                let _isPaused = GetUnityPlayerUtils().isUnityPaused()
                result(_isPaused)
            } else if call.method == "unity#pausePlayer" {
                GetUnityPlayerUtils().pause()
                result(nil)
            } else if call.method == "unity#postMessage" {
                self.postMessage(call: call, result: result)
                result(nil)
            } else if call.method == "unity#resumePlayer" {
                GetUnityPlayerUtils().resume()
                result(nil)
            } else if call.method == "unity#unloadPlayer" {
                GetUnityPlayerUtils().unload()
                result(nil)
            } else if call.method == "unity#quitPlayer" {
                GetUnityPlayerUtils().quit()
                result(nil)
            } else if call.method == "unity#waitForUnity" {
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func setDisabledUnload(enabled: Bool) {

    }

    public func view() -> UIView {
        return _rootView;
    }

    private func startUnityIfNeeded() {
        // Attach when Unity is actually up, not on the next unrelated plugin
        // call. Framework init runs on a later main-queue turn, so the
        // synchronous attach in attachView() below finds no root view yet on
        // a cold start — and on a reboot after unload, nothing else calls in
        // until Flutter answers SendCode, leaving the freshly booted player in
        // its own (lower) window while the overlay has already lifted.
        GetUnityPlayerUtils().createPlayer(completed: { [self] (view: UIView?) in
            if self._disposed { return }
            self.attachUnityViewIfNeeded()
        })
    }

    func attachView() {
        startUnityIfNeeded()
        attachUnityViewIfNeeded()
        GetUnityPlayerUtils().resume()
    }

    /// Moves Unity's root view under this platform view. Idempotent: the
    /// createPlayer completion and attachView both call it, and on the
    /// already-initialized path they do so back to back.
    private func attachUnityViewIfNeeded() {
        guard let unityView = GetUnityPlayerUtils().ufw?.appController()?.rootView else {
            return
        }
        if unityView.superview == _rootView {
            return
        }
        if let superview = unityView.superview {
            unityView.removeFromSuperview()
            superview.layoutIfNeeded()
        }
        _rootView.addSubview(unityView)
        _rootView.layoutIfNeeded()
        guard canSendToFlutter else { return }
        self.channel?.invokeMethod("events#onViewReattached", arguments: "")
    }

    func reattachView() {
        let unityView = GetUnityPlayerUtils().ufw?.appController()?.rootView
        let superview = unityView?.superview
        if superview != _rootView {
            attachView()
        }

        GetUnityPlayerUtils().resume()
    }

    func removeViewIfNeeded() {
        if GetUnityPlayerUtils().ufw == nil {
            return
        }

        let unityView = GetUnityPlayerUtils().ufw?.appController()?.rootView
        if _rootView == unityView?.superview {
            if globalControllers.isEmpty {
                unityView?.removeFromSuperview()
                unityView?.superview?.layoutIfNeeded()
            } else {
                globalControllers.last?.reattachView()
            }
        }
        GetUnityPlayerUtils().resume()
    }

    func dispose() {
        if _disposed {
            return
        }

        globalControllers.removeAll{ value in
            return value == self
        }

        channel?.setMethodCallHandler(nil)
        removeViewIfNeeded()
        
        _disposed = true
    }
    
    /// A channel outlives the engine it talks to: the object stays non-nil
    /// after the engine's shell is torn down, so the optional-chaining above
    /// is not the check it looks like. Sending then trips the engine's
    /// assertion and aborts the process. See `unityHostIsTerminating`.
    private var canSendToFlutter: Bool {
        return !_disposed && !unityHostIsTerminating
    }

    /// Handles messages from unity in the current view
    func handleMessage(message: String) {
        guard canSendToFlutter else { return }
        self.channel?.invokeMethod("events#onUnityMessage", arguments: message)
    }


    /// Handles scene changed event from unity in the current view
    func handleSceneChangeEvent(info: Dictionary<String, Any>) {
        guard canSendToFlutter else { return }
        self.channel?.invokeMethod("events#onUnitySceneLoaded", arguments: info)
    }

    /// Unity finished unloadApplication(). Same payload Android sends.
    func handleUnloaded() {
        guard canSendToFlutter else { return }
        self.channel?.invokeMethod("events#onUnityUnloaded", arguments: true)
    }
    
    /// Post messages to unity from flutter
    func postMessage(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments else {
            result("iOS could not recognize flutter arguments in method: (postMessage)")
            return
        }

        if let myArgs = args as? [String: Any],
           let gObj = myArgs["gameObject"] as? String,
           let method = myArgs["methodName"] as? String,
           let message = myArgs["message"] as? String {
            GetUnityPlayerUtils().postMessageToUnity(gameObject: gObj, unityMethodName: method, unityMessage: message)
            result(nil)
        } else {
            result(FlutterError(code: "-1", message: "iOS could not extract " +
                   "flutter arguments in method: (postMessage)", details: nil))
        }
    }
}
