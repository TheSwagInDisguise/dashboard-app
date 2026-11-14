import Flutter
import UIKit
import EventKit

/**
 * Entry point for every outside nudge on iOS (mirror of Android's MainActivity):
 *   - home-screen quick actions (UIApplicationShortcutItems) → {type: "add_task" | "sync_now"}
 *   - (share capture is absent on iOS — no Share Extension yet; see PROJECT_NOTES)
 *   - cold start: Flutter polls getInitialInput on first frame
 *   - warm: Quick Action → nativeInput MethodChannel callback
 *
 * Also owns the `daydeck/devicecal` channel: read-only access to the
 * calendars synced to this iPhone via EventKit (the reliable path for a
 * private shared calendar with no iCal secret). Nothing leaves the device.
 */
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  static let shortcutNewTask = "io.github.theswagindisguise.daydeck.new-task"
  static let shortcutSyncNow = "io.github.theswagindisguise.daydeck.sync-now"

  var pendingInput: [String: Any?]?
  var inputChannel: FlutterMethodChannel?
  var deviceChannel: FlutterMethodChannel?
  private let eventStore = EKEventStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called when the storyboard's implicit engine is ready to take channels.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    let input = FlutterMethodChannel(name: "daydeck/input", binaryMessenger: messenger)
    input.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialInput":
        let value = self?.pendingInput
        self?.pendingInput = nil
        result(value)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    inputChannel = input

    let device = FlutterMethodChannel(name: "daydeck/devicecal", binaryMessenger: messenger)
    device.setMethodCallHandler { [weak self] call, result in
      self?.handleDeviceCalendarCall(call, result)
    }
    deviceChannel = device
  }

  /// Quick Action from the home screen (cold start stores it for getInitialInput;
  /// warm start fires it straight down the channel).
  func handleShortcutAction(type: String) {
    let input: [String: Any?]
    switch type {
    case AppDelegate.shortcutNewTask:
      input = ["type": "add_task"]
    case AppDelegate.shortcutSyncNow:
      input = ["type": "sync_now"]
    default:
      input = ["type": "open_today"]
    }
    pendingInput = input
    inputChannel?.invokeMethod("nativeInput", arguments: input)
  }

  // ---------------------------------------------------------------------
  // Device calendar (EventKit, read-only)
  // ---------------------------------------------------------------------

  private func calendarAccessGranted() -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) {
      return status == .fullAccess
    }
    return status == .authorized
  }

  private func handleDeviceCalendarCall(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "checkCalendarPermission":
      result(calendarAccessGranted())

    case "requestCalendarPermission":
      if calendarAccessGranted() {
        result(true)
        return
      }
      let completion: (Bool, Error?) -> Void = { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
      if #available(iOS 17.0, *) {
        eventStore.requestFullAccessToEvents(completion: completion)
      } else {
        eventStore.requestAccess(to: .event, completion: completion)
      }

    case "listCalendars":
      guard calendarAccessGranted() else {
        result(FlutterError(code: "PERMISSION", message: "calendar permission not granted", details: nil))
        return
      }
      let calendars = eventStore.calendars(for: .event).map { calendar -> [String: Any?] in
        return [
          "id": calendar.calendarIdentifier,
          "name": calendar.title,
          "account": calendar.source.title,
          "color": colorInt(calendar.cgColor),
          // EventKit does not expose per-calendar sync state; treat all as synced.
          "syncEnabled": true,
        ]
      }
      result(calendars)

    case "listEvents":
      guard calendarAccessGranted() else {
        result(FlutterError(code: "PERMISSION", message: "calendar permission not granted", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let beginMs = (args["beginMs"] as? NSNumber)?.int64Value,
            let endMs = (args["endMs"] as? NSNumber)?.int64Value else {
        result(FlutterError(code: "ARG", message: "beginMs and endMs are required", details: nil))
        return
      }
      let start = Date(timeIntervalSince1970: TimeInterval(beginMs) / 1000.0)
      let end = Date(timeIntervalSince1970: TimeInterval(endMs) / 1000.0)
      let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
      let events = eventStore.events(matching: predicate).map { event -> [String: Any?] in
        let eventStart = Int64(event.startDate.timeIntervalSince1970 * 1000.0)
        let eventEnd = Int64(event.endDate.timeIntervalSince1970 * 1000.0)
        return [
          "eventId": "\(event.calendarItemIdentifier)|\(eventStart)",
          "calendarId": event.calendar.calendarIdentifier,
          "title": event.title ?? "",
          "location": event.location,
          "notes": event.notes,
          "begin": eventStart,
          "end": eventEnd,
          "allDay": event.isAllDay,
        ]
      }
      result(events)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func colorInt(_ cgColor: CGColor) -> Int {
    let uiColor = UIColor(cgColor: cgColor)
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
      return (Int(red * 255) << 16) | (Int(green * 255) << 8) | Int(blue * 255)
    }
    return 0
  }
}
