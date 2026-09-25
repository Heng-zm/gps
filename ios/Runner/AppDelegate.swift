import Flutter
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
@available(iOS 16.1, *)
public struct TrackProActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var speedMph: Double
    public var distanceMiles: Double
    public var elapsedSeconds: Int
    public var formattedTime: String
    public var maxSpeedMph: Double
    public var avgSpeedMph: Double

    public init(
      speedMph: Double,
      distanceMiles: Double,
      elapsedSeconds: Int,
      formattedTime: String,
      maxSpeedMph: Double,
      avgSpeedMph: Double
    ) {
      self.speedMph = speedMph
      self.distanceMiles = distanceMiles
      self.elapsedSeconds = elapsedSeconds
      self.formattedTime = formattedTime
      self.maxSpeedMph = maxSpeedMph
      self.avgSpeedMph = avgSpeedMph
    }
  }

  public var tripName: String

  public init(tripName: String) {
    self.tripName = tripName
  }
}
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
#if canImport(ActivityKit)
  @available(iOS 16.1, *)
  private var currentActivityId: String?
#endif

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as? FlutterViewController
    if let messenger = controller?.binaryMessenger {
      setupLiveActivityChannel(messenger: messenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupLiveActivityChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.trackpro.live_activity",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate released", details: nil))
        return
      }

      switch call.method {
      case "isSupported":
        if #available(iOS 16.1, *) {
          #if canImport(ActivityKit)
          result(ActivityAuthorizationInfo().areActivitiesEnabled)
          #else
          result(false)
          #endif
        } else {
          result(false)
        }

      case "startActivity":
        if #available(iOS 16.1, *) {
          #if canImport(ActivityKit)
          guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "DISABLED", message: "Live Activities are disabled", details: nil))
            return
          }

          let args = call.arguments as? [String: Any] ?? [:]
          let tripName = args["tripName"] as? String ?? "TrackPro Journey"
          let speedMph = args["speedMph"] as? Double ?? 0.0
          let distanceMiles = args["distanceMiles"] as? Double ?? 0.0
          let elapsedSeconds = args["elapsedSeconds"] as? Int ?? 0
          let formattedTime = args["formattedTime"] as? String ?? "00:00"
          let maxSpeedMph = args["maxSpeedMph"] as? Double ?? 0.0
          let avgSpeedMph = args["avgSpeedMph"] as? Double ?? 0.0

          let attributes = TrackProActivityAttributes(tripName: tripName)
          let initialContentState = TrackProActivityAttributes.ContentState(
            speedMph: speedMph,
            distanceMiles: distanceMiles,
            elapsedSeconds: elapsedSeconds,
            formattedTime: formattedTime,
            maxSpeedMph: maxSpeedMph,
            avgSpeedMph: avgSpeedMph
          )

          do {
            for activity in Activity<TrackProActivityAttributes>.activities {
              Task {
                await activity.end(using: nil, dismissalPolicy: .immediate)
              }
            }

            let activity = try Activity<TrackProActivityAttributes>.request(
              attributes: attributes,
              contentState: initialContentState,
              pushType: nil
            )
            self.currentActivityId = activity.id
            result(activity.id)
          } catch {
            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
          }
          #else
          result(FlutterError(code: "UNSUPPORTED", message: "ActivityKit unavailable", details: nil))
          #endif
        } else {
          result(FlutterError(code: "UNSUPPORTED", message: "Requires iOS 16.1+", details: nil))
        }

      case "updateActivity":
        if #available(iOS 16.1, *) {
          #if canImport(ActivityKit)
          let args = call.arguments as? [String: Any] ?? [:]
          let speedMph = args["speedMph"] as? Double ?? 0.0
          let distanceMiles = args["distanceMiles"] as? Double ?? 0.0
          let elapsedSeconds = args["elapsedSeconds"] as? Int ?? 0
          let formattedTime = args["formattedTime"] as? String ?? "00:00"
          let maxSpeedMph = args["maxSpeedMph"] as? Double ?? 0.0
          let avgSpeedMph = args["avgSpeedMph"] as? Double ?? 0.0

          let updatedState = TrackProActivityAttributes.ContentState(
            speedMph: speedMph,
            distanceMiles: distanceMiles,
            elapsedSeconds: elapsedSeconds,
            formattedTime: formattedTime,
            maxSpeedMph: maxSpeedMph,
            avgSpeedMph: avgSpeedMph
          )

          Task {
            for activity in Activity<TrackProActivityAttributes>.activities {
              await activity.update(using: updatedState)
            }
          }
          result(true)
          #else
          result(false)
          #endif
        } else {
          result(false)
        }

      case "stopActivity":
        if #available(iOS 16.1, *) {
          #if canImport(ActivityKit)
          Task {
            for activity in Activity<TrackProActivityAttributes>.activities {
              await activity.end(using: nil, dismissalPolicy: .immediate)
            }
            self.currentActivityId = nil
          }
          result(true)
          #else
          result(false)
          #endif
        } else {
          result(false)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
