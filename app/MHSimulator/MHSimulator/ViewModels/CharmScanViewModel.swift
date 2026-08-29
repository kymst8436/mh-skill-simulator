import Foundation
import Observation
import AVFoundation
import UIKit
import MHSimulatorCore

/// 護石スキャン(画面設計4.13)。カメラ権限と完了判定(連続フレーム安定)を持つ。
/// フレームの解釈本体はCore `CharmScanParser`(仕様3.6)
@Observable
final class CharmScanViewModel {
    enum Permission {
        case undetermined
        case granted
        case denied
    }

    /// 完了判定: 同一解釈がこの回数連続したら確定(仕様3.6のN。実機検証F10-4で調整)
    static let requiredStableFrames = 3

    private(set) var permission: Permission = .undetermined
    let parser: CharmScanParser
    /// 完了時に確定スキル(規則順)と読み取れたレア度を渡す。呼び出しはMainActor・一度だけ
    let onScanned: ([CharmRules.GroupEntry], Int?) -> Void

    private var lastSkills: [CharmRules.GroupEntry]?
    private var lastRarity: Int?
    private var stableCount = 0
    private var isFinished = false

    init(dependencies: AppDependencies, onScanned: @escaping ([CharmRules.GroupEntry], Int?) -> Void) {
        self.parser = CharmScanParser(
            skillNames: dependencies.master.skills.mapValues(\.name),
            rules: dependencies.master.charmRules)
        self.onScanned = onScanned
        syncPermission()
    }

    func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.permission = granted ? .granted : .denied
                }
            }
        default:
            syncPermission()
        }
    }

    private func syncPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permission = .granted
        case .notDetermined: permission = .undetermined
        default: permission = .denied
        }
    }

    /// 1フレーム分の解釈結果を受けて安定判定する(MainActorから呼ぶ)。
    /// 安定判定はスキル構成のみで行う(レア度行は枠位置次第で読めたり読めなかったりするため、
    /// 揺れても安定を妨げず、連続一致中に読めた最新値を採用する)
    func handle(reading: CharmScanParser.Reading?) {
        guard !isFinished else { return }
        guard let reading else {
            lastSkills = nil
            lastRarity = nil
            stableCount = 0
            return
        }
        if reading.skills == lastSkills {
            stableCount += 1
        } else {
            lastSkills = reading.skills
            lastRarity = nil
            stableCount = 1
        }
        if let rarity = reading.rarity { lastRarity = rarity }
        guard stableCount >= Self.requiredStableFrames else { return }
        isFinished = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScanned(reading.skills, lastRarity)
    }
}
