import Foundation
import Darwin
import IOKit
import IOKit.serial

public struct MicPort: Equatable, Identifiable {
    public let path: String
    public let name: String
    public var id: String { path }
    public init(path: String, name: String) { self.path = path; self.name = name }

    public static func discover() -> [MicPort] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                  IOServiceMatching(kIOSerialBSDServiceValue), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [MicPort] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                  path.hasPrefix("/dev/cu.usb") else { continue }
            var names: [String] = []
            var entry: io_registry_entry_t = service
            IOObjectRetain(entry)
            for _ in 0..<12 {
                for key in ["USB Product Name", "USB Vendor Name", "Product Name", "Manufacturer"] {
                    if let value = IORegistryEntryCreateCFProperty(entry, key as CFString,
                            kCFAllocatorDefault, 0)?.takeRetainedValue() as? String { names.append(value) }
                }
                var parent: io_registry_entry_t = 0
                let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
                IOObjectRelease(entry)
                entry = 0
                if status != KERN_SUCCESS { break }
                entry = parent
            }
            if entry != 0 { IOObjectRelease(entry) }
            let identity = names.joined(separator: " ").lowercased()
            // Never probe arbitrary USB serial devices, such as modems or dev boards.
            if identity.contains("ep-2350") || identity.contains("ep2350") || path.contains("usbmodemEPTXP") {
                result.append(MicPort(path: path, name: identity.contains("fx") ? "EP–2350 FX-MIC" : "EP–2350"))
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}

/// Half-duplex, bounded console polling. Only documented/read-only sensor calls
/// are sent. In particular, no Ctrl-C, Ctrl-D, callback changes or firmware writes.
public final class SerialConnection {
    public var onSnapshot: ((DeviceSnapshot) -> Void)?
    public var onStatus: ((String) -> Void)?
    public var onDisconnect: (() -> Void)?
    private let queue = DispatchQueue(label: "local.fxtalk.serial")
    private var fd: Int32 = -1
    private var timer: DispatchSourceTimer?
    private var decoder = LineDecoder()
    private var waitingSince: TimeInterval?
    private var failureCount = 0
    private var closed = false
    private var verified = false

    public init() {}
    public func start(path: String) {
        queue.async { self.openPort(path) }
    }
    public func stop() {
        queue.async { self.closePort(notify: false) }
    }
    private func status(_ message: String) {
        DispatchQueue.main.async { self.onStatus?(message) }
    }
    private func openPort(_ path: String) {
        guard fd < 0, !closed else { return }
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { status("Couldn’t open the mic’s USB connection."); closePort(notify: true); return }
        // Exclusive access prevents two controllers polling the same console.
        guard ioctl(fd, TIOCEXCL) == 0 else {
            status("Another app is using this mic’s USB controls."); closePort(notify: true); return
        }
        var settings = termios()
        guard tcgetattr(fd, &settings) == 0 else { closePort(notify: true); return }
        cfmakeraw(&settings)
        cfsetspeed(&settings, speed_t(B115200))
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard tcsetattr(fd, TCSANOW, &settings) == 0 else { closePort(notify: true); return }
        status("Checking the mic’s stock USB controls…")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.025)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }
    private func tick() {
        guard fd >= 0, !closed else { return }
        var bytes = [UInt8](repeating: 0, count: 4096)
        for _ in 0..<8 {
            let n = Darwin.read(fd, &bytes, bytes.count)
            if n > 0 {
                for line in decoder.append(Data(bytes.prefix(n))) {
                    if let snapshot = DeviceSnapshot.parse(line) {
                        waitingSince = nil; failureCount = 0
                        if !verified { verified = true; status("USB controls connected") }
                        DispatchQueue.main.async { self.onSnapshot?(snapshot) }
                    } else if line.hasPrefix("AttributeError:") || line.hasPrefix("ImportError:") || line.hasPrefix("NameError:") {
                        status("This firmware didn’t expose the expected controls. Nothing was changed.")
                        closePort(notify: true); return
                    }
                }
            } else if n == 0 {
                status("Mic disconnected"); closePort(notify: true); return
            } else if errno == EAGAIN || errno == EWOULDBLOCK { break }
            else if errno == EINTR { continue }
            else { status("Mic disconnected"); closePort(notify: true); return }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let pending = waitingSince {
            if now - pending < 0.75 { return }
            failureCount += 1; waitingSince = nil
            if failureCount >= 3 {
                status("No sensor reply. Power-cycle the mic, then click Reconnect.")
                closePort(notify: true); return
            }
        }
        let command = Array(DeviceSnapshot.query.utf8)
        var offset = 0
        while offset < command.count {
            let n = command.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), command.count - offset) }
            if n <= 0 { status("USB write failed. Click Reconnect."); closePort(notify: true); return }
            offset += n
        }
        waitingSince = now
    }
    private func closePort(notify: Bool) {
        guard !closed else { return }
        closed = true
        timer?.cancel(); timer = nil
        if fd >= 0 { _ = ioctl(fd, TIOCNXCL); Darwin.close(fd); fd = -1 }
        if notify { DispatchQueue.main.async { self.onDisconnect?() } }
    }
}
