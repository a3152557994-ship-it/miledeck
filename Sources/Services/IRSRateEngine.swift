import Foundation

enum IRS2026Period: String, Codable {
    case h1_2026 // Jan 1 – Jun 30, 2026 ($0.725/mi)
    case h2_2026 // Jul 1 – Dec 31, 2026 ($0.760/mi)
    case otherYear

    var shortBadge: String {
        switch self {
        case .h1_2026: return L10n.t("2026 H1 • 72.5¢/mi", "2026 上半年 • $0.725/mi", "2026 上半年 • $0.725/mi")
        case .h2_2026: return L10n.t("2026 H2 • 76¢/mi", "2026 下半年 • $0.76/mi", "2026 下半年 • $0.76/mi")
        case .otherYear: return L10n.t("Standard IRS", "IRS 标准费率", "IRS 標準費率")
        }
    }

    var csvLabel: String {
        switch self {
        case .h1_2026: return "2026-H1 (Jan-Jun)"
        case .h2_2026: return "2026-H2 (Jul-Dec)"
        case .otherYear: return "Standard"
        }
    }
}

enum IRSRateEngine {
    // Official IRS 2026 Split-Period Standard Mileage Rates (IRS Announcement 2026-11)
    static let business2026H1: Double = 0.725   // Jan 1 – Jun 30, 2026
    static let business2026H2: Double = 0.760   // Jul 1 – Dec 31, 2026
    static let business2025: Double = 0.700
    static let medicalMovingRate: Double = 0.210
    static let charityRate: Double = 0.140

    // International Tax Presets
    static let ukHMRCTier1: Double = 0.45             // £0.45/mi first 10,000 mi
    static let ukHMRCTier2: Double = 0.25             // £0.25/mi after 10,000 mi
    static let ukHMRCThresholdMiles: Double = 10_000.0

    static let auATORatePerKm: Double = 0.88          // A$0.88/km

    static let caCRATier1PerKm: Double = 0.72         // CA$0.72/km first 5,000 km
    static let caCRATier2PerKm: Double = 0.66         // CA$0.66/km after 5,000 km
    static let caCRAThresholdKm: Double = 5_000.0

    static let euStandardPerKm: Double = 0.30         // €0.30/km

    static func period(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> IRS2026Period {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return .h2_2026 }
        if year == 2026 {
            return month <= 6 ? .h1_2026 : .h2_2026
        }
        return .otherYear
    }

    static func periodBadge(for date: Date, settings: DriverSettings) -> String {
        if settings.useCustomRate {
            return String(format: "%@%.3f/%@", settings.currencySymbol, settings.customRatePerUnit, settings.distanceUnit.shortLabel)
        }
        switch settings.taxRegion {
        case .usIRS2026:
            return period(for: date).shortBadge
        case .ukHMRC:
            return L10n.t("UK HMRC • 45p/25p", "英国 HMRC • 45p/25p", "英國 HMRC • 45p/25p")
        case .auATO:
            return L10n.t("AU ATO • 88¢/km", "澳洲 ATO • A$0.88/km", "澳洲 ATO • A$0.88/km")
        case .caCRA:
            return L10n.t("CA CRA • 72¢/66¢/km", "加拿大 CRA • 72¢/66¢/km", "加拿大 CRA • 72¢/66¢/km")
        case .euStandard:
            return L10n.t("EU • €0.30/km", "欧盟 • €0.30/km", "歐盟 • €0.30/km")
        }
    }

    /// Official IRS rate per mile for a given date & classification (ignoring custom override)
    static func irsRatePerMile(for classification: DriveClassification, on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2026
        let month = comps.month ?? 7

        switch classification {
        case .business, .unclassified:
            if year == 2026 {
                return month <= 6 ? business2026H1 : business2026H2
            } else if year <= 2025 {
                return business2025
            } else {
                return business2026H2
            }
        case .medical:
            return medicalMovingRate
        case .charity:
            return charityRate
        case .personal:
            return 0.0
        }
    }

