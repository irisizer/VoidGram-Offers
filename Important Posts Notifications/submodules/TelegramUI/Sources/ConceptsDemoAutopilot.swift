import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import ContextUI
import ChatControllerInteraction
import ChatMessageItemView
import ChatMessageItem
import ItemListUI
import ChatListUI
import UIKitRuntimeUtils
import GlassBackgroundComponent
import ChatTitleView
import AnimatedStickerNode
import TelegramAnimatedStickerNode

// Локальные концепты: автопилот для записи ролика (`--concepts-demo-autopilot`). Сам делает всё, что в ролике
// делал бы палец: долгое нажатие на пост, пункт меню, редактор, подсказки слов, приход постов, кнопка
// с колокольчиком, возврат к старым постам. Поверх экрана рисуются белые кружки-касания.
// Запись стартует по файлу /tmp/concepts-demo-go (его создаёт скрипт записи); точки касаний можно
// поправить без пересборки в /tmp/concepts-demo-coords.json: {"menuItem": [x, y], ...}.

/// Кольца тапов в запись не попадают: автопилот только пишет их в журнал (позиция, время, вид), а при сборке ролика кольцо рисуется
/// по ключам слоя «Tap» проекта Black Hole (белый контур 60 %, тень, размытие 30 и линза под контуром) — это точнее и синхронно
/// с касаниями. Для синхронизации записи и журнала в момент старта на 0,12 с вспыхивает белая полоса вне окна приложения
/// (внизу экрана, при сборке обрезается): по ней находится смещение между журналом и видео.
final class ConceptsDemoTouchOverlay {
    private let window: UIWindow
    private let flash = UIView()
    private(set) var events: [[String: Any]] = []
    var startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    // Тайминг кольца (как в AE): расширение 0,25 с, затем сжатие 0,25–0,417 с — в этот момент палец касается; тап отпускается
    // в конце сжатия (0,417 с), после чего кольцо расширяется и гаснет до 0,75 с.
    static let growDuration = 0.25, pressDuration = 0.1667
    
    init(scene: UIWindowScene?) {
        if let scene {
            self.window = UIWindow(windowScene: scene)
            self.window.frame = scene.screen.bounds
        } else {
            self.window = UIWindow(frame: UIScreen.main.bounds)
        }
        self.window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 2.0)
        self.window.backgroundColor = .clear
        self.window.isUserInteractionEnabled = false
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        self.window.rootViewController = controller
        let bounds = self.window.bounds
        self.flash.frame = CGRect(x: 0.0, y: bounds.height - 40.0, width: bounds.width, height: 40.0)
        self.flash.backgroundColor = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
        self.flash.isHidden = true
        controller.view.addSubview(self.flash)
        self.window.isHidden = false
    }
    
    private func log(_ type: String, _ point: CGPoint, extra: [String: Any] = [:]) {
        var event: [String: Any] = ["t": CFAbsoluteTimeGetCurrent() - self.startTime, "type": type, "x_pt": Double(point.x), "y_pt": Double(point.y)]
        for (key, value) in extra {
            event[key] = value
        }
        self.events.append(event)
    }
    
    /// Контейнер оверлея для временных демо-элементов (стикер поверх шапки и т. п.).
    var hostView: UIView {
        return self.window.rootViewController!.view
    }
    
    /// Вспышка для синхронизации: белая полоса внизу экрана, вне окна приложения.
    func flashSync() {
        self.events.append(["t": CFAbsoluteTimeGetCurrent() - self.startTime, "type": "flash"])
        self.flash.isHidden = false
        Queue.mainQueue().after(0.12, { [weak self] in
            self?.flash.isHidden = true
        })
    }
    
    /// Начало кольца (касание «приближается»): время появления кольца в журнале.
    func present(at point: CGPoint, long: Bool = false) {
        self.log("ring", point, extra: ["kind": long ? "long" : "tap"])
    }
    
    /// Отпускание долгого нажатия: кольцо расширяется и гаснет (для обычного тапа не вызывается).
    func release() {
        self.events.append(["t": CFAbsoluteTimeGetCurrent() - self.startTime, "type": "ringEnd"])
    }
    
    func mark(_ name: String) {
        self.events.append(["t": CFAbsoluteTimeGetCurrent() - self.startTime, "type": "mark", "name": name])
    }
    
    func writeLog() {
        if let data = try? JSONSerialization.data(withJSONObject: ["events": self.events], options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/concepts-demo-touches.json"))
        }
    }
}

enum ConceptsDemoAutopilot {
    /// Проверка настоящих касаний: после запуска тапает по первой строке списка чатов и пишет результат в /tmp/concepts-injector.log.
    static func touchTest(context: AccountContext) {
        let injector = ConceptsDemoTouchInjector()
        Queue.mainQueue().after(14.0, {
            injector.down(at: CGPoint(x: 200.0, y: 230.0))
            Queue.mainQueue().after(0.12, {
                injector.up()
                Queue.mainQueue().after(1.5, {
                    let top = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController
                    let line = "touch-test: top controller = \(String(describing: top.map { type(of: $0) })), available=\(injector.isAvailable)\n"
                    if let handle = FileHandle(forWritingAtPath: "/tmp/concepts-injector.log") {
                        handle.seekToEndOfFile()
                        handle.write(line.data(using: .utf8)!)
                        handle.closeFile()
                    } else {
                        try? line.write(toFile: "/tmp/concepts-injector.log", atomically: true, encoding: .utf8)
                    }
                })
            })
        })
    }

    private static let startPostPrefix = "TON hits a new monthly high"
    
    private static func point(_ coords: [String: [Double]], _ key: String, _ fallback: CGPoint) -> CGPoint {
        if let value = coords[key], value.count == 2 {
            return CGPoint(x: value[0], y: value[1])
        }
        return fallback
    }
    
    private static func chat() -> ChatControllerImpl? {
        guard let navigationController = ConceptsDemoAutopilot.navigationController() else {
            return nil
        }
        return navigationController.topViewController as? ChatControllerImpl
    }
    
    private static var contextProvider: AccountContext?
    
    private static func navigationController() -> NavigationController? {
        return self.contextProvider?.sharedContext.mainWindow?.viewController as? NavigationController
    }
    
