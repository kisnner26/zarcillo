import AppKit
import AudioToolbox
import CoreAudio

/// Volumen por app. macOS no lo trae: se usa un "grifo" de Core Audio sobre
/// los procesos de la app (que silencia su salida original) y un dispositivo
/// agregado privado que vuelve a tocar ese audio con la ganancia elegida.
/// En 100 % el grifo se retira y la app suena como siempre.
@MainActor
final class Mixer {
    private final class Gain: @unchecked Sendable { var value: Float = 1 }

    private struct Tap {
        let objects: Set<AudioObjectID>
        let tap: AudioObjectID
        let aggregate: AudioObjectID
        let proc: AudioDeviceIOProcID
        let gain: Gain
    }

    private var taps: [pid_t: Tap] = [:]
    private var gains: [pid_t: Double] = [:]
    private let queue = DispatchQueue(label: "zarcillo.mixer", qos: .userInteractive)

    // MARK: Lista

    /// Las apps que están sonando (o que ya tienen un volumen propio).
    func list() -> [MixerApp] {
        let groups = Self.processGroups()
        var out: [MixerApp] = []
        for (pid, info) in groups where info.playing || gains[pid] != nil {
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            out.append(MixerApp(id: pid, bundleID: app.bundleIdentifier ?? "",
                                name: app.localizedName ?? "app", gain: gains[pid] ?? 1,
                                playing: info.playing, icon: Self.icon(app)))
        }
        return out.sorted { $0.name < $1.name }
    }

    func set(_ pid: pid_t, gain: Double) {
        let g = min(1, max(0, gain))
        if g > 0.995 {
            gains[pid] = nil
            remove(pid)
            return
        }
        gains[pid] = g
        let objects = Self.processGroups()[pid]?.objects ?? []
        guard !objects.isEmpty else { return }
        if let t = taps[pid], t.objects == objects {
            t.gain.value = Float(g)
        } else {
            remove(pid)
            if let t = makeTap(objects: objects, gain: Float(g)) { taps[pid] = t }
        }
    }

    /// Si la app abrió otro proceso de audio (una pestaña nueva, por ejemplo), el grifo se rehace.
    func refresh() {
        guard !gains.isEmpty else { return }
        let groups = Self.processGroups()
        for (pid, g) in gains {
            guard let objects = groups[pid]?.objects, !objects.isEmpty else { continue }
            if taps[pid]?.objects != objects { set(pid, gain: g) }
        }
    }

    private func remove(_ pid: pid_t) {
        guard let t = taps.removeValue(forKey: pid) else { return }
        AudioDeviceStop(t.aggregate, t.proc)
        AudioDeviceDestroyIOProcID(t.aggregate, t.proc)
        AudioHardwareDestroyAggregateDevice(t.aggregate)
        AudioHardwareDestroyProcessTap(t.tap)
    }

    // MARK: Grifo

    private func makeTap(objects: Set<AudioObjectID>, gain: Float) -> Tap? {
        let desc = CATapDescription(stereoMixdownOfProcesses: Array(objects))
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { return nil }
        guard let output = Self.defaultOutputUID() else { AudioHardwareDestroyProcessTap(tap); return nil }

        let spec: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Zarcillo mezcla",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                                kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(spec as CFDictionary, &aggregate) == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }

        let box = Gain()
        box.value = gain
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue) { _, input, _, output, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outs = UnsafeMutableAudioBufferListPointer(output)
            let g = box.value
            // Las entradas del agregado terminan con las del grifo.
            let first = max(0, ins.count - outs.count)
            for (i, out) in outs.enumerated() {
                guard let dst = out.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let total = Int(out.mDataByteSize) / MemoryLayout<Float>.size
                let j = first + i
                guard j < ins.count, let src = ins[j].mData?.assumingMemoryBound(to: Float.self) else {
                    for k in 0..<total { dst[k] = 0 }
                    continue
                }
                let n = min(total, Int(ins[j].mDataByteSize) / MemoryLayout<Float>.size)
                for k in 0..<n { dst[k] = src[k] * g }
                if n < total { for k in n..<total { dst[k] = 0 } }
            }
        }
        guard status == noErr, let proc else {
            AudioHardwareDestroyAggregateDevice(aggregate)
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        AudioDeviceStart(aggregate, proc)
        return Tap(objects: objects, tap: tap, aggregate: aggregate, proc: proc, gain: box)
    }

    // MARK: Core Audio

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T) -> T {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let ok = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0) }
        return ok == noErr ? value : fallback
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Procesos de audio agrupados por la app responsable (Safari suena desde
    /// sus procesos de contenido web, Chrome desde sus "Helper").
    private static func processGroups() -> [pid_t: (objects: Set<AudioObjectID>, playing: Bool)] {
        var groups: [pid_t: (objects: Set<AudioObjectID>, playing: Bool)] = [:]
        let me = ProcessInfo.processInfo.processIdentifier
        for obj in processObjects() {
            let pid: pid_t = read(obj, kAudioProcessPropertyPID, -1)
            guard pid > 0, pid != me else { continue }
            let owner = responsible(pid)
            guard NSRunningApplication(processIdentifier: owner)?.activationPolicy == .regular else { continue }
            let playing: UInt32 = read(obj, kAudioProcessPropertyIsRunningOutput, 0)
            var g = groups[owner] ?? ([], false)
            g.objects.insert(obj)
            g.playing = g.playing || playing != 0
            groups[owner] = g
        }
        return groups
    }

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    private static func responsible(_ pid: pid_t) -> pid_t {
        guard let fn = responsibleFn else { return pid }
        let r = fn(pid)
        return r > 0 ? r : pid
    }

    private static func defaultOutputUID() -> String? {
        let device: AudioObjectID = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, 0)
        guard device != 0 else { return nil }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static var iconCache: [pid_t: Data] = [:]

    private static func icon(_ app: NSRunningApplication) -> Data? {
        if let d = iconCache[app.processIdentifier] { return d }
        guard let img = app.icon else { return nil }
        let size = NSSize(width: 64, height: 64)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let d = rep.representation(using: .png, properties: [:])
        iconCache[app.processIdentifier] = d
        return d
    }
}

// MARK: - Pestaña del navegador

/// La página que tienes abierta en el navegador del Mac.
enum BrowserTab {
    static func front() -> (url: String, title: String)? {
        let browsers: [(id: String, script: String)] = [
            ("com.apple.Safari", "tell application \"Safari\" to return {URL, name} of current tab of front window"),
            ("com.google.Chrome", "tell application \"Google Chrome\" to return {URL, title} of active tab of front window"),
            ("company.thebrowser.Browser", "tell application \"Arc\" to return {URL, title} of active tab of front window"),
            ("com.brave.Browser", "tell application \"Brave Browser\" to return {URL, title} of active tab of front window"),
            ("com.microsoft.edgemac", "tell application \"Microsoft Edge\" to return {URL, title} of active tab of front window"),
        ]
        // Primero el navegador que está al frente, luego cualquiera abierto.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let order = browsers.filter { $0.id == front } + browsers.filter { $0.id != front && running.contains($0.id) }
        for b in order {
            var error: NSDictionary?
            guard let result = NSAppleScript(source: b.script)?.executeAndReturnError(&error),
                  result.numberOfItems == 2,
                  let url = result.atIndex(1)?.stringValue, !url.isEmpty else { continue }
            return (url, result.atIndex(2)?.stringValue ?? "")
        }
        return nil
    }
}