    /// Computes tiered allowance for progressive distance brackets (e.g. UK HMRC 10k mi, CA CRA 5k km).
    static func tieredAllowance(
        units: Double,
        priorUnits: Double,
        threshold: Double,
        tier1Rate: Double,
        tier2Rate: Double
    ) -> Double {
        let safeUnits = max(0, units)
        let safePrior = max(0, priorUnits)
        let remainingTier1 = max(0, threshold - safePrior)
        let tier1Units = min(safeUnits, remainingTier1)
        let tier2Units = max(0, safeUnits - tier1Units)
        return roundCents(tier1Units * tier1Rate + tier2Units * tier2Rate)
    }

    /// Calculates tax deduction in the configured region currency for a drive.
    /// `priorDeductibleMilesInYear`: cumulative prior deductible miles in the same tax year (used by UK HMRC & CA CRA tiered thresholds).
    /// For unclassified drives, `includePotentialForUnclassified` returns what the drive WOULD be worth if swiped Business.
    static func deduction(
        for drive: DriveRecord,
        settings: DriverSettings,
        includePotentialForUnclassified: Bool = false,
        priorDeductibleMilesInYear: Double = 0
    ) -> Double {
        if drive.classification == .personal { return 0.0 }
        if drive.classification == .unclassified && !includePotentialForUnclassified { return 0.0 }

        let miles = max(0, drive.distanceMiles)
        if settings.useCustomRate && (drive.classification == .business || drive.classification == .unclassified) {
            let units = settings.distanceUnit.fromMiles(miles)
            return roundCents(units * max(0, settings.customRatePerUnit))
        }

        switch settings.taxRegion {
        case .usIRS2026:
            let rate = irsRatePerMile(for: drive.classification, on: drive.startDate)
            return roundCents(miles * rate)

        case .ukHMRC:
            return tieredAllowance(
                units: miles,
                priorUnits: priorDeductibleMilesInYear,
                threshold: ukHMRCThresholdMiles,
                tier1Rate: ukHMRCTier1,
                tier2Rate: ukHMRCTier2
            )

        case .auATO:
            let km = miles * DistanceUnit.kmPerMile
            return roundCents(km * auATORatePerKm)

        case .caCRA:
            let km = miles * DistanceUnit.kmPerMile
            let priorKm = max(0, priorDeductibleMilesInYear) * DistanceUnit.kmPerMile
            return tieredAllowance(
                units: km,
                priorUnits: priorKm,
                threshold: caCRAThresholdKm,
                tier1Rate: caCRATier1PerKm,
                tier2Rate: caCRATier2PerKm
            )

        case .euStandard:
            let km = miles * DistanceUnit.kmPerMile
            return roundCents(km * euStandardPerKm)
        }
    }

    /// Chronologically computes per-drive deductions across an array of drives, accurately applying UK HMRC & CA CRA tiered thresholds.
    static func deductionsByDriveID(
        for drives: [DriveRecord],
        settings: DriverSettings
    ) -> [UUID: Double] {
        let cal = Calendar(identifier: .gregorian)
        let sorted = drives.sorted { $0.startDate < $1.startDate }
        var priorMilesByYear: [Int: Double] = [:]
        var result: [UUID: Double] = [:]

        for d in sorted {
            let year = cal.component(.year, from: d.startDate)
            let prior = priorMilesByYear[year, default: 0]
            let ded = deduction(for: d, settings: settings, priorDeductibleMilesInYear: prior)
            result[d.id] = ded
            if d.classification.isDeductible {
                priorMilesByYear[year] = prior + max(0, d.distanceMiles)
            }
        }
        return result
    }