    static func run(context: AccountContext, window: UIWindow) {
        self.contextProvider = context
        let peerId = ConceptsOfflineDemo.cryptoChannelId
        let overlay = ConceptsDemoTouchOverlay(scene: window.windowScene)
        
        let _ = updateConceptsMuteException(postbox: context.account.postbox, peerId: peerId, { _ in ConceptsMuteException() }).startStandalone()
        
        // Подготовка: открыть канал и поставить стартовый пост наверх, без подсветки.
        Queue.mainQueue().after(3.0, {
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).startStandalone(next: { peer in
                guard let peer, let navigationController = self.navigationController() else {
                    return
                }
                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
            })
        })
        Queue.mainQueue().after(7.0, {
            self.scrollToStartPost(context: context, animated: false)
        })
        Queue.mainQueue().after(9.0, {
            self.scrollToStartPost(context: context, animated: false)
            try? "ready".write(toFile: "/tmp/concepts-demo-ready", atomically: true, encoding: .utf8)
            self.waitForGo(context: context, overlay: overlay)
        })
    }
    
    private static func startPostIndices(context: AccountContext) -> Signal<(start: MessageIndex, last: MessageIndex)?, NoError> {
        return context.account.postbox.transaction { transaction -> (start: MessageIndex, last: MessageIndex)? in
            var start: MessageIndex?
            for id in 1 ... 40 {
                if let message = transaction.getMessage(MessageId(peerId: ConceptsOfflineDemo.cryptoChannelId, namespace: Namespaces.Message.Cloud, id: Int32(id))), message.text.hasPrefix(self.startPostPrefix) {
                    start = message.index
                    break
                }
            }
            let last = transaction.getTopPeerMessageIndex(peerId: ConceptsOfflineDemo.cryptoChannelId)
            if let start, let last {
                return (start, last)
            }
            return nil
        }
    }
    
    private static func scrollToStartPost(context: AccountContext, animated: Bool) {
        let _ = (self.startPostIndices(context: context) |> deliverOnMainQueue).startStandalone(next: { indices in
            guard let indices, let chat = self.chat() else {
                return
            }
            chat.chatDisplayNode.historyNode.scrollToMessage(from: indices.last, to: indices.start, animated: animated, highlight: false, scrollPosition: conceptsDemoScrollPosition(key: "startScroll", fallback: .bottom(0.0)))
        })
    }
    
    private static func waitForGo(context: AccountContext, overlay: ConceptsDemoTouchOverlay) {
        if FileManager.default.fileExists(atPath: "/tmp/concepts-demo-go") {
            try? FileManager.default.removeItem(atPath: "/tmp/concepts-demo-go")
            // Перед стартом позиция чата перепроверяется (должен быть виден последний пост целиком).
            self.scrollToStartPost(context: context, animated: false)
            Queue.mainQueue().after(0.4, {
                self.play(context: context, overlay: overlay)
            })
        } else {
            Queue.mainQueue().after(0.05, {
                self.waitForGo(context: context, overlay: overlay)
            })
        }
    }
    
    private static func waitUntil(timeout: Double = 8.0, _ condition: @escaping () -> Bool, then: @escaping () -> Void) {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        func check() {
            if condition() || CFAbsoluteTimeGetCurrent() > deadline {
                then()
            } else {
                Queue.mainQueue().after(0.05, check)
            }
        }
        check()
    }
    
    private static func waitForTopMessage(context: AccountContext, atLeast id: Int32, then: @escaping () -> Void) {
        let deadline = CFAbsoluteTimeGetCurrent() + 8.0
        func check() {
            let _ = (context.account.postbox.transaction { transaction -> Int32 in
                return transaction.getTopPeerMessageId(peerId: ConceptsOfflineDemo.cryptoChannelId, namespace: Namespaces.Message.Cloud)?.id ?? 0
            } |> deliverOnMainQueue).startStandalone(next: { top in
                if top >= id || CFAbsoluteTimeGetCurrent() > deadline {
                    then()
                } else {
                    Queue.mainQueue().after(0.1, check)
                }
            })
        }
        check()
    }
    
    /// Настоящий тап по таймингу тапа из AE (Black Hole): кольцо расширяется 0,25 с; палец касается в момент начала сжатия (0,25 с)
    /// и отпускается в его конце (0,417 с), когда кольцо расширяется и гаснет: интерфейс отвечает сразу после этого.
    private static func realTap(_ overlay: ConceptsDemoTouchOverlay, _ injector: ConceptsDemoTouchInjector, at point: CGPoint, hold: Double = 0.0, direct: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        overlay.present(at: point)
        if let direct {
            // Без реального касания: у стеклянной кнопки нет «дёрганья» от нажатия, действие вызывается напрямую.
            Queue.mainQueue().after(ConceptsDemoTouchOverlay.growDuration, {
                direct()
                completion?()
            })
            return
        }
        Queue.mainQueue().after(ConceptsDemoTouchOverlay.growDuration, {
            injector.down(at: point)
        })
        Queue.mainQueue().after(ConceptsDemoTouchOverlay.growDuration + ConceptsDemoTouchOverlay.pressDuration, {
            injector.up()
            completion?()
        })
    }
    
    /// Скролл настоящим перетаскиванием, без кольца (по просьбе: скроллы тапами не показываются).
    private static func scroll(_ injector: ConceptsDemoTouchInjector, from: CGPoint, to: CGPoint, duration: Double = 0.9, completion: @escaping () -> Void) {
        injector.drag(from: from, to: to, duration: duration, completion: completion)
    }
    
    // MARK: - Редактор: живые координаты строк (после футера и скролла положения меняются)
    
    private static func editorController() -> ItemListController? {
        return self.navigationController()?.topViewController as? ItemListController
    }
    
    private static func editorRows() -> (media: ListViewItemNode?, other: ListViewItemNode?, giveaways: ListViewItemNode?) {
        guard let controller = self.editorController() else {
            return (nil, nil, nil)
        }
        var expandables: [ListViewItemNode] = []
        var switches: [ListViewItemNode] = []
        controller.forEachItemNode { node in
            if node is ItemListExpandableSwitchItemNode {
                expandables.append(node)
            } else if node is ItemListSwitchItemNode {
                switches.append(node)
            }
        }
        expandables.sort(by: { $0.frame.minY < $1.frame.minY })
        switches.sort(by: { $0.frame.minY < $1.frame.minY })
        return (expandables.first, expandables.count > 1 ? expandables[1] : nil, switches.count > 2 ? switches[2] : nil)
    }
    
    /// Шеврон строки аккордеона в координатах окна (тап идёт прямо в него).
    private static func headerPoint(_ node: ListViewItemNode?) -> CGPoint? {
        guard let node = node as? ItemListExpandableSwitchItemNode else {
            return nil
        }
        return node.view.convert(node.demoExpandArrowCenter, to: nil)
    }
    
    private static func togglePoint(_ node: ListViewItemNode?) -> CGPoint? {
        guard let node else {
            return nil
        }
        // Центр настоящего переключателя в строке.
        if let switchNode = self.findNode(in: node, { String(describing: type(of: $0)).hasSuffix("SwitchNode") && $0.bounds.width > 20.0 }) {
            return switchNode.view.convert(CGPoint(x: switchNode.bounds.midX, y: switchNode.bounds.midY), to: nil)
        }
        return node.view.convert(CGPoint(x: 339.0, y: node.bounds.height / 2.0), to: nil)
    }
    
    // MARK: - Поиск живых элементов (тап всегда в центр настоящего элемента)
    
    private static func allWindows() -> [UIWindow] {
        var result: [UIWindow] = []
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                result.append(contentsOf: windowScene.windows)
            }
        }
        return result
    }
    
    private static func findNode(in root: ASDisplayNode, _ match: (ASDisplayNode) -> Bool) -> ASDisplayNode? {
        if match(root) {
            return root
        }
        for sub in root.subnodes ?? [] {
            if let found = self.findNode(in: sub, match) {
                return found
            }
        }
        return nil
    }
    
    private static func findNode(inView view: UIView, _ match: (ASDisplayNode) -> Bool) -> ASDisplayNode? {
        if let node = view.asyncdisplaykit_node, let found = self.findNode(in: node, match) {
            return found
        }
        for sub in view.subviews {
            if let found = self.findNode(inView: sub, match) {
                return found
            }
        }
        return nil
    }
    
    private static func findNode(_ match: (ASDisplayNode) -> Bool) -> ASDisplayNode? {
        for window in self.allWindows().reversed() {
            if let found = self.findNode(inView: window, match) {
                return found
            }
        }
        return nil
    }
    
    private static func windowCenter(_ node: ASDisplayNode) -> CGPoint {
        return node.layer.convert(CGPoint(x: node.bounds.midX, y: node.bounds.midY), to: nil)
    }
    
    private static func findTextView(_ view: UIView, prefix: String, exact: Bool) -> UIView? {
        if let text = view as? ImmediateTextView, let string = text.attributedText?.string, text.bounds.width > 1.0, exact ? string == prefix : string.hasPrefix(prefix) {
            return view
        }
        for sub in view.subviews {
            if let found = self.findTextView(sub, prefix: prefix, exact: exact) {
                return found
            }
        }
        return nil
    }
    
    private static func textView(prefix: String, exact: Bool = false) -> UIView? {
        for window in self.allWindows().reversed() {
            if let found = self.findTextView(window, prefix: prefix, exact: exact) {
                return found
            }
        }
        return nil
    }
    
    /// Центр текстового узла с заданным началом строки (пункт меню, подсказка).
    private static func textPoint(prefix: String, exact: Bool = false) -> CGPoint? {
        if let view = self.textView(prefix: prefix, exact: exact) {
            return view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        }
        let node = self.findNode({ node in
            if let text = node as? ImmediateTextNode, let string = text.attributedText?.string {
                return (exact ? string == prefix : string.hasPrefix(prefix)) && node.bounds.width > 1.0
            }
            return false
        })
        return node.map { self.windowCenter($0) }
    }
    
    /// Анимация нажатия кнопки без настоящего касания: кнопка под точкой сжимается и пружинит обратно, затем действие.
    private static func pressAnimation(at point: CGPoint, then action: @escaping () -> Void) {
        var target: UIView?
        for window in self.allWindows().reversed() {
            if var view = window.hitTest(point, with: nil) {
                // Поднимаемся до всей кнопки (стеклянный круг ≈44 pt), а не до значка галки внутри.
                while let parent = view.superview, parent.bounds.width <= 64.0, parent.bounds.height <= 64.0 {
                    view = parent
                }
                target = view
                break
            }
        }
        guard let view = target, view.bounds.width < 80.0 else {
            action()
            return
        }
        UIView.animate(withDuration: 0.12, delay: 0.0, options: [.curveEaseOut], animations: {
            view.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        }, completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.0, options: [], animations: {
                view.transform = .identity
            })
            // Шторка уходит, когда нажатие закончилось (кнопка уже пружинит назад).
            Queue.mainQueue().after(0.15, action)
        })
    }
    
    /// Центр строки пункта контекстного меню (а не текста): тап по центру ячейки.
    private static func menuRowCenter(prefix: String) -> CGPoint? {
        guard let textView = self.textView(prefix: prefix) else {
            // Текст пункта — узел (ImmediateTextNode): поднимаемся до строки пункта (высота < 70 pt).
            // Пункты меню рисуются TextNode с сущностями (не ImmediateTextNode) — берём текст из раскладки.
            let textNode = self.findNode({ node in
                if let text = node as? TextNode, let string = text.cachedLayout?.attributedString?.string {
                    return string.hasPrefix(prefix) && node.bounds.width > 1.0
                }
                return false
            })
            guard var row = textNode else {
                return nil
            }
            while let parent = row.supernode, parent.bounds.height < 70.0 {
                row = parent
            }
            let frame = row.view.convert(row.bounds, to: nil)
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        var row: UIView = textView
        var current: UIView? = textView.superview
        while let view = current, view.bounds.height < 70.0 {
            row = view
            current = view.superview
        }
        let frame = row.convert(row.bounds, to: nil)
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    /// Рамка пункта контекстного меню (строка с заданным началом текста) и его бейджа в координатах окна, в 0,1 pt.
    private static func menuRowMark(prefix: String) -> String? {
        guard let textView = self.textView(prefix: prefix) else {
            return nil
        }
        // Строка пункта: ближайший родитель выше текста с шириной меню (≥ 150 pt) и высотой строки (< 70 pt).
        var row: UIView = textView
        var current: UIView? = textView.superview
        while let view = current, view.bounds.height < 70.0 {
            row = view
            current = view.superview
        }
        let frame = row.convert(row.bounds, to: nil)
        var badgeFrame = CGRect()
        func findBadge(_ view: UIView) -> UIView? {
            if view.bounds.height > 16.0, view.bounds.height < 20.0, view.bounds.width > 24.0, view.bounds.width < 80.0, view !== textView {
                if let node = view.asyncdisplaykit_node, node is ASImageNode {
                    return view
                }
                if view is UIImageView {
                    return view
                }
            }
            for sub in view.subviews {
                if let found = findBadge(sub) {
                    return found
                }
            }
            return nil
        }
        var badgeNode: ASDisplayNode?
        if let node = row.asyncdisplaykit_node {
            badgeNode = self.findNode(in: node, { candidate in
                return candidate is ASImageNode && candidate.bounds.height > 16.0 && candidate.bounds.height < 20.0 && candidate.bounds.width > 24.0
            })
        }
        if let badgeNode {
            badgeFrame = badgeNode.layer.convert(badgeNode.bounds, to: nil)
        } else if let view = findBadge(row) {
            badgeFrame = view.convert(view.bounds, to: nil)
        }
        func v(_ x: CGFloat) -> Int { return Int(x * 10.0) }
        return "menuRowX\(v(frame.minX))Y\(v(frame.minY))W\(v(frame.width))H\(v(frame.height))BX\(v(badgeFrame.minX))BY\(v(badgeFrame.minY))BW\(v(badgeFrame.width))BH\(v(badgeFrame.height))"
    }
    
    private static func findTextField(_ view: UIView) -> UITextField? {
        if let field = view as? UITextField, field.bounds.width > 40.0, !field.isHidden, field.window != nil {
            return field
        }
        for sub in view.subviews {
            if let found = self.findTextField(sub) {
                return found
            }
        }
        return nil
    }
    
    private static func textFieldPoint() -> CGPoint? {
        for window in self.allWindows().reversed() {
            if let field = self.findTextField(window) {
                return field.convert(CGPoint(x: min(field.bounds.width / 2.0, 90.0), y: field.bounds.midY), to: nil)
            }
        }
        return nil
    }
    
    /// Качает настоящую иконку-колокольчик пункта меню (один раз), без подложек.
    private static func swingMenuIcon(prefix: String) {
        guard let textView = self.textView(prefix: prefix) else {
            return
        }
        var row: UIView = textView
        var current: UIView? = textView.superview
        while let view = current, view.bounds.height < 70.0 {
            row = view
            current = view.superview
        }
        let textFrame = textView.convert(textView.bounds, to: row)
        func findIcon(_ view: UIView) -> UIView? {
            let frame = view.convert(view.bounds, to: row)
            if view !== textView, frame.width >= 16.0, frame.width <= 34.0, frame.height >= 16.0, frame.height <= 34.0, frame.maxX <= textFrame.minX + 1.0 {
                return view
            }
            for sub in view.subviews {
                if let found = findIcon(sub) {
                    return found
                }
            }
            return nil
        }
        guard let icon = findIcon(row) else {
            return
        }
        let layer = icon.layer
        let oldFrame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.12)
        layer.frame = oldFrame
        let swing = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        swing.values = [0.0, 0.38, -0.32, 0.22, -0.13, 0.06, 0.0]
        swing.keyTimes = [0.0, 0.14, 0.32, 0.5, 0.68, 0.85, 1.0]
        swing.duration = 0.9
        swing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(swing, forKey: "demoMenuBellSwing")
    }
    
    private static func findLabel(_ view: UIView, prefix: String) -> UILabel? {
        if let label = view as? UILabel, let text = label.text, text.hasPrefix(prefix), label.window != nil, !label.isHidden, label.alpha > 0.01 {
            return label
        }
        for sub in view.subviews {
            if let found = self.findLabel(sub, prefix: prefix) {
                return found
            }
        }
        return nil
    }
    
    /// Тап «Add a word»: точно по тексту плейсхолдера (он едет вправо, когда добавляются чипсы).
    private static func addWordPoint() -> CGPoint? {
        for window in self.allWindows().reversed() {
            if let label = self.findLabel(window, prefix: "Add a word") {
                let frame = label.convert(label.bounds, to: nil)
                return CGPoint(x: frame.minX + min(frame.width / 2.0, 46.0), y: frame.midY)
            }
        }
        return self.textFieldPoint()
    }
    
    private static func findTitleView(_ view: UIView) -> ChatTitleView? {
        if let title = view as? ChatTitleView {
            return title
        }
        for sub in view.subviews {
            if let found = self.findTitleView(sub) {
                return found
            }
        }
        return nil
    }
    
    /// Начало ролика: значок «без звука» в шапке увеличивается и через размытие и прозрачность превращается в стикер 🔕
    /// из официального пака; стикер проигрывается, затем всё возвращается в значок.
    private static func muteCallout(context: AccountContext, overlay: ConceptsDemoTouchOverlay, completion: @escaping () -> Void) {
        // Значок «без звука» в шапке — компонент TitleIconComponent (ищем по имени класса, он внутри ChatTitleComponent).
        // Значок «без звука» в шапке: маленький UIImageView (≈9 pt) внутри ChatNavigationBarTitleView, справа от названия.
        func findTitle(_ view: UIView) -> UIView? {
            if String(describing: type(of: view)).contains("ChatNavigationBarTitleView") {
                return view
            }
            for sub in view.subviews {
                if let found = findTitle(sub) {
                    return found
                }
            }
            return nil
        }
        func findIcon(_ view: UIView) -> UIView? {
            guard let title = findTitle(view) else {
                return nil
            }
            var best: UIImageView?
            func walk(_ v: UIView) {
                if let imageView = v as? UIImageView, imageView.image != nil, imageView.bounds.width >= 6.0, imageView.bounds.width <= 20.0, !imageView.isHidden, imageView.alpha > 0.01 {
                    let frame = imageView.convert(imageView.bounds, to: title)
                    if frame.midX > title.bounds.midX, best == nil || frame.midX > best!.convert(best!.bounds, to: title).midX {
                        best = imageView
                    }
                }
                for sub in v.subviews {
                    walk(sub)
                }
            }
            walk(title)
            return best
        }
        var iconView: UIView?
        for window in self.allWindows() {
            if let found = findIcon(window) {
                iconView = found
                break
            }
        }
        guard let iconView, let iconImageView = iconView as? UIImageView, let iconImage = iconImageView.image else {
            overlay.mark("calloutMuteMissing")
            var dump = ""
            func walk(_ view: UIView, _ depth: Int) {
                let frame = view.convert(view.bounds, to: nil)
                if frame.minY < 140.0, frame.width < 400.0, depth < 40 {
                    dump += "\(depth) \(type(of: view)) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))\n"
                }
                for sub in view.subviews {
                    walk(sub, depth + 1)
                }
            }
            for window in self.allWindows() {
                walk(window, 0)
            }
            try? dump.write(toFile: "/tmp/concepts-title-dump.txt", atomically: true, encoding: .utf8)
            completion()
            return
        }
        let iconLayer = iconView.layer
        let iconFrame = iconView.convert(iconView.bounds, to: nil)
        let host = overlay.hostView
        
        let stickerSide: CGFloat = 132.0
        let start = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        let target = CGPoint(x: host.bounds.midX, y: iconFrame.midY + 108.0)
        // Дуга: контрольная точка смещена вбок от середины прямой.
        let control = CGPoint(x: (start.x + target.x) / 2.0 + 46.0, y: (start.y + target.y) / 2.0 - 8.0)
        let startScale = max(iconFrame.width, 9.0) / stickerSide
        let swapDuration = 0.2
        
        // Один контейнер едет по дуге; внутри подсветка-подложка, значок и стикер. Подмена значок ↔ стикер — в самом начале
        // и в самом конце пути: размытие и прозрачность самих картинок (без плашек, границ блюра не видно).
        let mover = UIView(frame: CGRect(x: 0.0, y: 0.0, width: stickerSide, height: stickerSide))
        mover.center = start
        mover.transform = CGAffineTransform(scaleX: startScale, y: startScale)
        host.addSubview(mover)
        
        // Подложка за стикером едет вместе с ним (внутри контейнера): настоящий переменный блюр фона (backdrop-слой Telegram с маской),
        // радиус размытия плавно спадает от центра к краю по радиальной маске — без видимой границы. Светлота не добавляется.
        let glowSide = stickerSide * 2.3
        let glow = UIView(frame: CGRect(x: (stickerSide - glowSide) / 2.0, y: (stickerSide - glowSide) / 2.0, width: glowSide, height: glowSide))
        glow.alpha = 0.0
        glow.isUserInteractionEnabled = false
        if let backdrop = createBackdropLayer(), let variableBlur = CALayer.variableBlur() {
            // Радиальная маска: в центре блюр полный, к краю плавно сходит на нет (прогрессивный блюр).
            let maskImage = generateImage(CGSize(width: 256.0, height: 256.0), rotatedContext: { size, context in
                context.clear(CGRect(origin: CGPoint(), size: size))
                let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.85).cgColor, UIColor.white.withAlphaComponent(0.4).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
                var locations: [CGFloat] = [0.0, 0.35, 0.7, 1.0]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: &locations) {
                    let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
                    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: size.width / 2.0, options: [])
                }
            })
            variableBlur.setValue(12.0, forKey: "inputRadius")
            variableBlur.setValue(true, forKey: "inputNormalizeEdges")
            if let cgImage = maskImage?.cgImage {
                variableBlur.setValue(cgImage, forKey: "inputMaskImage")
            }
            backdrop.filters = [variableBlur]
            backdrop.setValue(0.5, forKey: "scale")
            backdrop.frame = glow.bounds
            glow.layer.addSublayer(backdrop)
        }
        // Светлая вуаль над блюром: радиальная (плотнее в центре, плавно исчезает к краю).
        // Затемнение вокруг стикера, как фон при лонгтапе, но локально: радиальное, края плавно уходят в ноль.
        let veilLayer = CAGradientLayer()
        veilLayer.frame = glow.bounds
        veilLayer.type = .radial
        veilLayer.colors = [UIColor(white: 0.0, alpha: 0.3).cgColor, UIColor(white: 0.0, alpha: 0.24).cgColor, UIColor(white: 0.0, alpha: 0.09).cgColor, UIColor(white: 0.0, alpha: 0.0).cgColor]
        veilLayer.locations = [0.0, 0.4, 0.72, 1.0]
        veilLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        veilLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        glow.layer.addSublayer(veilLayer)
        // За стикером экран слегка затемняется, как фон при лонгтапе, но слабее (без блюра).
        let dimView = UIView(frame: host.bounds)
        dimView.isUserInteractionEnabled = false
        dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.18)
        dimView.alpha = 0.0
        host.insertSubview(dimView, belowSubview: mover)
        
        let iconInside = UIImageView(image: iconImage)
        iconInside.tintColor = iconImageView.tintColor
        iconInside.contentMode = .scaleAspectFit
        iconInside.frame = mover.bounds
        mover.addSubview(iconInside)
        let sticker = DefaultAnimatedStickerNodeImpl(lottieSettings: context.lottieRenderingSettings)
        sticker.setup(source: AnimatedStickerNodeLocalFileSource(name: "ConceptsBellMuted"), width: Int(stickerSide * 3.0), height: Int(stickerSide * 3.0), playbackMode: .once, mode: .direct(cachePathPrefix: nil))
        sticker.frame = mover.bounds
        sticker.updateLayout(size: mover.bounds.size)
        sticker.view.alpha = 0.0
        mover.addSubview(sticker.view)
        iconLayer.opacity = 0.0
        overlay.mark("calloutMute")
        
        func blurFade(_ layer: CALayer, alphaFrom: Float, alphaTo: Float, blurFrom: CGFloat, blurTo: CGFloat) {
            if let filter = makeBlurFilter() {
                filter.setValue(blurTo as NSNumber, forKey: "inputRadius")
                layer.filters = [filter]
                layer.animate(from: blurFrom as NSNumber, to: blurTo as NSNumber, keyPath: "filters.gaussianBlur.inputRadius", timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, duration: swapDuration, removeOnCompletion: false, completion: { _ in
                    if blurTo == 0.0 {
                        layer.filters = []
                    }
                })
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = alphaFrom
            fade.toValue = alphaTo
            fade.duration = swapDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "swapFade")
            layer.opacity = alphaTo
        }
        func swap(toSticker: Bool) {
            // Значок размывается и гаснет, одновременно стикер из размытия проявляется (0,2 с).
            blurFade(iconInside.layer, alphaFrom: toSticker ? 1.0 : 0.0, alphaTo: toSticker ? 0.0 : 1.0, blurFrom: toSticker ? 0.0 : 10.0, blurTo: toSticker ? 10.0 : 0.0)
            blurFade(sticker.view.layer, alphaFrom: toSticker ? 0.0 : 1.0, alphaTo: toSticker ? 1.0 : 0.0, blurFrom: toSticker ? 10.0 : 0.0, blurTo: toSticker ? 0.0 : 10.0)
        }
        func travel(from: CGPoint, to: CGPoint, scaleFrom: CGFloat, scaleTo: CGFloat, duration: Double, springScale: Bool) {
            let path = UIBezierPath()
            path.move(to: from)
            path.addQuadCurve(to: to, controlPoint: control)
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path.cgPath
            move.duration = duration
            move.timingFunction = springScale ? CAMediaTimingFunction(controlPoints: 0.3, 0.0, 0.2, 1.0) : CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.12, 1.0)
            mover.layer.add(move, forKey: "arc")
            if springScale {
                // Возврат: масштаб с баунсом (проскакивает меньше значка и возвращается), подмена — прямо во время баунса.
                let scale = CASpringAnimation(keyPath: "transform.scale")
                scale.fromValue = scaleFrom
                scale.toValue = scaleTo
                scale.mass = 1.0
                scale.stiffness = 200.0
                scale.damping = 13.0
                scale.duration = scale.settlingDuration
                mover.layer.add(scale, forKey: "grow")
            } else {
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = scaleFrom
                scale.toValue = scaleTo
                scale.duration = duration
                scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.12, 1.0)
                mover.layer.add(scale, forKey: "grow")
            }
            mover.layer.position = to
            mover.transform = CGAffineTransform(scaleX: scaleTo, y: scaleTo)
        }
        // Туда: плавный старт (движение видно), стикер играет по пути; подмена — сразу в начале.
        let outDuration = 0.75
        sticker.visibility = true
        travel(from: start, to: target, scaleFrom: startScale, scaleTo: 1.0, duration: outDuration, springScale: false)
        swap(toSticker: true)
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseInOut], animations: {
            dimView.alpha = 1.0
        })
        // Обратно — после первого звона. Движение по дуге, у значка баунс масштаба; подмена на значок — во время баунса.
        let backAt = 1.15
        let backDuration = 0.55
        Queue.mainQueue().after(backAt, {
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseInOut], animations: {
                dimView.alpha = 0.0
            })
            travel(from: target, to: start, scaleFrom: 1.0, scaleTo: startScale, duration: backDuration, springScale: true)
            Queue.mainQueue().after(backDuration - 0.12, {
                swap(toSticker: false)
            })
        })
        Queue.mainQueue().after(backAt + backDuration + 0.55, {
            iconLayer.opacity = 1.0
            mover.removeFromSuperview()
            glow.removeFromSuperview()
            dimView.removeFromSuperview()
        })
        Queue.mainQueue().after(backAt + backDuration + 0.3, {
            completion()
        })
    }
    
    /// Петля: посты, пришедшие за ролик, удаляются в конце (они уже за экраном), чат снова внизу — как в первом кадре.
    private static func deleteReceivedPosts(context: AccountContext, after topId: Int32) {
        let _ = context.account.postbox.transaction({ transaction -> Void in
            var ids: [MessageId] = []
            let top = transaction.getTopPeerMessageId(peerId: ConceptsOfflineDemo.cryptoChannelId, namespace: Namespaces.Message.Cloud)?.id ?? 0
            if top > topId {
                for id in (topId + 1) ... top {
                    ids.append(MessageId(peerId: ConceptsOfflineDemo.cryptoChannelId, namespace: Namespaces.Message.Cloud, id: id))
                }
            }
            transaction.deleteMessages(ids, forEachMedia: nil)
        }).startStandalone()
    }
    
    private static var seedTopId: Int32 = 0
    
    // MARK: - Бесшовная петля
    /// Время вспышки синхронизации (= начало ролика − 0,15 с) и длина петли в ролике.
    private static var flashTime: CFAbsoluteTime = 0.0
    private static let loopDuration: Double = 29.0
    private static let stickerPeriod: Double = 3.0
    
    /// Ставит анимацию стикеров в ленте на нужную фазу: к концу петли кадр стикера совпадёт с первым кадром ролика.
    private static func syncStickers(fromIndex index: Int) {
        guard let historyNode = self.chat()?.chatDisplayNode.historyNode else {
            return
        }
        historyNode.forEachItemNode { item in
            if let sticker = self.findNode(in: item, { $0 is AnimatedStickerNode }) as? AnimatedStickerNode {
                sticker.play(firstFrame: false, fromIndex: index)
            }
        }
    }
    
    private static var loopStartStickerFrame: Int?
    private static weak var debugOverlay: ConceptsDemoTouchOverlay?
    
    private static func stickerCount() -> Int {
        var count = 0
        self.chat()?.chatDisplayNode.historyNode.forEachItemNode { item in
            if let sticker = self.findNode(in: item, { $0 is AnimatedStickerNode }) as? AnimatedStickerNode {
                count += sticker.isPlaying ? 10 : 1
            }
        }
        return count
    }
    
    /// Число кадров анимации стикера (рендер может идти не 60 к/с — частота = кадры / период).
    private static func stickerFrameCount() -> Int {
        var result = Int(self.stickerPeriod * 60.0)
        self.chat()?.chatDisplayNode.historyNode.forEachItemNode { item in
            if let sticker = self.findNode(in: item, { $0 is AnimatedStickerNode }) as? AnimatedStickerNode, sticker.currentFrameCount > 0 {
                result = sticker.currentFrameCount
            }
        }
        return result
    }
    
    private static func currentStickerFrame() -> Int? {
        guard let historyNode = self.chat()?.chatDisplayNode.historyNode else {
            return nil
        }
        var result: Int?
        historyNode.forEachItemNode { item in
            if result == nil, let sticker = self.findNode(in: item, { $0 is AnimatedStickerNode }) as? AnimatedStickerNode, sticker.isPlaying {
                result = sticker.currentFrameIndex
            }
        }
        return result
    }
    
    private static func syncStickersForLoopEnd() {
        // К концу петли стикер должен прийти ровно в тот кадр, что был в первом кадре ролика.
        let frames = self.stickerFrameCount()
        let fps = Double(frames) / self.stickerPeriod
        let now = CFAbsoluteTimeGetCurrent() - self.flashTime
        let remaining = (0.15 + self.loopDuration) - now
        let target = (self.loopStartStickerFrame ?? 0) - 3  // поправка на задержку отрисовки (замер по стыку: +2,5 кадра)
        var index = (target - Int((remaining * fps).rounded())) % frames
        if index < 0 { index += frames }
        self.syncStickers(fromIndex: index)
    }
    
    /// Вторая подгонка: через 0,4 с сравниваем фактический кадр с ожидаемым и снимаем задержку запуска анимации.
    private static func correctStickersForLoopEnd() {
        guard let actual = self.currentStickerFrame() else {
            return
        }
        let frames = self.stickerFrameCount()
        let fps = Double(frames) / self.stickerPeriod
        let now = CFAbsoluteTimeGetCurrent() - self.flashTime
        let remaining = (0.15 + self.loopDuration) - now
        let target = (self.loopStartStickerFrame ?? 0) - 3  // поправка на задержку отрисовки (замер по стыку: +2,5 кадра)
        var expected = (target - Int((remaining * fps).rounded())) % frames
        if expected < 0 { expected += frames }
        var lag = expected - actual
        self.debugOverlay?.mark("stkCheck\(expected)a\(actual)n\(self.stickerCount())")
        if lag > frames / 2 { lag -= frames }
        if lag < -frames / 2 { lag += frames }
        if abs(lag) >= 1 {
            var index = (expected + lag) % frames
            if index < 0 { index += frames }
            self.syncStickers(fromIndex: index)
        }
    }
    
    /// Центр пузыря стартового поста (долгое нажатие идёт именно в него).
    private static func startPostPoint() -> CGPoint? {
        guard let chat = self.chat() else {
            return nil
        }
        var result: CGPoint?
        chat.chatDisplayNode.historyNode.forEachVisibleItemNode { node in
            if let view = node as? ChatMessageItemView, let item = view.item, item.message.text.hasPrefix(self.startPostPrefix) {
                let center = view.layer.convert(CGPoint(x: 160.0, y: view.bounds.height / 2.0), to: nil)
                result = center
            }
        }
        return result
    }
    
    /// Верхняя ячейка списка чатов (после прихода постов это Crypto Morning) в координатах окна.
    private static func topChatListCellFrame() -> CGRect? {
        var best: CGRect?
        for window in self.allWindows() {
            let _ = self.findNode(inView: window, { node in
                if node is ChatListItemNode, (node as! ChatListItemNode).item != nil {
                    let rect = node.layer.convert(node.bounds, to: nil)
                    if rect.width > 100.0, rect.minY > 60.0, best == nil || rect.minY < best!.minY {
                        best = rect
                    }
                }
                return false
            })
        }
        return best
    }
    
    /// Один скролл жестом на заданную высоту (без поправок: слежение пальцем точное, потеря на порог распознавания учтена).
    private static func scrollOnce(_ injector: ConceptsDemoTouchInjector, distance: CGFloat, completion: @escaping () -> Void) {
        let slop: CGFloat = 6.0
        let total = max(20.0, min(distance + slop, 520.0))
        let startY = max(300.0, min(585.0, 60.0 + total))
        let duration = max(0.75, min(1.1, Double(total) / 430.0))
        self.scroll(injector, from: CGPoint(x: 200.0, y: startY), to: CGPoint(x: 200.0, y: startY - total), duration: duration, completion: completion)
    }
    
    private static func play(context: AccountContext, overlay: ConceptsDemoTouchOverlay) {
        let injector = ConceptsDemoTouchInjector()
        overlay.startTime = CFAbsoluteTimeGetCurrent()
        overlay.flashSync()
        self.debugOverlay = overlay
        self.flashTime = CFAbsoluteTimeGetCurrent()
        // Начало ролика (вспышка + 0,15 с): стикеры с первого кадра анимации.
        Queue.mainQueue().after(0.15, {
            // Запоминаем фактический кадр стикера в первом кадре ролика (без перезапуска — первый кадр не дёргается).
            // Кадр стикера, приведённый к моменту начала ролика (вызов мог прийти чуть позже 0,15 с).
            if let frame = self.currentStickerFrame() {
                let late = (CFAbsoluteTimeGetCurrent() - self.flashTime) - 0.15
                self.loopStartStickerFrame = frame - Int((late * Double(self.stickerFrameCount()) / self.stickerPeriod).rounded())
                self.debugOverlay?.mark("stkCount\(self.stickerFrameCount())")
            }
            self.debugOverlay?.mark("stkStart\(self.loopStartStickerFrame ?? -1)n\(self.stickerCount())")
        })
        var coords: [String: [Double]] = [:]
        if let data = FileManager.default.contents(atPath: "/tmp/concepts-demo-coords.json"), let json = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]] {
            coords = json
        }
        let postPressFallback = self.point(coords, "postPress", CGPoint(x: 180.0, y: 165.0))
        let menuItem = self.point(coords, "menuItem", CGPoint(x: 137.0, y: 382.0))
        let chipA = self.point(coords, "chipA", CGPoint(x: 57.0, y: 395.0))
        let chipB = self.point(coords, "chipB", CGPoint(x: 150.0, y: 395.0))
        let mediaRow = self.point(coords, "mediaRow", CGPoint(x: 120.0, y: 360.0))
        let otherRow = self.point(coords, "otherRow", CGPoint(x: 120.0, y: 531.0))
        let giveToggle = self.point(coords, "giveToggle", CGPoint(x: 339.0, y: 323.0))
        let close = self.point(coords, "close", CGPoint(x: 363.0, y: 103.0))
        let bell = self.point(coords, "bell", CGPoint(x: 356.0, y: 480.0))
        let back = self.point(coords, "back", CGPoint(x: 40.0, y: 96.0))
        let row = self.point(coords, "row", CGPoint(x: 200.0, y: 215.0))
        
        func after(_ time: Double, _ f: @escaping () -> Void) {
            Queue.mainQueue().after(time, f)
        }
        func chatIsTop() -> Bool {
            return self.chat() != nil
        }
        
        let _ = (context.account.postbox.transaction { transaction -> Int32 in
            return transaction.getTopPeerMessageId(peerId: ConceptsOfflineDemo.cryptoChannelId, namespace: Namespaces.Message.Cloud)?.id ?? 0
        } |> deliverOnMainQueue).startStandalone(next: { id in
            self.seedTopId = id
        })
        // 0. Канал без звука: значок mute → стикер 🔕 → обратно.
        after(0.3, {
            self.muteCallout(context: context, overlay: overlay, completion: {})
        })
        // 1. Долгое нажатие на стартовый пост: настоящий жест, меню открывается само.
        after(2.25, {
            let postPress = self.startPostPoint() ?? postPressFallback
            // Лонгтап: палец касается сразу, а кольцо в журнале появляется на 0,25 с позже — долгое нажатие срабатывает (≈0,67 с после касания)
            // ровно к концу сжатия кольца (0,42 с после его появления), как в слое «Tap 2» Black Hole.
            after(0.25, {
                overlay.present(at: postPress, long: true)
            })
            after(0.0, {
                injector.down(at: postPress)
                overlay.mark("longDown")
                self.waitUntil(timeout: 4.0, { self.chat()?.currentContextController != nil }, then: {
                    overlay.mark("menuOpen")
                    after(0.85, {
                        injector.up()
                        overlay.release()
                    })
                    // 2. Меню открыто: пункт увеличивается (врезка при сборке, с бейджем NEW и бликом), после этого тап по нему.
                    after(0.3, {
                        overlay.mark("calloutMenu")
                        after(0.4, {
                            self.swingMenuIcon(prefix: "Unmute Similar")
                        })
                    })
                    after(1.75, {
                        if let mark = self.menuRowMark(prefix: "Unmute Similar") {
                            overlay.mark(mark)
                        }
                        self.realTap(overlay, injector, at: self.menuRowCenter(prefix: "Unmute Similar") ?? menuItem, completion: {
                            // 3. Редактор: два тапа по подсказкам, третье слово «печатается».
                            self.waitUntil({ !chatIsTop() }, then: {
                                overlay.mark("editorShown")
                                // Редактор по единой сетке: TON, Telegram и «Add a word» — с одинаковым шагом 0,75 с; дальше без простоев.
                                let beat = 0.75
                                func at(_ time: Double, _ f: @escaping () -> Void) {
                                    after(time, f)
                                }
                                at(0.5, {
                                    self.realTap(overlay, injector, at: self.textPoint(prefix: "TON", exact: true) ?? chipA)
                                })
                                at(0.5 + beat, {
                                    self.realTap(overlay, injector, at: self.textPoint(prefix: "Telegram", exact: true) ?? chipB)
                                })
                                // Набор слов без пауз: тап по «Add a word» → сразу набор (в момент нажатия кольца) → слово сразу становится чипсом →
                                // сразу следующий тап. Слово: 7 символов × 0,055 с + 0,26 с.
                                let wordTime = 7.0 * 0.07 + 0.3
                                let tapA = 0.5 + beat * 2.0
                                at(tapA, {
                                    overlay.present(at: self.addWordPoint() ?? CGPoint(x: 90.0, y: 330.0))
                                })
                                let typeA = tapA + 0.42
                                at(typeA, {
                                    overlay.mark("typing")
                                    NotificationCenter.default.post(name: Notification.Name("ConceptsDemoTypeWord"), object: nil, userInfo: ["word": "airdrop"])
                                })
                                // Без второго тапа: «bitcoin» печатается сразу следом, как через пробел.
                                let typeB = typeA + wordTime + 0.2
                                at(typeB, {
                                    NotificationCenter.default.post(name: Notification.Name("ConceptsDemoTypeWord"), object: nil, userInfo: ["word": "bitcoin", "last": true])
                                })
                                // Скролл — через 0,4 с после того, как «bitcoin» стал чипсом: сразу до конца списка (кнопка «Remove All» внизу),
                                // плавно (1,3 с).
                                let scrollA = typeB + wordTime + 0.4
                                at(scrollA, {
                                    overlay.mark("scrollDown")
                                    var distance: CGFloat = 480.0
                                    if case let .known(value)? = self.editorController()?.visibleBottomContentOffset, value > 0.0 {
                                        distance = value
                                    }
                                    self.editorController()?.conceptsScroll(by: distance, duration: 1.3)
                                })
                                // Тап по шеврону Media — когда скролл остановился.
                                at(scrollA + 1.35, {
                                    self.realTap(overlay, injector, at: self.headerPoint(self.editorRows().media) ?? mediaRow, completion: {
                                        overlay.mark("accordionOpen")
                                    })
                                })
                                // Тап именно в чек GIFs — когда строки Media проявились.
                                at(scrollA + 1.35 + 1.15, {
                                    var checkPoint = CGPoint(x: 42.0, y: (self.textPoint(prefix: "GIFs", exact: true) ?? mediaRow).y)
                                    if let label = self.textView(prefix: "GIFs", exact: true) {
                                        let frame = label.convert(label.bounds, to: nil)
                                        checkPoint = CGPoint(x: frame.minX - 30.0, y: frame.midY)
                                    }
                                    self.realTap(overlay, injector, at: checkPoint, completion: {
                                        overlay.mark("pickGIFs")
                                    })
                                })
                                // Второй скролл до конца списка (Giveaways и Other в кадре, «Remove All» внизу).
                                let scrollB = scrollA + 1.35 + 1.15 + 0.55
                                at(scrollB, {
                                    var distance: CGFloat = 480.0
                                    if case let .known(value)? = self.editorController()?.visibleBottomContentOffset, value > 0.0 {
                                        distance = value
                                    }
                                    overlay.mark("scrollOther")
                                    self.editorController()?.conceptsScroll(by: distance, duration: 1.1)
                                })
                                // Сначала гивы, затем Other (секция подъезжает, кнопка «Remove All» на месте), затем Done.
                                at(scrollB + 1.0, {
                                    overlay.mark("giveTap")
                                    self.realTap(overlay, injector, at: self.togglePoint(self.editorRows().giveaways) ?? giveToggle)
                                })
                                at(scrollB + 1.0 + 0.7, {
                                    self.realTap(overlay, injector, at: self.headerPoint(self.editorRows().other) ?? otherRow, completion: {
                                        self.editorController()?.conceptsPinLastItem(duration: 1.2)
                                    })
                                })
                                at(scrollB + 1.0 + 0.7 + 1.25, {
                                    overlay.mark("ringLight")
                                    self.realTap(overlay, injector, at: close, direct: { self.pressAnimation(at: close, then: { self.editorController()?.dismiss() }) }, completion: {
                                        self.waitUntil(timeout: 2.5, { chatIsTop() }, then: {
                                            overlay.mark("editorDismissed")
                                            after(0.3, {
                                                self.listScene(context: context, overlay: overlay, injector: injector, back: back, row: row, bell: bell)
                                            })
                                        })
                                    })
                                })
                            })
                        })
                    })
                })
            })
        })
    }
    
    // 5. Назад в список чатов: посты приходят тихо; ячейку канала увеличиваем (врезка делается при сборке ролика), затем тап.
    // 6. В чате акцент на кнопке с колокольчиком, два тапа: розыгрыш (по типу), пост со словом.
    private static func listScene(context: AccountContext, overlay: ConceptsDemoTouchOverlay, injector: ConceptsDemoTouchInjector, back: CGPoint, row: CGPoint, bell: CGPoint) {
        let peerId = ConceptsOfflineDemo.cryptoChannelId
        func after(_ time: Double, _ f: @escaping () -> Void) {
            Queue.mainQueue().after(time, f)
        }
        let photo: (String, UIColor, UIColor) = ("📊", UIColor(rgb: 0x0f2027), UIColor(rgb: 0x2c5364))
        self.realTap(overlay, injector, at: back, completion: {
            self.waitUntil({ self.chat() == nil }, then: {
                overlay.mark("listShown")
                let _ = (context.account.postbox.transaction { transaction -> Int32 in
                    return transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id ?? 0
                } |> deliverOnMainQueue).startStandalone(next: { baseId in
                    // Сначала два сообщения проходят в тишине (серый счётчик), затем розыгрыш: пуш, колокольчик и врезка ячейки.
                    // Совпадающие с исключениями посты (розыгрыш, TON, Telegram) приходят ближе к концу, но без долгого ожидания.
                    // Семь постов с шагом 0,45 с: счётчик остаётся однозначным (колокольчик не сдвигается), нужные посты приходят в конце.
                    let posts: [(String, (String, UIColor, UIColor)?, String?, Bool, Double)] = [
                        ("Chart of the week: volumes keep rising 📈", photo, "chartui", false, 0.3),
                        ("Market heatmap: green across the board 🟢", photo, "heatmap", false, 0.6),
                        ("Live from the studio: what moved the market today", photo, "newsroom", false, 0.9),
                        ("🎁 Giveaway: 5 Telegram Premium subscriptions for 6 months. Join before Friday!", nil, nil, true, 1.2),
                        ("Wallet update: faster, cheaper, simpler", photo, "walletui", false, 1.5),
                        ("TON staking rewards double as Telegram opens the wallet airdrop", nil, nil, false, 1.8),
                        ("Mining update: network activity at a yearly high", photo, "coin", false, 2.1),
                        ("Telegram announces a new wallet feature for next week", nil, nil, false, 2.4),
                        ("Wallet review: five features that changed in 2026", photo, "wallet", false, 2.7)
                    ]
                    for post in posts {
                        after(post.4, {
                            ConceptsOfflineDemo.receivePost(context: context, peerId: peerId, text: post.0, photo: post.1, image: post.2, giveaway: post.3)
                        })
                    }
                    // Врезка ячейки стартует с первым изменением в ячейке (приходит первый пост) и заканчивается до перехода.
                    after(0.3, {
                        overlay.mark("calloutList")
                    })
                    // Точная рамка верхней ячейки (после прихода постов) для врезки при сборке ролика: значения в 0,1 pt.
                    after(1.0, {
                        if let frame = self.topChatListCellFrame() {
                            overlay.mark("listCellX\(Int(frame.minX * 10.0))Y\(Int(frame.minY * 10.0))W\(Int(frame.width * 10.0))H\(Int(frame.height * 10.0))")
                        }
                    })
                    // Ячейка возвращается из скейла сразу после анимации колокольчика (первый пост-исключение).
                    after(2.2, {
                        overlay.mark("calloutListEnd")
                    })
                    self.waitForTopMessage(context: context, atLeast: baseId + Int32(posts.count), then: {
                        after(0.0, {
                          after(0.0, {
                            let rowPoint = self.topChatListCellFrame().map { CGPoint(x: $0.midX, y: $0.midY) } ?? row
                            self.realTap(overlay, injector, at: rowPoint, completion: {
                                self.waitUntil({ self.chat() != nil }, then: {
                                    overlay.mark("chatOpened")
                                    self.waitUntil({ (self.chat()?.chatDisplayNode.navigateButtons.conceptsMuteExceptionsCount ?? 0) >= 3 }, then: {
                                        after(0.2, {
                                            self.bellScene(context: context, overlay: overlay, injector: injector, bell: bell)
                                        })
                                    })
                                })
                            })
                          })
                        })
                    })
                })
            })
        })
    }
    
    private static func currentBellPoint(fallback: CGPoint) -> CGPoint {
        if let button = self.chat()?.chatDisplayNode.navigateButtons.conceptsMuteExceptionsButton.view {
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            if center.x > 200.0 && center.y > 200.0 {
                return center
            }
        }
        return fallback
    }
    
    private static func bellScene(context: AccountContext, overlay: ConceptsDemoTouchOverlay, injector: ConceptsDemoTouchInjector, bell: CGPoint) {
        func after(_ time: Double, _ f: @escaping () -> Void) {
            Queue.mainQueue().after(time, f)
        }
        func bellStep(_ name: String, hold: Double, tapped: @escaping () -> Void) {
            let point = self.currentBellPoint(fallback: bell)
            let count = self.chat()?.chatDisplayNode.navigateButtons.conceptsMuteExceptionsCount ?? 0
            overlay.mark("\(name)C\(count)X\(Int(point.x))Y\(Int(point.y))")
            // Первый раз сначала акцент (врезка кнопки с качающимся колокольчиком при сборке), потом нажатие.
            after(hold, {
                self.realTap(overlay, injector, at: self.currentBellPoint(fallback: bell), completion: tapped)
            })
        }
        var unread: [EngineMessage.Index] = []
        let _ = (conceptsMuteExceptionUnreadMessages(context: context, peerId: ConceptsOfflineDemo.cryptoChannelId) |> take(1) |> deliverOnMainQueue).startStandalone(next: { indices in
            unread = indices.sorted()
        })
        // Три звоночка: розыгрыш, пост с TON, пост с Telegram. Врезка с акцентом только у первого; между нажатиями короткие паузы.
        func step(_ index: Int) {
            let countBefore = self.chat()?.chatDisplayNode.navigateButtons.conceptsMuteExceptionsCount ?? 0
            bellStep(index == 0 ? "calloutBellA" : "tapBell\(index)", hold: index == 0 ? 1.25 : 0.05, tapped: {
                if index < 2 {
                    // Пост прочитан после перехода к нему: счётчик уменьшается, следом следующий звоночек.
                    after(0.3, {
                        if index < unread.count {
                            let _ = context.engine.messages.applyMaxReadIndexInteractively(index: unread[index]).startStandalone()
                        }
                    })
                    self.waitUntil(timeout: 4.0, { (self.chat()?.chatDisplayNode.navigateButtons.conceptsMuteExceptionsCount ?? 0) < countBefore }, then: {
                        after(0.85, {
                            step(index + 1)
                        })
                    })
                } else {
                    after(0.25, {
                        if index < unread.count {
                            let _ = context.engine.messages.applyMaxReadIndexInteractively(index: unread[index]).startStandalone()
                        }
                    })
                    after(1.1, {
                        overlay.mark("dragStart")
                        // Петля: всё прочитано заранее (лента не перестраивается во время скролла), затем один плавный скролл,
                        // после которого пост TON стоит внизу экрана, как в первом кадре (переход в первый кадр — при сборке).
                        let _ = (self.startPostIndices(context: context) |> deliverOnMainQueue).startStandalone(next: { indices in
                            if let indices {
                                let _ = context.engine.messages.applyMaxReadIndexInteractively(index: indices.last).startStandalone()
                            }
                        })
                        after(0.45, {
                            // Переход в первый кадр: один плавный скролл вверх изингом пользователя, сразу к стартовому посту (без пустоты).
                            overlay.mark("scrollUpStart")
                            // Кнопка «вниз» уходит родной анимацией вместе с быстрым началом отскролла (в первом кадре её нет).
                            conceptsDemoHideDownButton = true
                            if let buttons = self.chat()?.chatDisplayNode.navigateButtons {
                                let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
                                transition.updateAlpha(node: buttons.downButton, alpha: 0.0)
                                transition.updateTransformScale(node: buttons.downButton, scale: 0.2)
                            }
                            let _ = (self.startPostIndices(context: context) |> deliverOnMainQueue).startStandalone(next: { indices in
                                guard let indices, let chat = self.chat() else {
                                    return
                                }
                                // Плашка «Unread Messages» в первом кадре отсутствует: при отскролле она не показывается вовсе
                                // (гаснет за 0,15 с в начале быстрого движения, новые экземпляры сразу скрыты).
                                // Посты ниже стартового прячутся только целиком за краем окна (по presentation-слоям).
                                // Движение — две фазы как пружина: изинг пользователя с перелётом на 80 pt (низ стартового
                                // поста уходит за край), затем мягкий возврат; возврат стартует до конца хвоста — без паузы.
                                let historyNode = chat.chatDisplayNode.historyNode
                                // Видимый низ ролика: окно урезано (compact), а панель с Unmute закрывает низ —
                                // пост считается ушедшим из вида, когда его верх ниже верха панели.
                                let windowHeight = min(chat.view.window?.bounds.height ?? UIScreen.main.bounds.height, UIScreen.main.bounds.height - conceptsDemoWindowHeightReduction) - 60.0
                                var fadedDividers = false
                                let watchUntil = CFAbsoluteTimeGetCurrent() + 2.0
                                func watch() {
                                    var startMinY: CGFloat?
                                    historyNode.forEachItemNode { node in
                                        if let node = node as? ChatMessageItemView, let item = node.item, item.message.index == indices.start {
                                            startMinY = node.frame.minY
                                        }
                                    }
                                    historyNode.forEachItemNode { node in
                                        if String(describing: type(of: node)).contains("UnreadItemNode") {
                                            if !fadedDividers, node.alpha > 0.0 {
                                                ContainedViewLayoutTransition.animated(duration: 0.15, curve: .easeInOut).updateAlpha(node: node, alpha: 0.0)
                                            } else {
                                                node.alpha = 0.0
                                            }
                                            return
                                        }
                                        var isBelowStart = false
                                        if let node = node as? ChatMessageItemView, let item = node.item {
                                            isBelowStart = item.message.index > indices.start
                                        } else if let startMinY {
                                            isBelowStart = node.frame.maxY <= startMinY + 1.0
                                        }
                                        if isBelowStart && !node.isHidden {
                                            var rect = node.view.convert(node.bounds, to: nil)
                                            if let windowLayer = chat.view.window?.layer.presentation(), let nodeLayer = node.layer.presentation() {
                                                rect = nodeLayer.convert(nodeLayer.bounds, to: windowLayer)
                                            }
                                            if rect.minY >= windowHeight - 0.5 {
                                                node.isHidden = true
                                            }
                                        }
                                    }
                                    fadedDividers = true
                                    if CFAbsoluteTimeGetCurrent() < watchUntil {
                                        Queue.mainQueue().after(0.008, watch)
                                    }
                                }
                                watch()
                                // Одна настоящая пружина: старт с начальной скоростью, перелёт за край и затухающий возврат.
                                historyNode.conceptsAnimatedScroll(toMessageId: indices.start.id, position: conceptsDemoScrollPosition(key: "startScroll", fallback: .bottom(0.0)), duration: 1.4, spring: (mass: 1.0, stiffness: 33.0, damping: 8.6, velocity: 0.0))
                            })
                        })
                        after(1.3, {
                            // Стикер уже в кадре: фаза подгоняется под конец петли.
                            self.syncStickersForLoopEnd()
                            after(0.35, {
                                self.correctStickersForLoopEnd()
                            })
                        })
                        let untilLoopEnd = max(2.6, (0.15 + self.loopDuration + 0.4) - (CFAbsoluteTimeGetCurrent() - self.flashTime))
                        after(untilLoopEnd, {
                            overlay.mark("end")
                            overlay.writeLog()
                            try? "done".write(toFile: "/tmp/concepts-demo-done", atomically: true, encoding: .utf8)
                        })
                    })
                }
            })
        }
        step(0)
    }
}
