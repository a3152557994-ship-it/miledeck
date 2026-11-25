import SwiftUI

struct VehiclesView: View {
    @EnvironmentObject private var ledger: MileageStore

    @State private var editingVehicle: VehicleEditTarget? = nil
    @State private var odometerTarget: Vehicle? = nil
    @State private var newOdometerText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Garage Header Card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "car.2.fill")
                                .foregroundStyle(MileTheme.emeraldBright)
                            Text(L10n.t("MULTI-VEHICLE ODOMETER GARAGE", "多车辆里程表车库"))
                                .font(.caption.weight(.heavy))
                                .tracking(0.5)
                                .foregroundStyle(Color.white.opacity(0.75))
                            Spacer()
                            Text("\(ledger.vehicles.count) \(L10n.t("vehicles", "辆车"))")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(MileTheme.emerald.opacity(0.28))
                                .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                                .clipShape(Capsule())
                        }
                        Text(L10n.t(
                            "IRS Pub 463 recommends recording start-of-year and current odometer readings for every vehicle you deduct.",
                            "为每辆车登记年初与当前表显里程，导出报税 PDF 时将自动列入合规车辆清单。"
                        ))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.80))
                    }
                    .padding(16)
                    .background(MileTheme.asphalt)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    // Vehicle Cards
                    ForEach(ledger.vehicles) { vehicle in
                        vehicleCard(vehicle)
                    }

                    // Add Vehicle CTA
                    Button {
                        editingVehicle = VehicleEditTarget(vehicle: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text(L10n.t("Add Another Vehicle", "添加新车辆"))
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MileTheme.card)
                        .foregroundStyle(MileTheme.emerald)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MileTheme.emerald.opacity(0.5), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(MileTheme.roadWhite.ignoresSafeArea())
            .navigationTitle(L10n.t("Vehicles", "我的车辆"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingVehicle = VehicleEditTarget(vehicle: nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(MileTheme.emerald)
                    }
                }
            }
            .sheet(item: $editingVehicle) { target in
                VehicleEditorSheet(vehicle: target.vehicle, unit: ledger.settings.distanceUnit)
            }
            .alert(L10n.t("Update Current Odometer", "更新当前表显里程"), isPresented: Binding(get: { odometerTarget != nil }, set: { if !$0 { odometerTarget = nil } })) {
                TextField(L10n.t("Odometer (\(ledger.settings.distanceUnit.shortLabel))", "当前里程 (\(ledger.settings.distanceUnit.shortLabel))"), text: $newOdometerText)
                    .keyboardType(.decimalPad)
                Button(L10n.t("Cancel", "取消"), role: .cancel) { odometerTarget = nil }
                Button(L10n.t("Save", "保存")) {
                    if let v = odometerTarget, let val = Double(newOdometerText.replacingOccurrences(of: ",", with: "")) {
                        ledger.updateVehicleOdometer(v.id, currentMiles: ledger.settings.distanceUnit.toMiles(val))
                    }
                    odometerTarget = nil
                }
            } message: {
                if let v = odometerTarget {
                    Text(v.displayName)
                }
            }
        }
    }

    private func vehicleCard(_ vehicle: Vehicle) -> some View {
        let totalLogged = ledger.milesLogged(for: vehicle.id, businessOnly: false)
        let bizLogged = ledger.milesLogged(for: vehicle.id, businessOnly: true)
        let deltaOdo = max(0, vehicle.currentOdometerMiles - vehicle.startOdometerMiles)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(vehicle.isDefault ? MileTheme.emeraldSoft : MileTheme.roadWhite)
                            .frame(width: 46, height: 46)
                        Image(systemName: "car.side.fill")
                            .font(.title3)
                            .foregroundStyle(vehicle.isDefault ? MileTheme.emerald : MileTheme.asphalt)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(vehicle.displayName)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(MileTheme.ink)
                            if vehicle.isDefault {
                                Text(L10n.t("DEFAULT", "默认"))
                                    .font(.system(size: 9, weight: .heavy))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(MileTheme.emerald)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        if !vehicle.licensePlate.isEmpty {
                            Text(L10n.t("Plate: \(vehicle.licensePlate)", "车牌：\(vehicle.licensePlate)"))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(MileTheme.muted)
                        }
                    }
                }
                Spacer()
                Button {
                    editingVehicle = VehicleEditTarget(vehicle: vehicle)
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(MileTheme.muted)
                }
            }

            // Odometer Telemetry Strip
            HStack(spacing: 10) {
                odoBox(
                    label: L10n.t("JAN 1 START ODO", "年初表显里程"),
                    value: IRSRateEngine.formatOdometer(vehicle.startOdometerMiles, unit: ledger.settings.distanceUnit)
                )
                odoBox(
                    label: L10n.t("CURRENT ODO", "当前表显里程"),
                    value: IRSRateEngine.formatOdometer(vehicle.currentOdometerMiles, unit: ledger.settings.distanceUnit),
                    highlight: true
                )
                odoBox(
                    label: L10n.t("YTD DRIVEN", "今年总行驶"),
                    value: IRSRateEngine.formatOdometer(deltaOdo, unit: ledger.settings.distanceUnit)
                )
            }

            // Logged business vs total summary
            HStack {
                Label(
                    L10n.t(
                        "Business logged: \(IRSRateEngine.formatDistance(bizLogged, unit: ledger.settings.distanceUnit)) / \(IRSRateEngine.formatDistance(totalLogged, unit: ledger.settings.distanceUnit))",
                        "已记商务：\(IRSRateEngine.formatDistance(bizLogged, unit: ledger.settings.distanceUnit)) / 共 \(IRSRateEngine.formatDistance(totalLogged, unit: ledger.settings.distanceUnit))"
                    ),
                    systemImage: "briefcase.fill"
                )
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(MileTheme.emerald)
                Spacer()
            }

            // Actions
            HStack(spacing: 10) {
                Button {
                    odometerTarget = vehicle
                    newOdometerText = String(Int(ledger.settings.distanceUnit.fromMiles(vehicle.currentOdometerMiles).rounded()))
                } label: {
                    Label(L10n.t("Update Odometer", "更新表显"), systemImage: "gauge.with.needle.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(MileTheme.roadWhite)
                        .foregroundStyle(MileTheme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if !vehicle.isDefault {
                    Button {
                        ledger.setDefaultVehicle(vehicle.id)
                    } label: {
                        Label(L10n.t("Set Default", "设为默认"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(MileTheme.emeraldSoft)
                            .foregroundStyle(MileTheme.emerald)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .mileCard(padding: 15)
    }

    private func odoBox(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(MileTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(highlight ? MileTheme.emerald : MileTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(highlight ? MileTheme.emeraldSoft : MileTheme.roadWhite)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct VehicleEditTarget: Identifiable {
    let id = UUID()
    let vehicle: Vehicle?
}

struct VehicleEditorSheet: View {
    @EnvironmentObject private var ledger: MileageStore
    @Environment(\.dismiss) private var dismiss

    let existing: Vehicle?
    let unit: DistanceUnit

    @State private var year: Int
    @State private var make: String
    @State private var model: String
    @State private var licensePlate: String
    @State private var startOdoText: String
    @State private var currentOdoText: String
    @State private var isDefault: Bool

    init(vehicle: Vehicle?, unit: DistanceUnit) {
        self.existing = vehicle
        self.unit = unit
        _year = State(initialValue: vehicle?.year ?? 2024)
        _make = State(initialValue: vehicle?.make ?? "")
        _model = State(initialValue: vehicle?.model ?? "")
        _licensePlate = State(initialValue: vehicle?.licensePlate ?? "")
        _startOdoText = State(initialValue: String(Int(unit.fromMiles(vehicle?.startOdometerMiles ?? 15000).rounded())))
        _currentOdoText = State(initialValue: String(Int(unit.fromMiles(vehicle?.currentOdometerMiles ?? 15000).rounded())))
        _isDefault = State(initialValue: vehicle?.isDefault ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("Vehicle Identity", "车辆信息")) {
                    Stepper(value: $year, in: 1990...2028) {
                        HStack {
                            Text(L10n.t("Model Year", "年份"))
                            Spacer()
                            Text("\(year)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(MileTheme.ink)
                        }
                    }
                    TextField(L10n.t("Make (e.g. Honda, Toyota)", "品牌（如：丰田、比亚迪）"), text: $make)
                    TextField(L10n.t("Model (e.g. Civic, Prius)", "车型（如：卡罗拉、宋 PLUS）"), text: $model)
                    TextField(L10n.t("License Plate (Optional)", "车牌号（选填）"), text: $licensePlate)
                }

                Section(L10n.t("Odometer Readings (\(unit.shortLabel))", "里程表读数 (\(unit.shortLabel))")) {
                    HStack {
                        Text(L10n.t("Start-of-Year", "年初表显"))
                        Spacer()
                        TextField("15000", text: $startOdoText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 120)
                    }
                    HStack {
                        Text(L10n.t("Current Reading", "当前表显"))
                        Spacer()
                        TextField("18500", text: $currentOdoText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 120)
                    }
                    Toggle(L10n.t("Default Vehicle for New Drives", "设为新行程默认车辆"), isOn: $isDefault)
                }

                if let existing, ledger.vehicles.count > 1 {
                    Section {
                        Button(role: .destructive) {
                            ledger.deleteVehicle(existing.id)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text(L10n.t("Delete Vehicle", "删除车辆"))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? L10n.t("Add Vehicle", "添加车辆") : L10n.t("Edit Vehicle", "编辑车辆"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Save", "保存")) {
                        let startVal = unit.toMiles(Double(startOdoText.replacingOccurrences(of: ",", with: "")) ?? 0)
                        let currVal = max(startVal, unit.toMiles(Double(currentOdoText.replacingOccurrences(of: ",", with: "")) ?? startVal))
                        let v = Vehicle(
                            id: existing?.id ?? UUID(),
                            year: year,
                            make: make.isEmpty ? L10n.t("My", "我的") : make,
                            model: model.isEmpty ? L10n.t("Vehicle", "车辆") : model,
                            licensePlate: licensePlate,
                            startOdometerMiles: startVal,
                            currentOdometerMiles: currVal,
                            isDefault: isDefault
                        )
                        ledger.saveVehicle(v)
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                }
            }
        }
    }
}
