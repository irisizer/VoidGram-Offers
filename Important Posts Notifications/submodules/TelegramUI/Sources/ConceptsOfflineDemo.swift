import Foundation
import UIKit
import ImageIO
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import PromptUI
import PeerInfoScreen
import ChatMessageItemView
import ChatMessageItem

// Локальные концепты: данные офлайн-демо (`--concepts-offline-demo`). Все имена, каналы и
// посты вымышленные. Кнопка «Демо» справа добавляет посты в канал так, будто они пришли
// с сервера: пост пишется в Postbox и проходит обычный путь уведомлений внутри приложения.

enum ConceptsOfflineDemo {
    static let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(7770001))
    static let friendPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(7770002))
    static let cryptoChannelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771001))
    static let designChannelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771002))
    static let districtChannelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771003))

    static let friend2PeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(7770004))
    static let friend3PeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(7770005))
    // Разговоры с друзьями — небольшие группы: личные чаты в офлайн-демо не загружаются (вечный индикатор),
    // а группы идут по тому же рабочему пути, что и каналы.
    static let techChannelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771007))
    static let travelChannelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771008))
    static let crewGroupId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771004))
    static let lunchGroupId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771005))
    static let teamGroupId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(7771006))

    /// Папка с картинками демо (`--concepts-demo-assets <папка>`): chart.png, coin.png, airdrop.png, design.png,
    /// bakery.png, latte.png и стикер sticker-clean.png (сгенерированы через Codex). Нет файла — рисуется заглушка.
    private static var assetsPath: String? {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--concepts-demo-assets"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return nil
    }

    private enum Content {
        case image(String)
        case sticker(String, String)
        case voice(Int)
        case file(String, Int64)
        case poll(String, [(String, Int)])
        case link(url: String, site: String, title: String, text: String, image: String)
    }

    private struct Item {
        var minutesAgo: Int32
        var text: String
        var content: Content? = nil
        var incoming: Bool = true
        var author: PeerId? = nil
        var views: Int? = nil
    }

    static func signIn(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount) -> Signal<Void, NoError> {
        let mediaBox = account.postbox.mediaBox
        return conceptsOfflineDemoSignIn(accountManager: accountManager, account: account, accountPeerId: self.accountPeerId, seed: { transaction in
            self.seed(transaction: transaction, mediaBox: mediaBox)
        })
    }

    private static func seed(transaction: Transaction, mediaBox: MediaBox) {
        let statusFileId: Int64 = 5_000_000_001
        if let statusFile = self.makeStatusEmoji(mediaBox: mediaBox, fileId: statusFileId, name: "SparklesEmoji.tgs", alt: "✨") {
            transaction.storeMediaIfNotPresent(media: statusFile)
        }
        let me = self.makeUser(id: self.accountPeerId, firstName: "Alex", lastName: "Demo", phone: "88800001", photo: [], isPremium: true, emojiStatusFileId: statusFileId)
        let anna = self.makeUser(id: self.friendPeerId, firstName: "Anna", lastName: "Carter", phone: nil, photo: self.avatar(mediaBox: mediaBox, name: "av-anna"))
        let mia = self.makeUser(id: self.friend2PeerId, firstName: "Mia", lastName: "Park", phone: nil, photo: self.avatar(mediaBox: mediaBox, name: "av-mia"))
        let daniel = self.makeUser(id: self.friend3PeerId, firstName: "Daniel", lastName: "Reed", phone: nil, photo: self.avatar(mediaBox: mediaBox, name: "av-daniel"))
        let crypto = self.makeChannel(id: self.cryptoChannelId, title: "Crypto Morning", username: "crypto_morning_demo", photo: self.avatar(mediaBox: mediaBox, name: "av-crypto"))
        let design = self.makeChannel(id: self.designChannelId, title: "Design Daily", username: "design_daily_demo", photo: self.avatar(mediaBox: mediaBox, name: "av-design"))
        let district = self.makeChannel(id: self.districtChannelId, title: "Neighborhood News", username: nil, photo: self.avatar(mediaBox: mediaBox, name: "av-district"))
        let tech = self.makeChannel(id: self.techChannelId, title: "Tech Pulse", username: "tech_pulse_demo", photo: self.avatar(mediaBox: mediaBox, name: "av-tech"))
        let travel = self.makeChannel(id: self.travelChannelId, title: "Travel Diary", username: "travel_diary_demo", photo: self.avatar(mediaBox: mediaBox, name: "av-travel"))
        let crew = self.makeGroup(id: self.crewGroupId, title: "Weekend Crew", photo: self.avatar(mediaBox: mediaBox, name: "av-crew"))
        let lunch = self.makeGroup(id: self.lunchGroupId, title: "Team Lunch", photo: self.avatar(mediaBox: mediaBox, name: "av-lunch"))
        let team = self.makeGroup(id: self.teamGroupId, title: "Design Team", photo: self.avatar(mediaBox: mediaBox, name: "av-team"))
        transaction.updatePeersInternal([me, anna, mia, daniel, crypto, design, district, tech, travel, crew, lunch, team], update: { _, updated in updated })

        let now = self.demoNow()
        let a = self.friendPeerId, m = self.friend2PeerId, d = self.friend3PeerId

        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.cryptoChannelId, now: now, unreadCount: 0, items: [
            Item(minutesAgo: 560, text: "", content: .sticker("GramDiamond.tgs", "💎"), views: 18400),
            Item(minutesAgo: 520, text: "Bitcoin steadies above $98,000 as traders wait for the weekly close.", views: 20100),
            Item(minutesAgo: 500, text: "Reminder: our posts are news, not financial advice.", views: 15900),
            Item(minutesAgo: 480, text: "Chart of the week: volumes are rising for the third day in a row.", content: .image("chartui"), views: 16200),
            Item(minutesAgo: 400, text: "", content: .poll("Where will TON trade by the end of the month?", [("Above $7", 1840), ("Around $6", 1230), ("Below $5", 410)]), views: 12800),
            Item(minutesAgo: 300, text: "Our hands-on wallet review is live: https://example.com/wallet-review", content: .link(url: "https://example.com/wallet-review", site: "Wallet Weekly", title: "Five wallet features that changed in 2026", text: "A hands-on look at how wallets got faster, cheaper and simpler this year.", image: "wallet"), views: 15500),
            Item(minutesAgo: 220, text: "", content: .voice(42), views: 9300),
            Item(minutesAgo: 140, text: "Market heatmap: green across the board 🟢 BTC +2.1%, TON +6.4%, ETH +3.0%", content: .image("heatmap"), views: 11800),
            Item(minutesAgo: 120, text: "", content: .sticker("GramDiamond.tgs", "💎"), views: 14100),
            Item(minutesAgo: 12, text: "TON hits a new monthly high 🚀 Trading volume up 40% as Telegram announces a wallet airdrop", views: 20100)
        ])
        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.designChannelId, now: now, unreadCount: 1, items: [
            Item(minutesAgo: 1500, text: "A set of soft gradients for autumn covers.", content: .image("design"), views: 5400),
            Item(minutesAgo: 700, text: "", content: .sticker("SparklesEmoji.tgs", "✨"), views: 4700),
            Item(minutesAgo: 360, text: "Spacing systems that scale: https://example.com/spacing", content: .link(url: "https://example.com/spacing", site: "Type & Grid", title: "Spacing systems that scale", text: "Why spacing matters more than color: a short thread on rhythm in interfaces.", image: "desk"), views: 4300),
            Item(minutesAgo: 180, text: "Quick tip: use a 4-point grid and your layouts will always align.", views: 4100)
        ])
        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.districtChannelId, now: now, unreadCount: 2, items: [
            Item(minutesAgo: 2900, text: "Saturday at Maple Yard: the weekend farmers market is back.", views: 2300),
            Item(minutesAgo: 320, text: "Tomorrow from 10:00 to 14:00 the hot water will be off in buildings 3-7.", views: 3100),
            Item(minutesAgo: 60, text: "A new bakery opened by the metro station. Free coffee for the first three days.", content: .image("bakery"), views: 2800)
        ])
        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.techChannelId, now: now, unreadCount: 2, items: [
            Item(minutesAgo: 1100, text: "First look: the thinnest smartwatch yet. https://example.com/watch", content: .link(url: "https://example.com/watch", site: "Tech Pulse", title: "The thinnest smartwatch yet", text: "We spent a week with it. Battery, display and the one feature we did not expect.", image: "watch"), views: 7600),
            Item(minutesAgo: 600, text: "", content: .poll("Which OS do you use on your phone?", [("iOS", 5400), ("Android", 3900), ("Other", 300)]), views: 6900),
            Item(minutesAgo: 200, text: "Weekly roundup: five launches you might have missed.", views: 5200),
            Item(minutesAgo: 30, text: "Hands-on: a new wallet app, faster than ever.", content: .image("wallet"), views: 3100)
        ])
        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.travelChannelId, now: now, unreadCount: 0, items: [
            Item(minutesAgo: 3000, text: "Golden hour in the old harbor.", content: .image("harbor"), views: 1800),
            Item(minutesAgo: 1900, text: "Sunrise at the lake. Worth the 5 a.m. alarm.", content: .image("mountain"), views: 2100),
            Item(minutesAgo: 600, text: "", content: .voice(28), views: 1500)
        ])
        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.crewGroupId, now: now, unreadCount: 1, items: [
            Item(minutesAgo: 70, text: "Found a cozy place near the office", content: .image("latte"), author: a),
            Item(minutesAgo: 60, text: "Nice! Is it quiet enough to work?", author: d),
            Item(minutesAgo: 50, text: "Looks great! Coffee at 7?", incoming: false),
            Item(minutesAgo: 40, text: "", content: .voice(11), author: m),
            Item(minutesAgo: 25, text: "", content: .sticker("Celebrate.tgs", "🎉"), author: a)
        ])
        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.lunchGroupId, now: now, unreadCount: 1, items: [
            Item(minutesAgo: 200, text: "Where should we go for lunch tomorrow?", author: d),
            Item(minutesAgo: 190, text: "", content: .poll("Lunch spot", [("Luigi's", 4), ("Sushi Bar", 2), ("Taco Place", 1)]), author: d),
            Item(minutesAgo: 150, text: "Sure, 1pm works", incoming: false),
            Item(minutesAgo: 140, text: "Perfect, see you at Luigi's", content: .image("pasta"), author: d)
        ])
        self.addConversation(transaction: transaction, mediaBox: mediaBox, peerId: self.teamGroupId, now: now, unreadCount: 0, items: [
            Item(minutesAgo: 400, text: "New studio setup", content: .image("desk"), author: m),
            Item(minutesAgo: 300, text: "Sent you the design files, check your email", content: .file("Brand-guidelines-v3.pdf", 2_400_000), author: m),
            Item(minutesAgo: 200, text: "Thanks! Reviewing now", incoming: false),
            Item(minutesAgo: 120, text: "", content: .voice(19), author: m)
        ])

        transaction.updateCurrentPeerNotificationSettings([
            self.cryptoChannelId: TelegramPeerNotificationSettings.defaultSettings.withUpdatedMuteState(.muted(until: Int32.max)),
            self.districtChannelId: TelegramPeerNotificationSettings.defaultSettings.withUpdatedMuteState(.muted(until: Int32.max))
        ])
    }

    private static func addConversation(transaction: Transaction, mediaBox: MediaBox, peerId: PeerId, now: Int32, unreadCount: Int32, items: [Item]) {
        var messages: [StoreMessage] = []
        for (index, item) in items.enumerated() {
            let id = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: Int32(index + 1))
            let media = self.makeContent(mediaBox: mediaBox, content: item.content)
            messages.append(self.makeMessage(id: id, timestamp: now - item.minutesAgo * 60, text: item.text, media: media, incoming: item.incoming, author: item.author, views: item.views))
        }
        let _ = transaction.addMessages(messages, location: .UpperHistoryBlock)
        self.finishHistory(transaction: transaction, peerId: peerId, maxId: Int32(items.count), unreadCount: unreadCount)
    }

    private static func finishHistory(transaction: Transaction, peerId: PeerId, maxId: Int32, unreadCount: Int32) {
        transaction.removeHole(peerId: peerId, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
        transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: maxId - unreadCount, maxOutgoingReadId: maxId, maxKnownId: maxId, count: unreadCount, markedUnread: false)]])
        transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
    }

    /// Demo clock: "now" is today at 9:41 (same as the status bar) plus time since launch,
    /// so recordings look the same at any time of day and never cross midnight.
    private static let demoLaunch = Date()
    private static let demoAnchor: Int32 = {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 41
        return Int32((Calendar.current.date(from: components) ?? Date()).timeIntervalSince1970)
    }()
    static func demoNow() -> Int32 {
        return self.demoAnchor + Int32(Date().timeIntervalSince(self.demoLaunch))
    }
    
    private static func makeMessage(id: MessageId, timestamp: Int32, text: String, media: [Media], incoming: Bool, author: PeerId?, views: Int?) -> StoreMessage {
        var attributes: [MessageAttribute] = []
        if let views {
            attributes.append(ViewCountMessageAttribute(count: views))
        }
        var entities: [MessageTextEntity] = []
        if let range = text.range(of: "https://") {
            let utf16Start = range.lowerBound.utf16Offset(in: text)
            entities.append(MessageTextEntity(range: utf16Start ..< text.utf16.count, type: .Url))
            attributes.append(TextEntitiesMessageAttribute(entities: entities))
        }
        let (tags, globalTags) = tagsForStoreMessage(incoming: incoming, attributes: attributes, media: media, textEntities: entities, isPinned: false)
        return StoreMessage(id: id, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: timestamp, flags: incoming ? [.Incoming] : [], tags: tags, globalTags: globalTags, localTags: [], forwardInfo: nil, authorId: incoming ? (author ?? id.peerId) : self.accountPeerId, text: text, attributes: attributes, media: media)
    }

    private static func makePost(id: MessageId, timestamp: Int32, text: String, media: [Media], views: Int) -> StoreMessage {
        return self.makeMessage(id: id, timestamp: timestamp, text: text, media: media, incoming: true, author: nil, views: views)
    }

    private static func makeContent(mediaBox: MediaBox, content: Content?) -> [Media] {
        guard let content else {
            return []
        }
        switch content {
        case let .image(name):
            return self.makeMedia(mediaBox: mediaBox, image: name, photo: ("🖼", UIColor(rgb: 0x2c5364), UIColor(rgb: 0x0f2027)))
        case let .sticker(file, emoji):
            return self.makeSticker(mediaBox: mediaBox, file: file, emoji: emoji).flatMap { [$0] } ?? []
        case let .voice(seconds):
            return [self.makeVoice(mediaBox: mediaBox, seconds: seconds)]
        case let .file(name, size):
            return [self.makeDocument(mediaBox: mediaBox, name: name, size: size)]
        case let .poll(question, options):
            return [self.makePoll(question: question, options: options)]
        case let .link(url, site, title, text, image):
            var preview: TelegramMediaImage?
            if let result = self.makeImage(mediaBox: mediaBox, name: image) {
                preview = result
            }
            let webpage = TelegramMediaWebpage(webpageId: MediaId(namespace: Namespaces.Media.CloudWebpage, id: Int64.random(in: 1 ... Int64.max)), content: .Loaded(TelegramMediaWebpageLoadedContent(url: url, displayUrl: url.replacingOccurrences(of: "https://", with: ""), hash: 0, type: "article", websiteName: site, title: title, text: text, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: true, imageIsVideoCover: false, image: preview, file: nil, story: nil, attributes: [], instantPage: nil)))
            return [webpage]
        }
    }

    private static func makeVoice(mediaBox: MediaBox, seconds: Int) -> TelegramMediaFile {
        let resource = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max))
        mediaBox.storeResourceData(resource.id, data: Data(count: 2048))
        var waveform = Data()
        for _ in 0 ..< 40 {
            waveform.append(UInt8.random(in: 20 ... 235))
        }
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: 1 ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "audio/ogg", size: 2048, attributes: [.Audio(isVoice: true, duration: seconds, title: nil, performer: nil, waveform: waveform)], alternativeRepresentations: [])
    }

    private static func makeDocument(mediaBox: MediaBox, name: String, size: Int64) -> TelegramMediaFile {
        let resource = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max), size: size)
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: 1 ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/pdf", size: size, attributes: [.FileName(fileName: name)], alternativeRepresentations: [])
    }

    private static func makePoll(question: String, options: [(String, Int)]) -> TelegramMediaPoll {
        let pollOptions = options.enumerated().map { index, option in
            return TelegramMediaPollOption(text: option.0, entities: [], opaqueIdentifier: Data([UInt8(index)]), media: nil, date: nil, addedBy: nil)
        }
        let voters = options.enumerated().map { index, option in
            return TelegramMediaPollOptionVoters(selected: false, opaqueIdentifier: Data([UInt8(index)]), count: Int32(option.1), isCorrect: false)
        }
        let total = Int32(options.reduce(0) { $0 + $1.1 })
        return TelegramMediaPoll(pollId: MediaId(namespace: Namespaces.Media.CloudPoll, id: Int64.random(in: 1 ... Int64.max)), publicity: .anonymous, kind: .poll(multipleAnswers: false), text: question, textEntities: [], options: pollOptions, correctAnswers: nil, results: TelegramMediaPollResults(voters: voters, totalVoters: total, recentVoters: [], solution: nil, hasUnseenVotes: nil, canViewStats: false), isClosed: false, deadlineTimeout: nil, deadlineDate: nil, pollHash: 0)
    }

    /// Сначала картинка из папки демо, иначе — градиент с эмодзи.
    private static func makeMedia(mediaBox: MediaBox, image: String?, photo: (String, UIColor, UIColor)?) -> [Media] {
        if let image, let result = self.makeImage(mediaBox: mediaBox, name: image) {
            return [result]
        }
        if let photo, let result = self.makePhoto(mediaBox: mediaBox, emoji: photo.0, top: photo.1, bottom: photo.2) {
            return [result]
        }
        return []
    }

    private static func storeImage(mediaBox: MediaBox, data: Data, size: CGSize) -> TelegramMediaImage {
        let resource = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max))
        mediaBox.storeResourceData(resource.id, data: data)
        let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: Int32(size.width), height: Int32(size.height)), resource: resource, progressiveSizes: [], immediateThumbnailData: nil)
        return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: 1 ... Int64.max)), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    }

    /// Картинка из папки демо. Читается и сжимается через ImageIO: рисование через UIKit из потока Postbox
    /// зависает, а ImageIO не зависит от главного потока.
    private static func jpegData(name: String, maxPixelSize: Int) -> (Data, CGSize)? {
        guard let path = self.assetsPath, let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path + "/" + name + ".png") as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return (data as Data, CGSize(width: cgImage.width, height: cgImage.height))
    }

    private static func makeImage(mediaBox: MediaBox, name: String) -> TelegramMediaImage? {
        guard let (data, size) = self.jpegData(name: name, maxPixelSize: 1280) else {
            return nil
        }
        return self.storeImage(mediaBox: mediaBox, data: data, size: size)
    }

    /// Аватарка чата или человека из папки демо (`av-*.png`); нет файла — остаётся цветная заглушка с буквой.
    private static func avatar(mediaBox: MediaBox, name: String) -> [TelegramMediaImageRepresentation] {
        guard let (data, size) = self.jpegData(name: name, maxPixelSize: 512) else {
            return []
        }
        let resource = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max))
        mediaBox.storeResourceData(resource.id, data: data)
        return [TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: Int32(size.width), height: Int32(size.height)), resource: resource, progressiveSizes: [], immediateThumbnailData: nil)]
    }

    /// Анимированный стикер `.tgs` из папки демо (формат Lottie, как у настоящих стикеров Telegram).
    private static func makeSticker(mediaBox: MediaBox, file name: String, emoji: String) -> TelegramMediaFile? {
        guard let path = self.assetsPath, let data = FileManager.default.contents(atPath: path + "/" + name) else {
            return nil
        }
        let resource = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max))
        mediaBox.storeResourceData(resource.id, data: data)
        let attributes: [TelegramMediaFileAttribute] = [.FileName(fileName: name), .ImageSize(size: PixelDimensions(width: 512, height: 512)), .Sticker(displayText: emoji, packReference: nil, maskData: nil), .Animated]
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: 1 ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/x-tgsticker", size: Int64(data.count), attributes: attributes, alternativeRepresentations: [])
    }

    private static func makePhoto(mediaBox: MediaBox, emoji: String, top: UIColor, bottom: UIColor) -> TelegramMediaImage? {
        let size = CGSize(width: 1080.0, height: 720.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: 300.0)])
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2.0, y: (size.height - textSize.height) / 2.0))
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            return nil
        }
        return self.storeImage(mediaBox: mediaBox, data: data, size: size)
    }

    private static func makeStatusEmoji(mediaBox: MediaBox, fileId: Int64, name: String, alt: String) -> TelegramMediaFile? {
        guard let path = self.assetsPath, let data = FileManager.default.contents(atPath: path + "/" + name) else {
            return nil
        }
        let resource = LocalFileMediaResource(fileId: Int64.random(in: 1 ... Int64.max))
        mediaBox.storeResourceData(resource.id, data: data)
        let attributes: [TelegramMediaFileAttribute] = [.FileName(fileName: name), .ImageSize(size: PixelDimensions(width: 100, height: 100)), .CustomEmoji(isPremium: true, isSingleColor: false, alt: alt, packReference: nil), .Animated]
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.CloudFile, id: fileId), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/x-tgsticker", size: Int64(data.count), attributes: attributes, alternativeRepresentations: [])
    }

    private static func makeUser(id: PeerId, firstName: String, lastName: String?, phone: String?, photo: [TelegramMediaImageRepresentation], isPremium: Bool = false, emojiStatusFileId: Int64? = nil) -> TelegramUser {
        return TelegramUser(id: id, accessHash: nil, firstName: firstName, lastName: lastName, username: nil, phone: phone, photo: photo, botInfo: nil, restrictionInfo: nil, flags: isPremium ? [.isPremium] : [], emojiStatus: emojiStatusFileId.flatMap { PeerEmojiStatus(content: .emoji(fileId: $0), expirationDate: nil) }, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private static func makeGroup(id: PeerId, title: String, photo: [TelegramMediaImageRepresentation]) -> TelegramChannel {
        return TelegramChannel(id: id, accessHash: .personal(0), title: title, username: nil, photo: photo, creationDate: 0, version: 0, participationStatus: .member, info: .group(TelegramChannelGroupInfo(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: .blue, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private static func makeChannel(id: PeerId, title: String, username: String?, photo: [TelegramMediaImageRepresentation]) -> TelegramChannel {
        return TelegramChannel(id: id, accessHash: .personal(0), title: title, username: username, photo: photo, creationDate: 0, version: 0, participationStatus: .member, info: .broadcast(TelegramChannelBroadcastInfo(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: .blue, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    // MARK: - Входящие посты

    static func receivePost(context: AccountContext, peerId: PeerId, text: String, photo: (String, UIColor, UIColor)?, image: String? = nil, giveaway: Bool = false, sticker: String? = nil) {
        let account = context.account
        let _ = (account.postbox.transaction { transaction -> MessageId in
            // Номер поста — первый свободный: Postbox молча пропускает сообщение с занятым id.
            var nextId = max(transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id ?? 0, transaction.getTopPeerMessageIndex(peerId: peerId)?.id.id ?? 0) + 1
            while transaction.getMessage(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: nextId)) != nil {
                nextId += 1
            }
            let id = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: nextId)
            var media = self.makeMedia(mediaBox: account.postbox.mediaBox, image: image, photo: photo)
            if giveaway {
                media = [TelegramMediaGiveaway(flags: [.showWinners], channelPeerIds: [peerId], countries: [], quantity: 5, prize: .premium(months: 6), untilDate: Int32(Date().timeIntervalSince1970) + 3 * 86400, prizeDescription: nil)]
            }
            if let sticker, let file = self.makeSticker(mediaBox: account.postbox.mediaBox, file: sticker, emoji: "💎") {
                media = [file]
            }
            let _ = transaction.addMessages([self.makePost(id: id, timestamp: self.demoNow(), text: text, media: media, views: 1)], location: .UpperHistoryBlock)
            let stored = transaction.getMessage(id) != nil
            Logger.shared.log("ConceptsOfflineDemo", "receivePost id \(nextId) stored \(stored)")
            return id
        }
        |> deliverOnMainQueue).startStandalone(next: { id in
            account.stateManager.conceptsDeliverIncomingMessages(ids: [id])
        })
    }

    // MARK: - Сценарий запуска

    /// Флаги для проверки без касаний: `--concepts-demo-posts N` присылает в «Крипто-утро» N постов
    /// со словом «тон», `--concepts-demo-photos N` — N постов с фото, `--concepts-demo-open-channel`
    /// затем открывает канал. `--concepts-demo-keywords "a,b"` добавляет слова в исключения канала,
    /// `--concepts-demo-open-exceptions` открывает экран исключений, `--concepts-demo-expand-media`
    /// раскрывает на нём группу «Media», `--concepts-demo-reset-exceptions` очищает исключения,
    /// `--concepts-demo-types "photo,poll"` задаёт типы постов, `--concepts-demo-post-text "…"` присылает
    /// пост с этим текстом, `--concepts-demo-open-quickadd` открывает редактор исключений с подсказками из
    /// последнего поста (тот же редактор, что из меню поста), `--concepts-demo-open-postmenu` открывает меню
    /// поста в канале (предпочитает пост со словом TON).
    static func runLaunchScript(context: AccountContext) {
        let arguments = ProcessInfo.processInfo.arguments
        var postCount = 0
        if let index = arguments.firstIndex(of: "--concepts-demo-posts"), index + 1 < arguments.count {
            postCount = Int(arguments[index + 1]) ?? 0
        }
        var photoCount = 0
        if let index = arguments.firstIndex(of: "--concepts-demo-photos"), index + 1 < arguments.count {
            photoCount = Int(arguments[index + 1]) ?? 0
        }
        // `--concepts-demo-open-chat anna|daniel|mia|design|district` открывает один из остальных чатов.
        var openChatId: PeerId?
        if let index = arguments.firstIndex(of: "--concepts-demo-open-chat"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "tech": openChatId = self.techChannelId
            case "travel": openChatId = self.travelChannelId
            case "anna", "crew": openChatId = self.crewGroupId
            case "daniel", "lunch": openChatId = self.lunchGroupId
            case "mia", "team": openChatId = self.teamGroupId
            case "design": openChatId = self.designChannelId
            case "district": openChatId = self.districtChannelId
            default: break
            }
        }
        let openChannel = arguments.contains("--concepts-demo-open-channel")
        let openExceptions = arguments.contains("--concepts-demo-open-exceptions")
        var keywords: [String] = []
        if let index = arguments.firstIndex(of: "--concepts-demo-keywords"), index + 1 < arguments.count {
            keywords = arguments[index + 1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let openQuickAdd = arguments.contains("--concepts-demo-open-quickadd")
        let openPostMenu = arguments.contains("--concepts-demo-open-postmenu")
        var postText: String?
        if let index = arguments.firstIndex(of: "--concepts-demo-post-text"), index + 1 < arguments.count {
            postText = arguments[index + 1]
        }
        let resetExceptions = arguments.contains("--concepts-demo-reset-exceptions")
        var types: Set<ConceptsMuteExceptionContent>?
        if let index = arguments.firstIndex(of: "--concepts-demo-types"), index + 1 < arguments.count {
            types = Set(arguments[index + 1].components(separatedBy: ",").compactMap { ConceptsMuteExceptionContent(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
        }
        if postCount == 0 && photoCount == 0 && !openChannel && openChatId == nil && !openExceptions && keywords.isEmpty && !resetExceptions && types == nil && !openQuickAdd && !openPostMenu && postText == nil {
            return
        }
        if let postText {
            Queue.mainQueue().after(8.0, {
                self.receivePost(context: context, peerId: self.cryptoChannelId, text: postText, photo: nil)
            })
        }
        if openQuickAdd {
            Queue.mainQueue().after(11.0, {
                let _ = (context.account.postbox.transaction { transaction -> EngineRawMessage? in
                    guard let id = transaction.getTopPeerMessageId(peerId: self.cryptoChannelId, namespace: Namespaces.Message.Cloud) else {
                        return nil
                    }
                    return transaction.getMessage(id)
                }
                |> deliverOnMainQueue).startStandalone(next: { message in
                    guard let message, let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
                        return
                    }
                    conceptsPresentMuteExceptionEditor(context: context, message: message, navigationController: navigationController)
                })
            })
        }
        if openPostMenu {
            Queue.mainQueue().after(20.0, {
                guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController, let chat = navigationController.topViewController as? ChatControllerImpl else {
                    return
                }
                var target: (EngineRawMessage, ChatMessageItemView)?
                chat.chatDisplayNode.historyNode.forEachVisibleItemNode { node in
                    if let view = node as? ChatMessageItemView, let item = view.item {
                        let message = item.content.firstMessage
                        if !message.text.isEmpty && (target == nil || message.text.contains("TON")) {
                            target = (message, view)
                        }
                    }
                }
                if let (message, view) = target {
                    chat.openMessageContextMenu(message: EngineMessage(message), selectAll: false, node: view, frame: view.bounds, anyRecognizer: nil, location: nil)
                }
            })
        }
        if resetExceptions || !keywords.isEmpty || types != nil {
            let _ = updateConceptsMuteException(postbox: context.account.postbox, peerId: self.cryptoChannelId, { exception in
                var exception = resetExceptions ? ConceptsMuteException() : exception
                if let types {
                    exception.contentTypes = types
                }
                for keyword in keywords where !exception.keywords.contains(where: { $0.lowercased() == keyword.lowercased() }) {
                    exception.keywords.append(keyword)
                }
                return exception
            }).startStandalone()
        }
        if openExceptions {
            Queue.mainQueue().after(4.0, {
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.cryptoChannelId))
                |> deliverOnMainQueue).startStandalone(next: { peer in
                    guard let peer, let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
                        return
                    }
                    navigationController.pushViewController(peerInfoMuteExceptionsScreen(context: context, peer: peer))
                })
            })
        }
        let texts = [
            "Daily market wrap: a quiet session, no major moves",
            "New podcast episode is out: how wallets are changing",
            "Weekly digest: five things worth knowing"
        ]
        let startDelay = 4.0
        for i in 0 ..< postCount {
            Queue.mainQueue().after(startDelay + Double(i) * 0.8, {
                self.receivePost(context: context, peerId: self.cryptoChannelId, text: texts[i % texts.count], photo: nil)
            })
        }
        let photoImages = ["chart", "airdrop", "coin"]
        let photoCaptions = ["Chart of the week: volumes keep rising", "Airdrop season: what to watch this month", "Wallet update: faster, cheaper, simpler"]
        for i in 0 ..< photoCount {
            Queue.mainQueue().after(startDelay + Double(postCount + i) * 0.8, {
                self.receivePost(context: context, peerId: self.cryptoChannelId, text: photoCaptions[i % photoCaptions.count], photo: ("📊", UIColor(rgb: 0x0f2027), UIColor(rgb: 0x2c5364)), image: photoImages[i % photoImages.count])
            })
        }
        if let openChatId {
            Queue.mainQueue().after(startDelay + 6.0, {
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: openChatId))
                |> deliverOnMainQueue).startStandalone(next: { peer in
                    guard let peer, let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
                        return
                    }
                    context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
                })
            })
        }
        if openChannel {
            Queue.mainQueue().after(startDelay + Double(postCount + photoCount) * 0.8 + 8.0, {
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.cryptoChannelId))
                |> deliverOnMainQueue).startStandalone(next: { peer in
                    guard let peer, let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
                        return
                    }
                    context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
                })
            })
        }
    }
}

