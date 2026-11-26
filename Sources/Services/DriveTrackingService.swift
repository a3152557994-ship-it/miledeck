import CoreLocation
import CoreMotion
import Foundation
import Network
import SwiftUI

struct GeocodeAddressParts: Equatable, Sendable {
    var subThoroughfare: String?
    var thoroughfare: String?
    var subLocality: String?
    var locality: String?
    var administrativeArea: String?
    var name: String?
}

protocol ReverseGeocodingHandling: Sendable {
    func reverseGeocode(_ location: CLLocation) async throws -> String?
}

struct SystemReverseGeocoder: ReverseGeocodingHandling {
    func reverseGeocode(_ location: CLLocation) async throws -> String? {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let first = placemarks.first else { return nil }
        let parts = GeocodeAddressParts(
            subThoroughfare: first.subThoroughfare,
            thoroughfare: first.thoroughfare,
            subLocality: first.subLocality,
            locality: first.locality,
            administrativeArea: first.administrativeArea,
            name: first.name
        )
        return DriveTrackingService.formatAddressParts(parts)
    }
}

@MainActor
final class DriveTrackingService: NSObject, ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isAutoMonitoring: Bool = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var liveDistanceMiles: Double = 0.0
    @Published private(set) var liveElapsedSeconds: Int = 0
    @Published private(set) var currentSpeedMPH: Double = 0.0
    @Published private(set) var startAddressLabel: String = ""
    @Published private(set) var statusBanner: String?
    @Published private(set) var isCurrentDriveAutoDetected: Bool = false
    @Published private(set) var stationarySeconds: Int = 0

    /// Configurable thresholds for production reliability and deterministic unit testing.
    var autoStopStationaryThresholdSeconds: TimeInterval = 180.0
    var stationarySpeedThresholdMPS: Double = 0.8
    var minimumRecordableDistanceMiles: Double = 0.15
    var autoRestartCooldownSeconds: TimeInterval = 60.0
    var autoTriggerRequiredConsecutiveFixes: Int = 2
    var maxPlausibleAutomotiveSpeedMPS: Double = 55.0 // ~123 mph guard against tunnel/cell tower jumps

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private var geocoder: ReverseGeocodingHandling
    private var pathMonitor: NWPathMonitor?
    private weak var boundLedger: MileageStore?

    private var startLocation: CLLocation?
    private var lastLocation: CLLocation?
    private var lastCandidateAutoLocation: CLLocation?
    private var consecutiveAutoSpeedFixes: Int = 0
    private var recordingStartDate: Date?
    private var lastMovingDate: Date?
    private var lastStationarySampleDate: Date?
    private var accumulatedStationaryTime: TimeInterval = 0
    private var isMotionNonAutomotive: Bool = false
    private var isMotionWalkingOrTransitBounce: Bool = false
    private var lastAutoStopOrDiscardDate: Date?
    private var resolvedStartAddress: String?
    private var resolvedEndAddress: String?
    private var activeSessionToken = UUID()

    private var timer: Timer?
    private var autoTriggerSpeedMPS: Double = AutoDriveSensitivity.balanced.triggerSpeedMPS
    private var onAutoDriveCompleted: ((DriveRecord) -> Void)?
    var onDriveAddressResolved: ((UUID, String?, String?) -> Void)?

    init(geocoder: ReverseGeocodingHandling = SystemReverseGeocoder(), enableNetworkMonitor: Bool = true) {
        self.geocoder = geocoder
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 15
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus

        if enableNetworkMonitor {
            startNetworkRestorationMonitor()
        }
    }

    deinit {
        pathMonitor?.cancel()
    }

    func setGeocoderForTesting(_ customGeocoder: ReverseGeocodingHandling) {
        self.geocoder = customGeocoder
    }

    func bindLedger(_ ledger: MileageStore) {
        self.boundLedger = ledger
        self.onDriveAddressResolved = { [weak ledger] driveID, startAddr, endAddr in
            ledger?.updateDriveAddresses(id: driveID, startAddress: startAddr, endAddress: endAddr)
        }
    }

    var isAuthorizedForAlways: Bool {
        authorizationStatus == .authorizedAlways
    }

    var isAuthorizedWhenInUseOrAlways: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestLocationPermission(always: Bool = false) {
        if always {
            locationManager.requestAlwaysAuthorization()
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func configureAutoDetection(enabled: Bool, sensitivity: AutoDriveSensitivity, onCompleted: @escaping (DriveRecord) -> Void) {
        self.autoTriggerSpeedMPS = sensitivity.triggerSpeedMPS
        self.onAutoDriveCompleted = onCompleted

        if enabled {
            isAutoMonitoring = true
            startMotionDetectionIfAvailable()
            if isAuthorizedForAlways {
                enableBackgroundLocationSafely(true)
                locationManager.startMonitoringSignificantLocationChanges()
            } else if isAuthorizedWhenInUseOrAlways {
                locationManager.startUpdatingLocation()
            }
        } else {
            isAutoMonitoring = false
            consecutiveAutoSpeedFixes = 0
            lastCandidateAutoLocation = nil
            motionManager.stopActivityUpdates()
            locationManager.stopMonitoringSignificantLocationChanges()
            if !isRecording {
                enableBackgroundLocationSafely(false)
                locationManager.stopUpdatingLocation()
            }
        }
    }

    func startLiveDrive(autoDetected: Bool = false, initialLocation: CLLocation? = nil, startDate: Date = Date()) {
        guard !isRecording else { return }
        if authorizationStatus == .notDetermined && initialLocation == nil {
            locationManager.requestWhenInUseAuthorization()
        }

        let sessionID = UUID()
        activeSessionToken = sessionID
        isRecording = true
        isCurrentDriveAutoDetected = autoDetected
        recordingStartDate = startDate
        lastMovingDate = startDate
        lastStationarySampleDate = startDate
        accumulatedStationaryTime = 0
        stationarySeconds = 0
        liveDistanceMiles = 0.0
        liveElapsedSeconds = 0
        currentSpeedMPH = 0.0
        isMotionNonAutomotive = false
        resolvedStartAddress = nil
        resolvedEndAddress = nil
        startLocation = initialLocation
        lastLocation = initialLocation

        if let initialLocation {
            startAddressLabel = Self.formatCoordinateFallback(initialLocation.coordinate)
            resolveStartLocationAsync(initialLocation, sessionToken: sessionID)
        } else {
            startAddressLabel = ""
        }

        statusBanner = L10n.t(
            "Live GPS tracking active — stays 100% offline",
            "实时 GPS 里程记录中 · 100% 本地离线",
            "即時 GPS 里程記錄中 · 100% 本機離線"
        )

        if isAuthorizedForAlways {
            enableBackgroundLocationSafely(true)
        }
        locationManager.startUpdatingLocation()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickLiveTimer()
            }
        }
    }

    /// Useful for Simulator testing and user live demo verification
    func addSimulatedDistance(miles: Double = 2.4) {
        guard isRecording else { return }
        liveDistanceMiles += miles
        currentSpeedMPH = 34.0
        accumulatedStationaryTime = 0
        stationarySeconds = 0
        lastMovingDate = Date()
        lastStationarySampleDate = Date()
        if startLocation == nil {
            let simStart = CLLocation(latitude: 37.7749, longitude: -122.4194)
            let simEnd = CLLocation(latitude: 37.7897, longitude: -122.4014)
            startLocation = simStart
            lastLocation = simEnd
            if startAddressLabel.isEmpty {
                startAddressLabel = Self.formatCoordinateFallback(simStart.coordinate)
            }
            let token = activeSessionToken
            resolveStartLocationAsync(simStart, sessionToken: token)
        }
        statusBanner = L10n.t(
            "Simulated +\(String(format: "%.1f", miles)) mi added for live test",
            "已模拟增加 +\(String(format: "%.1f", miles)) 英里供实测",
            "已模擬增加 +\(String(format: "%.1f", miles)) 英里供實測"
        )
    }

    func stopAndCreateDrive(vehicleId: UUID?, endDate: Date = Date()) -> DriveRecord? {
        return finalizeActiveDrive(vehicleId: vehicleId, endDate: endDate, triggeredByAutoStop: false)
    }

    private func finalizeActiveDrive(vehicleId: UUID?, endDate: Date, triggeredByAutoStop: Bool) -> DriveRecord? {
        guard isRecording else { return nil }
        timer?.invalidate()
        timer = nil
        isRecording = false
        currentSpeedMPH = 0
        consecutiveAutoSpeedFixes = 0
        lastCandidateAutoLocation = nil

        // Always stop high-accuracy GPS battery drain when a trip ends; keep only ultra-low-power monitoring if auto-detect is on.
        locationManager.stopUpdatingLocation()
        if isAutoMonitoring && isAuthorizedForAlways {
            enableBackgroundLocationSafely(true)
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
            enableBackgroundLocationSafely(false)
        }

        let start = recordingStartDate ?? endDate.addingTimeInterval(-300)
        let capturedDistance = liveDistanceMiles
        let wasAuto = isCurrentDriveAutoDetected || triggeredByAutoStop
        let capturedStartLoc = startLocation
        let capturedEndLoc = lastLocation ?? startLocation
        let capturedStartResolved = resolvedStartAddress
        let capturedEndResolved = resolvedEndAddress
        let capturedStartLabel = startAddressLabel

        // Reset live session counters
        liveDistanceMiles = 0
        liveElapsedSeconds = 0
        stationarySeconds = 0
        accumulatedStationaryTime = 0
        recordingStartDate = nil
        lastMovingDate = nil
        lastStationarySampleDate = nil
        isCurrentDriveAutoDetected = false
        isMotionNonAutomotive = false
        startLocation = nil
        lastLocation = nil
        resolvedStartAddress = nil
        resolvedEndAddress = nil
        startAddressLabel = ""

        // Discard micro-trips (< 0.15 mi) cleanly instead of fabricating fake tax deductions!
        guard capturedDistance >= minimumRecordableDistanceMiles else {
            lastAutoStopOrDiscardDate = endDate
            statusBanner = L10n.t(
                "Trip under 0.15 mi discarded — too short to log.",
                "行程不足 0.15 英里（约 240 米），已自动忽略未入账。",
                "行程不足 0.15 英里（約 240 公尺），已自動忽略未入帳。"
            )
            return nil
        }

        lastAutoStopOrDiscardDate = endDate
        let recordedMiles = (capturedDistance * 100).rounded() / 100

        let initialStartAddress: String = {
            if let resolved = capturedStartResolved, !resolved.isEmpty {
                return resolved
            }
            if !capturedStartLabel.isEmpty {
                return capturedStartLabel
            }
            if let loc = capturedStartLoc {
                return Self.formatCoordinateFallback(loc.coordinate)
            }
            return Self.formatCoordinateFallback(CLLocationCoordinate2D(latitude: 0, longitude: 0))
        }()

        let initialEndAddress: String = {
            if let resolved = capturedEndResolved, !resolved.isEmpty {
                return resolved
            }
            if let loc = capturedEndLoc {
                return Self.formatCoordinateFallback(loc.coordinate)
            }
            return initialStartAddress
        }()

        let driveID = UUID()
        let record = DriveRecord(
            id: driveID,
            startDate: start,
            endDate: max(start, endDate),
            startAddress: initialStartAddress,
            endAddress: initialEndAddress,
            distanceMiles: recordedMiles,
            classification: .unclassified,
            purpose: .deliveryGig,
            vehicleId: vehicleId ?? boundLedger?.defaultVehicle?.id,
            odometerStartMiles: nil,
            odometerEndMiles: nil,
            isAutoDetected: wasAuto,
            notes: wasAuto
                ? L10n.t("Auto-detected GPS drive", "后台自动识车生成", "背景自動偵測行車紀錄")
                : L10n.t("Logged via Live GPS Drive Tracker", "通过实时 GPS 行车记录生成", "透過即時 GPS 行車紀錄產生"),
            startLatitude: capturedStartLoc?.coordinate.latitude,
            startLongitude: capturedStartLoc?.coordinate.longitude,
            endLatitude: capturedEndLoc?.coordinate.latitude,
            endLongitude: capturedEndLoc?.coordinate.longitude
        )

        statusBanner = nil

        // Asynchronously resolve street/city names for start and/or end if currently holding coordinate fallbacks
        let needsStartResolve = capturedStartResolved == nil && capturedStartLoc != nil
        let needsEndResolve = capturedEndResolved == nil && capturedEndLoc != nil
        if needsStartResolve || needsEndResolve {
            let geocoderRef = self.geocoder
            Task { @MainActor [weak self] in
                var newStart: String?
                var newEnd: String?
                if needsStartResolve, let sLoc = capturedStartLoc {
                    newStart = try? await geocoderRef.reverseGeocode(sLoc)
                }
                if needsEndResolve, let eLoc = capturedEndLoc {
                    newEnd = try? await geocoderRef.reverseGeocode(eLoc)
                }
                if (newStart != nil && !(newStart?.isEmpty ?? true)) || (newEnd != nil && !(newEnd?.isEmpty ?? true)) {
                    self?.onDriveAddressResolved?(driveID, newStart, newEnd)
                }
            }
        }

        if triggeredByAutoStop {
            onAutoDriveCompleted?(record)
        }
        return record
    }

    func formattedElapsed() -> String {
        let mins = liveElapsedSeconds / 60
        let secs = liveElapsedSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Testable timer tick & background stationary watchdog
    func tickLiveTimer(now: Date = Date()) {
        guard isRecording else { return }
        liveElapsedSeconds += 1

        if isCurrentDriveAutoDetected {
            let currentMPS = currentSpeedMPH / 2.23694
            let isCurrentlyStill = currentMPS < stationarySpeedThresholdMPS || isMotionNonAutomotive
            if isCurrentlyStill {
                let delta = max(0, now.timeIntervalSince(lastStationarySampleDate ?? now.addingTimeInterval(-1.0)))
                lastStationarySampleDate = now
                accumulatedStationaryTime += max(1.0, delta)
                stationarySeconds = Int(accumulatedStationaryTime.rounded(.down))
                if accumulatedStationaryTime >= autoStopStationaryThresholdSeconds {
                    _ = finalizeActiveDrive(vehicleId: boundLedger?.defaultVehicle?.id, endDate: now, triggeredByAutoStop: true)
                }
            } else {
                lastStationarySampleDate = now
            }
        }
    }

    /// Testable motion state processor (handles automotive auto-start & non-automotive/stationary auto-stop)
    func processMotionState(
        automotive: Bool,
        stationary: Bool,
        walkingOrRunning: Bool,
        confidence: CMMotionActivityConfidence,
        now: Date = Date()
    ) {
        guard confidence != .low else { return }
        isMotionWalkingOrTransitBounce = walkingOrRunning && !automotive

        if isRecording && isCurrentDriveAutoDetected {
            if !automotive && (stationary || walkingOrRunning) {
                if !isMotionNonAutomotive {
                    isMotionNonAutomotive = true
                    lastStationarySampleDate = lastStationarySampleDate ?? now
                }
                let anchor = lastStationarySampleDate ?? lastMovingDate ?? now
                let delta = max(0, now.timeIntervalSince(anchor))
                if delta > 0 {
                    accumulatedStationaryTime += delta
                    lastStationarySampleDate = now
                    stationarySeconds = Int(accumulatedStationaryTime.rounded(.down))
                }
                if accumulatedStationaryTime >= autoStopStationaryThresholdSeconds {
                    _ = finalizeActiveDrive(vehicleId: boundLedger?.defaultVehicle?.id, endDate: now, triggeredByAutoStop: true)
                }
            } else if automotive && !stationary {
                isMotionNonAutomotive = false
                accumulatedStationaryTime = 0
                stationarySeconds = 0
                lastMovingDate = now
                lastStationarySampleDate = now
            }
            return
        }

        // Auto-start via CoreMotion automotive signal (respecting post-discard cooldown to avoid indoor false-trigger loops)
        if automotive && !walkingOrRunning && !isRecording && isAutoMonitoring && canAutoStart(at: now) {
            startLiveDrive(autoDetected: true, initialLocation: nil, startDate: now)
        }
    }

    /// Testable location update processor
    func processLocationUpdate(_ latest: CLLocation) {
        guard latest.horizontalAccuracy >= 0, latest.horizontalAccuracy <= 65 else { return }
        let now = latest.timestamp

        // Compute effective speed (m/s), guarding against negative invalid speed or cell-tower jumps
        let effectiveSpeedMPS: Double = {
            if latest.speed >= 0 {
                return latest.speed
            }
            if let prev = lastLocation ?? lastCandidateAutoLocation {
                let dt = now.timeIntervalSince(prev.timestamp)
                let dist = latest.distance(from: prev)
                if dt > 0.5 && dist >= 10 {
                    return dist / dt
                }
            }
            return 0
        }()

        guard effectiveSpeedMPS <= maxPlausibleAutomotiveSpeedMPS else {
            // Reject underground subway / tunnel cell-tower teleportation spikes
            consecutiveAutoSpeedFixes = 0
            lastCandidateAutoLocation = nil
            return
        }

        currentSpeedMPH = effectiveSpeedMPS * 2.23694

        // 1. Auto-trigger check when monitoring in background and not yet recording
        if isAutoMonitoring && !isRecording {
            if !isMotionWalkingOrTransitBounce && effectiveSpeedMPS >= autoTriggerSpeedMPS && canAutoStart(at: now) {
                if let prevCandidate = lastCandidateAutoLocation {
                    let moved = latest.distance(from: prevCandidate)
                    if moved >= 15 {
                        consecutiveAutoSpeedFixes += 1
                    }
                } else {
                    consecutiveAutoSpeedFixes = 1
                }
                lastCandidateAutoLocation = latest

                if consecutiveAutoSpeedFixes >= max(1, autoTriggerRequiredConsecutiveFixes) {
                    let seedStart = lastCandidateAutoLocation ?? latest
                    consecutiveAutoSpeedFixes = 0
                    lastCandidateAutoLocation = nil
                    startLiveDrive(autoDetected: true, initialLocation: seedStart, startDate: now)
                }
            } else if effectiveSpeedMPS < stationarySpeedThresholdMPS {
                consecutiveAutoSpeedFixes = 0
                lastCandidateAutoLocation = nil
            }
            return
        }

        // 2. Active drive distance accumulation + stationary auto-stop check
        guard isRecording else { return }

        if startLocation == nil {
            startLocation = latest
            if startAddressLabel.isEmpty || Self.isCoordinatePlaceholder(startAddressLabel) {
                startAddressLabel = Self.formatCoordinateFallback(latest.coordinate)
            }
            resolveStartLocationAsync(latest, sessionToken: activeSessionToken)
        }

        var movedMeaningfully = false
        if let prev = lastLocation {
            let deltaMeters = latest.distance(from: prev)
            let dt = max(0.1, now.timeIntervalSince(prev.timestamp))
            let impliedMPS = deltaMeters / dt
            if deltaMeters >= 10 && deltaMeters < 5000 && impliedMPS <= maxPlausibleAutomotiveSpeedMPS {
                liveDistanceMiles += deltaMeters / 1609.344
                movedMeaningfully = true
            }
        }
        lastLocation = latest

        if isCurrentDriveAutoDetected {
            let isVehicleMoving = effectiveSpeedMPS >= stationarySpeedThresholdMPS && !isMotionNonAutomotive
            if isVehicleMoving && (movedMeaningfully || liveElapsedSeconds < 5) {
                accumulatedStationaryTime = 0
                stationarySeconds = 0
                lastMovingDate = now
                lastStationarySampleDate = now
            } else if effectiveSpeedMPS < stationarySpeedThresholdMPS || isMotionNonAutomotive {
                let anchor = lastStationarySampleDate ?? lastMovingDate ?? now
                let dt = max(0, now.timeIntervalSince(anchor))
                accumulatedStationaryTime += dt
                lastStationarySampleDate = now
                stationarySeconds = Int(accumulatedStationaryTime.rounded(.down))

                if accumulatedStationaryTime >= autoStopStationaryThresholdSeconds {
                    _ = finalizeActiveDrive(vehicleId: boundLedger?.defaultVehicle?.id, endDate: now, triggeredByAutoStop: true)
                }
            }
        }
    }

    private func canAutoStart(at date: Date) -> Bool {
        guard let lastStop = lastAutoStopOrDiscardDate else { return true }
        return date.timeIntervalSince(lastStop) >= autoRestartCooldownSeconds
    }

    private func resolveStartLocationAsync(_ location: CLLocation, sessionToken: UUID) {
        let geocoderRef = self.geocoder
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let street = try? await geocoderRef.reverseGeocode(location), !street.isEmpty {
                if self.isRecording && self.activeSessionToken == sessionToken {
                    self.resolvedStartAddress = street
                    self.startAddressLabel = street
                }
            }
        }
    }

    /// Backfills any saved drives whose startAddress or endAddress fell back to raw coordinates while offline.
    func backfillUnresolvedAddresses(in ledger: MileageStore) async {
        let candidates = ledger.drives.filter {
            Self.isCoordinatePlaceholder($0.startAddress) || Self.isCoordinatePlaceholder($0.endAddress)
        }
        guard !candidates.isEmpty else { return }

        for drive in candidates {
            var resolvedStart: String?
            var resolvedEnd: String?

            if Self.isCoordinatePlaceholder(drive.startAddress) {
                let coord: CLLocationCoordinate2D? = {
                    if let lat = drive.startLatitude, let lon = drive.startLongitude {
                        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                    return Self.parseCoordinatePlaceholder(drive.startAddress)
                }()
                if let coord {
                    let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    resolvedStart = try? await geocoder.reverseGeocode(loc)
                }
            }

            if Self.isCoordinatePlaceholder(drive.endAddress) {
                let coord: CLLocationCoordinate2D? = {
                    if let lat = drive.endLatitude, let lon = drive.endLongitude {
                        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                    return Self.parseCoordinatePlaceholder(drive.endAddress)
                }()
                if let coord {
                    let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    resolvedEnd = try? await geocoder.reverseGeocode(loc)
                }
            }

            if resolvedStart != nil || resolvedEnd != nil {
                ledger.updateDriveAddresses(id: drive.id, startAddress: resolvedStart, endAddress: resolvedEnd)
            }
        }
    }

    private func startNetworkRestorationMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, let ledger = self.boundLedger else { return }
                await self.backfillUnresolvedAddresses(in: ledger)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.miledeck.network.geocoder"))
        self.pathMonitor = monitor
    }

    // MARK: - Address & Coordinate Formatting Utilities

    nonisolated static func formatCoordinateFallback(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    nonisolated static func isCoordinatePlaceholder(_ address: String) -> Bool {
        parseCoordinatePlaceholder(address) != nil
    }

    nonisolated static func parseCoordinatePlaceholder(_ address: String) -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lon),
              parts[0].contains("."),
              parts[1].contains(".") else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    nonisolated static func formatAddressParts(_ parts: GeocodeAddressParts) -> String? {
        let street: String? = {
            let num = parts.subThoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let road = parts.thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !num.isEmpty && !road.isEmpty {
                // Handle CJK roads vs Western street numbers cleanly
                let hasCJK = road.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
                return hasCJK ? "\(road)\(num)" : "\(num) \(road)"
            }
            if !road.isEmpty { return road }
            if let poi = parts.name?.trimmingCharacters(in: .whitespacesAndNewlines), !poi.isEmpty {
                return poi
            }
            if let district = parts.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines), !district.isEmpty {
                return district
            }
            return nil
        }()

        let city: String? = {
            if let loc = parts.locality?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                return loc
            }
            if let sub = parts.subLocality?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
                return sub
            }
            if let admin = parts.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines), !admin.isEmpty {
                return admin
            }
            return nil
        }()

        if let street, let city {
            if street.localizedCaseInsensitiveContains(city) {
                return street
            }
            return "\(street), \(city)"
        }
        if let street { return street }
        if let city { return city }
        return nil
    }

    private func enableBackgroundLocationSafely(_ enable: Bool) {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
              modes.contains("location") else {
            return
        }
        if enable && isAuthorizedForAlways {
            locationManager.allowsBackgroundLocationUpdates = true
        } else if !enable {
            locationManager.allowsBackgroundLocationUpdates = false
        }
    }

    private func startMotionDetectionIfAvailable() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor in
                self.processMotionState(
                    automotive: activity.automotive,
                    stationary: activity.stationary,
                    walkingOrRunning: activity.walking || activity.running || activity.cycling,
                    confidence: activity.confidence,
                    now: Date()
                )
            }
        }
    }
}

extension DriveTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAutoMonitoring && status == .authorizedAlways {
                self.enableBackgroundLocationSafely(true)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.processLocationUpdate(latest)
        }
    }
}
