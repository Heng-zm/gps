#if canImport(ActivityKit) && canImport(WidgetKit) && canImport(SwiftUI)
import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
public struct TrackProLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackProActivityAttributes.self) { context in
            // Lock Screen Banner UI
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.tripName.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color.cyan)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", context.state.speedMph))
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("MPH")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.gray)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("DISTANCE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray)
                            Text(String(format: "%.2f mi", context.state.distanceMiles))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("DURATION")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.gray)
                            Text(context.state.formattedTime)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("MAX: \(String(format: "%.1f", context.state.maxSpeedMph))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("AVG: \(String(format: "%.1f", context.state.avgSpeedMph))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(red: 0.07, green: 0.09, blue: 0.13))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded View (Long Press)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURRENT SPEED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.cyan)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", context.state.speedMph))
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("mph")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("DISTANCE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f mi", context.state.distanceMiles))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.state.formattedTime, systemImage: "stopwatch.fill")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        HStack(spacing: 8) {
                            Text("MAX \(String(format: "%.0f", context.state.maxSpeedMph))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                            Text("AVG \(String(format: "%.0f", context.state.avgSpeedMph))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)
                    Text(String(format: "%.0f", context.state.speedMph))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
            } compactTrailing: {
                Text(String(format: "%.1f mi", context.state.distanceMiles))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            } minimal: {
                Text(String(format: "%.0f", context.state.speedMph))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.cyan)
            }
        }
    }
}
#endif