/// Кнопка «Демо» живёт в своём маленьком окне: окно Telegram само раздаёт касания и не видит
/// посторонние вьюхи. Меню и ввод текста — родные контроллеры Telegram.
final class ConceptsOfflineDemoPanel {
    private final class ButtonWindow: UIWindow {
    }
    
    private let context: AccountContext
    private let window: ButtonWindow
    private let button = UIButton(type: .system)
    
    init(context: AccountContext, window mainWindow: UIWindow) {
        self.context = context
        
        let size = CGSize(width: 54.0, height: 30.0)
        let frame = CGRect(origin: CGPoint(x: 8.0, y: floor(mainWindow.bounds.height * 0.78)), size: size)
        if let scene = mainWindow.windowScene {
            self.window = ButtonWindow(windowScene: scene)
        } else {
            self.window = ButtonWindow(frame: frame)
        }
        self.window.frame = frame
        self.window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1.0)
        self.window.backgroundColor = .clear
        self.window.rootViewController = UIViewController()
        self.window.rootViewController?.view.backgroundColor = .clear
        
        self.button.setTitle("Демо", for: .normal)
        self.button.titleLabel?.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.button.setTitleColor(.white, for: .normal)
        self.button.backgroundColor = UIColor(rgb: 0xff9500).withAlphaComponent(0.9)
        self.button.layer.cornerRadius = 15.0
        self.button.frame = CGRect(origin: .zero, size: size)
        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
        // Кнопку можно перетащить, если она закрывает нужный элемент.
        self.button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.buttonPanned(_:))))
        self.window.rootViewController?.view.addSubview(self.button)
        // `--concepts-demo-hide-panel` прячет кнопку «Демо» (для записи ролика); сценарий запуска работает и без неё.
        self.window.isHidden = CommandLine.arguments.contains("--concepts-demo-hide-panel")

        if CommandLine.arguments.contains("--concepts-demo-touch-test") {
            ConceptsDemoAutopilot.touchTest(context: context)
        }
        if CommandLine.arguments.contains("--concepts-demo-autopilot") {
            ConceptsDemoAutopilot.run(context: context, window: mainWindow)
        } else {
            ConceptsOfflineDemo.runLaunchScript(context: context)
        }
    }
    
    @objc private func buttonPanned(_ recognizer: UIPanGestureRecognizer) {
        guard let screen = self.window.windowScene?.screen.bounds else {
            return
        }
        let translation = recognizer.translation(in: nil)
        recognizer.setTranslation(.zero, in: nil)
        var frame = self.window.frame
        frame.origin.x = max(0.0, min(screen.width - frame.width, frame.origin.x + translation.x))
        frame.origin.y = max(60.0, min(screen.height - frame.height - 20.0, frame.origin.y + translation.y))
        self.window.frame = frame
    }
    
    @objc private func buttonPressed() {
        let context = self.context
        let peerId = ConceptsOfflineDemo.cryptoChannelId
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let posts: [(String, String, (String, UIColor, UIColor)?)] = [
            ("Text with “TON”", "TON hits a new monthly high 🚀 Trading volume up 40%", nil),
            ("Plain text", "A quiet session today, nothing to report.", nil),
            ("Photo", "Chart of the week: volumes keep rising", ("📊", UIColor(rgb: 0x0f2027), UIColor(rgb: 0x2c5364))),
            ("Link", "Weekly review: https://example.com/weekly", nil)
        ]
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [
            ActionSheetTextItem(title: "New post in “Crypto Morning”. The channel is muted: a notification arrives only if the post matches the exceptions.")
        ]
        for (title, text, photo) in posts {
            items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                ConceptsOfflineDemo.receivePost(context: context, peerId: peerId, text: text, photo: photo)
            }))
        }
        items.append(ActionSheetButtonItem(title: "Custom text…", color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            let prompt = promptController(context: context, text: "Post text", value: "", placeholder: "For example: TON is rising", apply: { value in
                if let value, !value.isEmpty {
                    ConceptsOfflineDemo.receivePost(context: context, peerId: peerId, text: value, photo: nil)
                }
            })
            context.sharedContext.mainWindow?.present(prompt, on: .root)
        }))
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        context.sharedContext.mainWindow?.present(actionSheet, on: .root)
    }
}
