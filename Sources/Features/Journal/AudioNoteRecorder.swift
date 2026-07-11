import AVFoundation
import SwiftUI
import os

/// 漁獲紀錄的魚聲錄音:錄製(AAC 單聲道)、播放、刪除。
/// 檔案存於 App Documents,檔名綁定紀錄 id。
@MainActor
final class AudioNoteRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {

    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.blackie.FishMeasureAR",
                                category: "audio")

    static func url(for fileName: String) -> URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// 要求麥克風權限並開始錄音;權限被拒或失敗回傳 false
    func startRecording(fileName: String) async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else {
            logger.warning("record: microphone permission denied")
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            recorder = try AVAudioRecorder(url: Self.url(for: fileName),
                                           settings: settings)
            recorder?.record()
            isRecording = true
            logger.info("record: started \(fileName)")
            return true
        } catch {
            logger.error("record: failed \(error.localizedDescription)")
            return false
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        logger.info("record: stopped")
    }

    func play(fileName: String) {
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            player = try AVAudioPlayer(contentsOf: Self.url(for: fileName))
            player?.delegate = self
            player?.play()
            isPlaying = true
        } catch {
            logger.error("play: failed \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func deleteFile(named fileName: String) {
        stopPlayback()
        try? FileManager.default.removeItem(at: Self.url(for: fileName))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
                                                 successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