    /// Live estimation for Day-0 Onboarding Calculator (weekly distance in preset's native unit * 52 weeks).
    static func estimatedAnnualDeduction(weeklyUnits: Double, preset: TaxRegionPreset) -> Double {
        let annualUnits = max(0, weeklyUnits) * 52.0
        switch preset {
        case .usIRS2026:
            // Half year at H1 ($0.725/mi) + half year at H2 ($0.760/mi)
            let half = annualUnits / 2.0
            return roundCents(half * business2026H1 + half * business2026H2)
        case .ukHMRC:
            return tieredAllowance(
                units: annualUnits,
                priorUnits: 0,
                threshold: ukHMRCThresholdMiles,
                tier1Rate: ukHMRCTier1,
                tier2Rate: ukHMRCTier2
            )
        case .auATO:
            return roundCents(annualUnits * auATORatePerKm)
        case .caCRA:
            return tieredAllowance(
                units: annualUnits,
                priorUnits: 0,
                threshold: caCRAThresholdKm,
                tier1Rate: caCRATier1PerKm,
                tier2Rate: caCRATier2PerKm
            )
        case .euStandard:
            return roundCents(annualUnits * euStandardPerKm)
        }
    }

    static func effectiveRateLabel(
        for drive: DriveRecord,
        settings: DriverSettings,
        priorDeductibleMilesInYear: Double = 0
    ) -> String {
        if drive.classification == .personal {
            return "\(settings.currencySymbol)0.00"
        }
        if settings.useCustomRate && (drive.classification == .business || drive.classification == .unclassified) {
            return String(format: "%@%.3f/%@", settings.currencySymbol, settings.customRatePerUnit, settings.distanceUnit.shortLabel)
        }
        switch settings.taxRegion {
        case .usIRS2026:
            let rate = irsRatePerMile(for: drive.classification, on: drive.startDate)
            if abs(rate - 0.725) < 0.0001 {
                return "$0.725/mi"
            }
            return String(format: "$%.2f/mi", rate)
        case .ukHMRC:
            let rate = priorDeductibleMilesInYear >= ukHMRCThresholdMiles ? ukHMRCTier2 : ukHMRCTier1
            return String(format: "£%.2f/mi", rate)
        case .auATO:
            return "A$0.88/km"
        case .caCRA:
            let priorKm = priorDeductibleMilesInYear * DistanceUnit.kmPerMile
            let rate = priorKm >= caCRAThresholdKm ? caCRATier2PerKm : caCRATier1PerKm
            return String(format: "CA$%.2f/km", rate)
        case .euStandard:
            return "€0.30/km"
        }
    }

    static func liveBusinessRatePerMile(settings: DriverSettings, on date: Date = Date()) -> Double {
        if settings.useCustomRate {
            return settings.distanceUnit == .miles
                ? settings.customRatePerUnit
                : settings.customRatePerUnit * DistanceUnit.kmPerMile
        }
        switch settings.taxRegion {
        case .usIRS2026: return irsRatePerMile(for: .business, on: date)
        case .ukHMRC: return ukHMRCTier1
        case .auATO: return auATORatePerKm * DistanceUnit.kmPerMile
        case .caCRA: return caCRATier1PerKm * DistanceUnit.kmPerMile
        case .euStandard: return euStandardPerKm * DistanceUnit.kmPerMile
        }
    }

    static func roundCents(_ value: Double) -> Double {
        (value * 100.0).rounded() / 100.0
    }

    static func formatMoney(_ amount: Double, symbol: String = "$") -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        let formatted = nf.string(from: NSNumber(value: abs(amount))) ?? String(format: "%.2f", abs(amount))
        return amount < 0 ? "-\(symbol)\(formatted)" : "\(symbol)\(formatted)"
    }

    static func formatWholeMoney(_ amount: Double, symbol: String = "$") -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        let formatted = nf.string(from: NSNumber(value: abs(amount).rounded())) ?? "\(Int(abs(amount).rounded()))"
        return amount < 0 ? "-\(symbol)\(formatted)" : "\(symbol)\(formatted)"
    }

    static func formatDistance(_ miles: Double, unit: DistanceUnit) -> String {
        let val = unit.fromMiles(miles)
        return String(format: "%.1f %@", val, unit.shortLabel)
    }

    static func formatOdometer(_ miles: Double, unit: DistanceUnit) -> String {
        let val = unit.fromMiles(miles)
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        let str = nf.string(from: NSNumber(value: val.rounded())) ?? "\(Int(val.rounded()))"
        return "\(str) \(unit.shortLabel)"
    }
}
