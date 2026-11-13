import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Number of frequency bands the analyzer produces (40 Hz – 16 kHz, log spaced).
let spectrumBandCount = 24

/// Live frequency levels of the selected music app, captured with a Core Audio process tap
/// (macOS 14.2+, "System Audio Recording" permission). Empty `levels` means no live audio.
@MainActor
final class AudioSpectrum: ObservableObject {
    @Published private(set) var levels: [Float] = []
    /// True while capturing but only receiving digital silence (usually: permission denied).
    @Published private(set) var isSilent = false
    @Published private(set) var failure: String?

    private var capture: AnyObject?
    private var target: PlayerSource?
    private var lastAttempt = Date.distantPast
    private var silentFrames = 0

    func sync(source: PlayerSource, isPlaying: Bool) {
        guard isPlaying else { stop(); return }
        guard #available(macOS 14.2, *) else {
            failure = "Requer macOS 14.2 ou mais novo."
            return
        }
        if capture != nil, target == source { return }
        stop()
        // Spotify registers its audio process a moment after playback starts; retry gently.
        guard Date().timeIntervalSince(lastAttempt) > 2 else { return }
        lastAttempt = Date()
        do {
            capture = try TapCapture(bundlePrefix: source.bundleID) { [weak self] bands in
                DispatchQueue.main.async { self?.receive(bands) }
            }
            target = source
            failure = nil
        } catch {
            failure = (error as? TapError)?.message ?? error.localizedDescription
        }
    }

    func stop() {
        if #available(macOS 14.2, *) { (capture as? TapCapture)?.stop() }
        capture = nil
        target = nil
        levels = []
        isSilent = false
        silentFrames = 0
    }

    private func receive(_ bands: [Float]) {
        guard capture != nil else { return }
        if bands.allSatisfy({ $0 == 0 }) {
            silentFrames += 1
            isSilent = silentFrames > 90
        } else {
            silentFrames = 0
            isSilent = false
        }
        levels = bands
    }
}

struct TapError: Error {
    let message: String
    static func os(_ step: String, _ status: OSStatus) -> TapError {
        TapError(message: "Falha ao \(step) (erro \(status)).")
    }
}

/// Owns one process tap, its private aggregate device and the IO proc reading from it.
@available(macOS 14.2, *)
final class TapCapture {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var analyzer: SpectrumAnalyzer?
    private let queue = DispatchQueue(label: "MenuBarPlayer.tap", qos: .userInteractive)

    init(bundlePrefix: String, onBands: @escaping ([Float]) -> Void) throws {
        let processes = try Self.audioProcesses(bundlePrefix: bundlePrefix)
        guard !processes.isEmpty else { throw TapError(message: "O app de música ainda não está tocando áudio.") }

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError.os("criar a captura de áudio", status) }

        do {
            let format: AudioStreamBasicDescription = try Self.property(tapID, kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
            guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
                throw TapError(message: "Formato de áudio não suportado.")
            }
            let outputID: AudioObjectID = try Self.property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, default: 0)
            let outputUID = try Self.stringProperty(outputID, kAudioDevicePropertyDeviceUID)

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "MenuBarPlayer Spectrum",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
            guard status == noErr else { throw TapError.os("criar o dispositivo de captura", status) }

            let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate, bands: spectrumBandCount)
            self.analyzer = analyzer
            let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            let channels = max(1, Int(format.mChannelsPerFrame))

            status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                if let bands = analyzer.consume(buffers, interleaved: interleaved, channels: channels) {
                    onBands(bands)
                }
            }
            guard status == noErr else { throw TapError.os("ler o áudio", status) }
            status = AudioDeviceStart(aggregateID, procID)
            guard status == noErr else { throw TapError.os("iniciar a captura", status) }
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Core Audio properties

    /// Audio process objects whose bundle id starts with the music app's (includes helpers).
    private static func audioProcesses(bundlePrefix: String) throws -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard status == noErr else { throw TapError.os("listar processos de áudio", status) }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids)
        guard status == noErr else { throw TapError.os("listar processos de áudio", status) }
        return ids.filter { id in
            (try? stringProperty(id, kAudioProcessPropertyBundleID))?.hasPrefix(bundlePrefix) == true
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func property<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, default value: T) throws -> T {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw TapError.os("ler propriedade de áudio", status) }
        return result
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { throw TapError.os("ler propriedade de áudio", status) }
        return value.takeRetainedValue() as String
    }
}

