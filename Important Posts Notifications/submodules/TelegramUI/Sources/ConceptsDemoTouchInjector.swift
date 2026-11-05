import Foundation
import UIKit
import ObjectiveC

// Локальные концепты: настоящие касания для записи ролика. Касание собирается по схеме KIF: свой UITouch,
// событие UIEvent и IOHIDEvent, затем UIApplication.sendEvent. Так у нажатых кнопок, строк и тогглов
// появляются родные состояния нажатия, а жесты (долгое нажатие, тап) проходят весь обычный путь.
// Работает на приватных селекторах: каждый шаг проверяется, пропуски пишутся в /tmp/concepts-injector.log.

final class ConceptsDemoTouchInjector {
    private typealias CreateDigitizer = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32, Double, Double, Double, Double, Double, UInt8, UInt8, UInt32) -> UnsafeMutableRawPointer?
    private typealias CreateFinger = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, Double, Double, Double, Double, Double, UInt8, UInt8, UInt32) -> UnsafeMutableRawPointer?
    private typealias AppendEvent = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt32) -> Void
    
    private var touch: NSObject?
    private weak var window: UIWindow?
    private var location: CGPoint = .zero
    private(set) var isAvailable = true
    
    private func log(_ text: String) {
        let line = text + "\n"
        if let handle = FileHandle(forWritingAtPath: "/tmp/concepts-injector.log") {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: "/tmp/concepts-injector.log", atomically: true, encoding: .utf8)
        }
    }
    
    private func mainWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if let key = windowScene.keyWindow {
                    return key
                }
                if let first = windowScene.windows.first(where: { $0.windowLevel == .normal }) {
                    return first
                }
            }
        }
        return nil
    }
    
    // MARK: - IOHIDEvent
    
    private func hidEvent(phase: UITouch.Phase, point: CGPoint) -> UnsafeMutableRawPointer? {
        guard let createDigitizer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDEventCreateDigitizerEvent"),
              let createFinger = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDEventCreateDigitizerFingerEvent"),
              let append = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOHIDEventAppendEvent") else {
            self.log("hid: символы IOHIDEvent не найдены")
            return nil
        }
        let timestamp = mach_absolute_time()
        let digitizer = unsafeBitCast(createDigitizer, to: CreateDigitizer.self)
        let finger = unsafeBitCast(createFinger, to: CreateFinger.self)
        let appendEvent = unsafeBitCast(append, to: AppendEvent.self)
        let touching: UInt8 = (phase == .ended || phase == .cancelled) ? 0 : 1
        let mask: UInt32 = (phase == .moved) ? 4 : 3
        guard let parent = digitizer(kCFAllocatorDefault, timestamp, 3, 0, 0, mask, 0, 0, 0, 0, 0, 0, 0, 0, 0) else {
            return nil
        }
        if let child = finger(kCFAllocatorDefault, timestamp, 1, 2, mask, Double(point.x), Double(point.y), 0, 0, 0, touching, touching, 0) {
            appendEvent(parent, child, 0)
        }
        return parent
    }
    
    // MARK: - Приватные вызовы
    
    private func callObject(_ object: NSObject, _ selector: String, _ argument: AnyObject?) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else {
            self.log("нет селектора \(selector)")
            return
        }
        _ = object.perform(sel, with: argument)
    }
    
    private func callInt(_ object: NSObject, _ selector: String, _ value: Int) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel), let imp = object.method(for: sel) else {
            self.log("нет селектора \(selector)")
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(imp, to: Function.self)(object, sel, value)
    }
    
    private func callDouble(_ object: NSObject, _ selector: String, _ value: Double) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel), let imp = object.method(for: sel) else {
            self.log("нет селектора \(selector)")
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, Double) -> Void
        unsafeBitCast(imp, to: Function.self)(object, sel, value)
    }
    
    private func callBool(_ object: NSObject, _ selector: String, _ value: Bool) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel), let imp = object.method(for: sel) else {
            self.log("нет селектора \(selector)")
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(imp, to: Function.self)(object, sel, value)
    }
    
    private func setLocation(_ touch: NSObject, _ point: CGPoint, reset: Bool) {
        let sel = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
        guard touch.responds(to: sel), let imp = touch.method(for: sel) else {
            self.log("нет селектора _setLocationInWindow:resetPrevious:")
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, CGPoint, Bool) -> Void
        unsafeBitCast(imp, to: Function.self)(touch, sel, point, reset)
    }
    
    private func send(phase: UITouch.Phase, point: CGPoint) {
        guard let touch = self.touch, let window = self.window else {
            return
        }
        self.callInt(touch, "setPhase:", phase.rawValue)
        self.callDouble(touch, "setTimestamp:", ProcessInfo.processInfo.systemUptime)
        self.setLocation(touch, point, reset: phase == .began)
        
        guard let event = UIApplication.shared.perform(NSSelectorFromString("_touchesEvent"))?.takeUnretainedValue() as? NSObject else {
            self.log("нет _touchesEvent")
            self.isAvailable = false
            return
        }
        _ = event.perform(NSSelectorFromString("_clearTouches"))
        if let hid = self.hidEvent(phase: phase, point: point) {
            let sel = NSSelectorFromString("_setHIDEvent:")
            if event.responds(to: sel), let imp = event.method(for: sel) {
                typealias Function = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(imp, to: Function.self)(event, sel, hid)
            }
            let touchSel = NSSelectorFromString("_setHidEvent:")
            if touch.responds(to: touchSel), let imp = touch.method(for: touchSel) {
                typealias Function = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(imp, to: Function.self)(touch, touchSel, hid)
            }
        }
        let addSel = NSSelectorFromString("_addTouch:forDelayedDelivery:")
        if event.responds(to: addSel), let imp = event.method(for: addSel) {
            typealias Function = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> Void
            unsafeBitCast(imp, to: Function.self)(event, addSel, touch, false)
        } else {
            self.log("нет _addTouch:forDelayedDelivery:")
            self.isAvailable = false
            return
        }
        if let uiEvent = event as? UIEvent {
            UIApplication.shared.sendEvent(uiEvent)
        }
        _ = window
    }
    
    // MARK: - Публичный интерфейс
    
    func down(at point: CGPoint) {
        guard let window = self.mainWindow(), let touchClass = NSClassFromString("UITouch") as? NSObject.Type else {
            self.log("нет окна или класса UITouch")
            self.isAvailable = false
            return
        }
        self.window = window
        self.location = point
        let touch = touchClass.init()
        self.callObject(touch, "setWindow:", window)
        let hit = window.hitTest(point, with: nil)
        self.callObject(touch, "setView:", hit)
        self.callObject(touch, "setGestureView:", hit)
        self.callInt(touch, "setTapCount:", 1)
        self.callBool(touch, "_setIsFirstTouchForView:", true)
        self.touch = touch
        self.log("down \(point) hit=\(String(describing: hit.map { String(describing: type(of: $0)) }))")
        self.send(phase: .began, point: point)
    }
    
    func move(to point: CGPoint) {
        self.location = point
        self.send(phase: .moved, point: point)
    }
    
    func up() {
        self.send(phase: .ended, point: self.location)
        self.touch = nil
    }
    
    private static func userEase(_ u: Double) -> Double {
        // Базовый изинг пользователя cubic-bezier(0, 0.4, 0, 1).
        let x1 = 0.0, y1 = 0.4, x2 = 0.0, y2 = 1.0
        var lo = 0.0, hi = 1.0
        for _ in 0 ..< 30 {
            let m = (lo + hi) / 2
            let x = 3 * (1 - m) * (1 - m) * m * x1 + 3 * (1 - m) * m * m * x2 + m * m * m
            if x < u { lo = m } else { hi = m }
        }
        let m = (lo + hi) / 2
        return 3 * (1 - m) * (1 - m) * m * y1 + 3 * (1 - m) * m * m * y2 + m * m * m
    }
    
    /// Перетаскивание пальцем: путь пальца идёт по изингу пользователя, поэтому скролл быстро стартует и плавно гаснет.
    func drag(from start: CGPoint, to end: CGPoint, duration: Double, completion: @escaping () -> Void) {
        self.down(at: start)
        let steps = max(2, Int(duration * 60.0))
        for step in 1 ... steps {
            let progress = Double(step) / Double(steps)
            let eased = ConceptsDemoTouchInjector.userEase(progress)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * progress, execute: { [weak self] in
                let point = CGPoint(x: start.x + (end.x - start.x) * CGFloat(eased), y: start.y + (end.y - start.y) * CGFloat(eased))
                self?.move(to: point)
                if step == steps {
                    self?.up()
                    completion()
                }
            })
        }
    }
}
