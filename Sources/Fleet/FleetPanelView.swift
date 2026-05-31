import SwiftUI

/// Right-sidebar Fleet view. Monitors the studio drone fleet: missions, tasks,
/// per-drone status. Polls the knowledge HTTP endpoint every 8s.
///
/// Snapshot-boundary: only `FleetMission`/`FleetTask` value types cross the
/// LazyVStack boundary — no ObservableObject refs in row views (issue #2586).
struct FleetPanelView: View {
    @ObservedObject private var store = FleetStore.shared
    let fontScale: CGFloat

    private func rsScaled(_ base: CGFloat) -> CGFloat { base * fontScale }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isOffline && store.missions.isEmpty {
                offlineView
            } else {
                missionList
            }
        }
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(String(localized: "fleet.panel.title", defaultValue: "FLEET"))
                .font(.system(size: rsScaled(11), weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if store.isOffline {
                Text(String(localized: "fleet.panel.offline", defaultValue: "offline"))
                    .font(.system(size: rsScaled(11)))
                    .foregroundStyle(.orange)
            } else if let updated = store.lastUpdated {
                Text(Self.relativeFormatter.localizedString(for: updated, relativeTo: Date()))
                    .font(.system(size: rsScaled(11)))
                    .foregroundStyle(.tertiary)
            }
            Button {
                Task { await store.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: rsScaled(11)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "fleet.panel.refresh", defaultValue: "Refresh Fleet"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Offline

    private var offlineView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(String(localized: "fleet.panel.offline.detail", defaultValue: "Knowledge endpoint unreachable"))
                .font(.system(size: rsScaled(12)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Mission list

    private var missionList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(store.missions) { mission in
                    let actions = FleetMissionRowActions(onJumpToSession: { _ in })
                    FleetMissionSection(
                        mission: mission,
                        fontScale: fontScale,
                        actions: actions
                    )
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Mission section (snapshot-boundary: no store ref)

private struct FleetMissionSection: View {
    let mission: FleetMission
    let fontScale: CGFloat
    let actions: FleetMissionRowActions

    @State private var isCollapsed: Bool = false

    private func rsScaled(_ base: CGFloat) -> CGFloat { base * fontScale }

    var body: some View {
        VStack(spacing: 0) {
            missionHeader
            if !isCollapsed {
                ForEach(mission.tasks) { task in
                    let taskActions = FleetTaskRowActions(onJumpToSession: { _ in })
                    FleetTaskRow(task: task, fontScale: fontScale, actions: taskActions)
                }
            }
        }
    }

    private var missionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: rsScaled(10)))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                Text(mission.name)
                    .font(.system(size: rsScaled(12), weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("\(mission.doneCount)/\(mission.totalCount)")
                    .font(.system(size: rsScaled(11)))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.04))
    }
}

// MARK: - Task row (snapshot-boundary: receives value snapshot + closures only)

private struct FleetTaskRow: View {
    let task: FleetTask
    let fontScale: CGFloat
    let actions: FleetTaskRowActions

    private func rsScaled(_ base: CGFloat) -> CGFloat { base * fontScale }

    var body: some View {
        HStack(spacing: 6) {
            Text(task.status.displayIcon)
                .font(.system(size: rsScaled(12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: rsScaled(12)))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let drone = task.lockedBy {
                    HStack(spacing: 4) {
                        Text(drone)
                            .font(.system(size: rsScaled(10)))
                            .foregroundStyle(.secondary)
                        if let elapsed = task.elapsedLabel {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(elapsed)
                                .font(.system(size: rsScaled(10)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { actions.onJumpToSession(task) }
    }
}