/// Mono FFT over a sliding window, folded into log-spaced bands normalized to 0...1.
/// Only touched from the tap's serial queue.
final class SpectrumAnalyzer {
    private let size = 2048
    private let hop: Int
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let bandRanges: [Range<Int>]
    private let bandTilt: [Float]
    private var samples: [Float] = []
    private var smoothed: [Float]
    private var peakDB: Float = -40

    init(sampleRate: Double, bands: Int) {
        hop = min(size, max(512, Int(sampleRate / 30)))
        fft = vDSP.FFT(log2n: 11, radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        smoothed = [Float](repeating: 0, count: bands)

        let bins = size / 2
        let nyquist = sampleRate / 2
        var edges = (0...bands).map { index -> Int in
            let frequency = 40 * pow(16_000 / 40, Double(index) / Double(bands))
            return min(bins - 1, max(1, Int(frequency / nyquist * Double(bins))))
        }
        for index in 1..<edges.count where edges[index] <= edges[index - 1] {
            edges[index] = min(bins, edges[index - 1] + 1)
        }
        bandRanges = (0..<bands).map { edges[$0]..<max(edges[$0] + 1, edges[$0 + 1]) }
        // Music has less energy in high bands; lift them ~4.5 dB per octave above 1 kHz.
        bandTilt = bandRanges.map { range in
            let center = Double(range.lowerBound + range.upperBound) / 2 / Double(bins) * nyquist
            return Float(4.5 * log2(max(center, 40) / 1000))
        }
    }

    func consume(_ buffers: UnsafeMutableAudioBufferListPointer, interleaved: Bool, channels: Int) -> [Float]? {
        if interleaved, let buffer = buffers.first, let data = buffer.mData {
            let pointer = data.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            samples.reserveCapacity(samples.count + frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += pointer[frame * channels + channel] }
                samples.append(sum / Float(channels))
            }
        } else {
            let frames = buffers.map { Int($0.mDataByteSize) / MemoryLayout<Float>.size }.min() ?? 0
            guard frames > 0 else { return nil }
            var mono = [Float](repeating: 0, count: frames)
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let channel = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: frames)
                vDSP.add(mono, channel, result: &mono)
            }
            vDSP.multiply(1 / Float(max(1, buffers.count)), mono, result: &mono)
            samples.append(contentsOf: mono)
        }

        guard samples.count >= size else { return nil }
        let frame = Array(samples.suffix(size))
        samples.removeFirst(samples.count - (size - hop))
        return analyze(frame)
    }

    private func analyze(_ frame: [Float]) -> [Float] {
        if vDSP.rootMeanSquare(frame) < 1e-5 {
            smoothed = smoothed.map { $0 * 0.8 < 0.01 ? 0 : $0 * 0.8 }
            return smoothed
        }

        let windowed = vDSP.multiply(frame, window)
        let half = size / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }

        let decibels: [Float] = bandRanges.enumerated().map { index, range in
            let mean = power[range].reduce(0, +) / Float(range.count)
            return 10 * log10(mean + 1e-12) + bandTilt[index]
        }
        // Adaptive ceiling: follows loud passages quickly, relaxes slowly.
        peakDB = max(decibels.max() ?? peakDB, peakDB - 0.15)
        let range: Float = 45
        for index in decibels.indices {
            let level = min(1, max(0, (decibels[index] - (peakDB - range)) / range))
            let previous = smoothed[index]
            smoothed[index] = level > previous ? level : previous * 0.82 + level * 0.18
        }
        return smoothed
    }
}
