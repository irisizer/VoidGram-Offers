import Foundation
import Postbox
import SwiftSignalKit

// Локальные концепты: исключения для канала без звука. Канал замьючен, но о выбранных типах
// постов и о постах с ключевыми словами всё равно приходит уведомление. Настройки хранятся
// только на устройстве; на сервере такой фильтрации нет.

public enum ConceptsMuteExceptionContent: String, Codable, CaseIterable {
    case text
    case photo
    case video
    case sticker
    case gif
    case audio
    case voice
    case roundVideo
    case file
    case link
    case poll
    case giveaway
    case location
    case contact
    case story
    case paid
}

public struct ConceptsMuteException: Codable, Equatable {
    public var contentTypes: Set<ConceptsMuteExceptionContent>
    public var keywords: [String]

    public init(contentTypes: Set<ConceptsMuteExceptionContent> = Set(), keywords: [String] = []) {
        self.contentTypes = contentTypes
        self.keywords = keywords
    }

    public var isEmpty: Bool {
        return self.contentTypes.isEmpty && self.keywords.isEmpty
    }
}

public struct ConceptsMuteExceptionsSettings: Codable, Equatable {
    public var peers: [Int64: ConceptsMuteException]

    public init(peers: [Int64: ConceptsMuteException] = [:]) {
        self.peers = peers
    }
}

private let conceptsMuteExceptionsKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 10001)
    return key
}()

// Настройки лежат в PreferencesEntry сырым JSON, без Postbox-кодировщика.
private func decodeConceptsMuteExceptions(_ entry: PreferencesEntry?) -> ConceptsMuteExceptionsSettings {
    guard let data = entry?.data, let settings = try? JSONDecoder().decode(ConceptsMuteExceptionsSettings.self, from: data) else {
        return ConceptsMuteExceptionsSettings()
    }
    return settings
}

public func conceptsMuteException(postbox: Postbox, peerId: PeerId) -> Signal<ConceptsMuteException, NoError> {
    return postbox.preferencesView(keys: [conceptsMuteExceptionsKey])
    |> map { view -> ConceptsMuteException in
        let settings = decodeConceptsMuteExceptions(view.values[conceptsMuteExceptionsKey])
        return settings.peers[peerId.toInt64()] ?? ConceptsMuteException()
    }
    |> distinctUntilChanged
}

public func conceptsMuteException(transaction: Transaction, peerId: PeerId) -> ConceptsMuteException {
    return decodeConceptsMuteExceptions(transaction.getPreferencesEntry(key: conceptsMuteExceptionsKey)).peers[peerId.toInt64()] ?? ConceptsMuteException()
}

public func updateConceptsMuteException(postbox: Postbox, peerId: PeerId, _ f: @escaping (ConceptsMuteException) -> ConceptsMuteException) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        transaction.updatePreferencesEntry(key: conceptsMuteExceptionsKey, { entry in
            var settings = decodeConceptsMuteExceptions(entry)
            let updated = f(settings.peers[peerId.toInt64()] ?? ConceptsMuteException())
            if updated.isEmpty {
                settings.peers.removeValue(forKey: peerId.toInt64())
            } else {
                settings.peers[peerId.toInt64()] = updated
            }
            guard let json = try? JSONEncoder().encode(settings) else {
                return entry
            }
            return PreferencesEntry(data: json)
        })
    }
}

/// Пост может относиться к нескольким типам сразу: текст со ссылкой — это и «текст», и «ссылка»,
/// фото с подписью-ссылкой — «фото» и «ссылка». «Текст» — пост без медиа (превью ссылки не считается).
/// Служебные сообщения (смена фото канала, закрепление) ни к одному типу не относятся.
public func conceptsMuteExceptionContents(message: Message) -> Set<ConceptsMuteExceptionContent> {
    var result = Set<ConceptsMuteExceptionContent>()
    var hasContentMedia = false
    for media in message.media {
        if media is TelegramMediaAction {
            return Set()
        } else if media is TelegramMediaImage {
            result.insert(.photo)
            hasContentMedia = true
        } else if let file = media as? TelegramMediaFile {
            hasContentMedia = true
            if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                result.insert(.sticker)
            } else if file.isInstantVideo {
                result.insert(.roundVideo)
            } else if file.isAnimated {
                result.insert(.gif)
            } else if file.isVideo {
                result.insert(.video)
            } else if file.isVoice {
                result.insert(.voice)
            } else if file.isMusic {
                result.insert(.audio)
            } else {
                result.insert(.file)
            }
        } else if media is TelegramMediaPoll {
            result.insert(.poll)
            hasContentMedia = true
        } else if media is TelegramMediaGiveaway || media is TelegramMediaGiveawayResults {
            result.insert(.giveaway)
            hasContentMedia = true
        } else if media is TelegramMediaWebpage {
            result.insert(.link)
        } else {
            hasContentMedia = true
            if media is TelegramMediaMap {
                result.insert(.location)
            } else if media is TelegramMediaContact {
                result.insert(.contact)
            } else if media is TelegramMediaStory {
                result.insert(.story)
            } else if media is TelegramMediaPaidContent {
                result.insert(.paid)
            }
            // Кубики, игры, счета, чек-листы, трансляции и прочее — не текст и не отдельный тип:
            // такие посты подходят только под ключевые слова.
        }
    }
    for attribute in message.attributes {
        if let attribute = attribute as? TextEntitiesMessageAttribute, attribute.entities.contains(where: { entity in
            switch entity.type {
            case .Url, .TextUrl:
                return true
            default:
                return false
            }
        }) {
            result.insert(.link)
            break
        }
    }
    if !hasContentMedia {
        result.insert(.text)
    }
    return result
}

/// Слова сравниваются целиком и без учёта регистра: «тон» совпадает с «Тон,», но не с «тонна».
public func conceptsMuteExceptionKeywordMatch(text: String, keywords: [String]) -> String? {
    let normalize: (String) -> String = { value in
        let words = value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return " " + words.joined(separator: " ") + " "
    }
    let normalizedText = normalize(text)
    for keyword in keywords {
        let normalizedKeyword = normalize(keyword)
        if normalizedKeyword.count > 2 && normalizedText.contains(normalizedKeyword) {
            return keyword
        }
    }
    return nil
}

/// Ключевые слова действуют для любого поста (текст или подпись к медиа), независимо от типов.
/// Включённый тип пропускает все посты этого типа; `.text` — все текстовые посты без медиа.
public func conceptsMuteExceptionMatches(exception: ConceptsMuteException, message: Message) -> Bool {
    if conceptsMuteExceptionKeywordMatch(text: message.text, keywords: exception.keywords) != nil {
        return true
    }
    return !exception.contentTypes.isDisjoint(with: conceptsMuteExceptionContents(message: message))
}

func conceptsMuteExceptionMatches(transaction: Transaction, message: Message) -> Bool {
    guard let exception = decodeConceptsMuteExceptions(transaction.getPreferencesEntry(key: conceptsMuteExceptionsKey)).peers[message.id.peerId.toInt64()] else {
        return false
    }
    return conceptsMuteExceptionMatches(exception: exception, message: message)
}

// Посты, которые прошли через исключение, помечаются как «непросмотренные» — по аналогии
// с упоминаниями и реакциями. Непросмотренным считается такой пост, пока канал не прочитан
// дальше него, поэтому отдельная отметка «просмотрено» не нужна.

private struct ConceptsMuteExceptionUnseenEntry: Codable, Equatable {
    var id: Int32
    var timestamp: Int32
}

private let conceptsMuteExceptionUnseenKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 10002)
    return key
}()

private func decodeConceptsMuteExceptionUnseen(_ entry: PreferencesEntry?) -> [Int64: [ConceptsMuteExceptionUnseenEntry]] {
    guard let data = entry?.data, let value = try? JSONDecoder().decode([Int64: [ConceptsMuteExceptionUnseenEntry]].self, from: data) else {
        return [:]
    }
    return value
}

func conceptsMuteExceptionMarkUnseen(transaction: Transaction, message: Message) {
    let peerId = message.id.peerId
    let readState = transaction.getCombinedPeerReadState(peerId)
    transaction.updatePreferencesEntry(key: conceptsMuteExceptionUnseenKey, { entry in
        var all = decodeConceptsMuteExceptionUnseen(entry)
        var list = all[peerId.toInt64()] ?? []
        if list.contains(where: { $0.id == message.id.id }) {
            return entry
        }
        list.removeAll(where: { item in
            return readState?.isIncomingMessageIndexRead(MessageIndex(id: MessageId(peerId: peerId, namespace: message.id.namespace, id: item.id), timestamp: item.timestamp)) ?? false
        })
        list.append(ConceptsMuteExceptionUnseenEntry(id: message.id.id, timestamp: message.timestamp))
        all[peerId.toInt64()] = list
        guard let json = try? JSONEncoder().encode(all) else {
            return entry
        }
        return PreferencesEntry(data: json)
    })
}

/// Все помеченные посты по каналам. Прочитанные отфильтровывает потребитель по состоянию прочтения.
public func conceptsMuteExceptionUnseen(postbox: Postbox) -> Signal<[PeerId: [MessageIndex]], NoError> {
    return postbox.preferencesView(keys: [conceptsMuteExceptionUnseenKey])
    |> map { view -> [PeerId: [MessageIndex]] in
        var result: [PeerId: [MessageIndex]] = [:]
        for (peerIdValue, list) in decodeConceptsMuteExceptionUnseen(view.values[conceptsMuteExceptionUnseenKey]) {
            let peerId = PeerId(peerIdValue)
            result[peerId] = list.map { MessageIndex(id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: $0.id), timestamp: $0.timestamp) }
        }
        return result
    }
    |> distinctUntilChanged
}

/// Непрочитанные посты из исключений одного канала, по возрастанию.
public func conceptsMuteExceptionUnreadIndices(_ indices: [MessageIndex], readCounters: EnginePeerReadCounters?) -> [MessageIndex] {
    guard let readCounters, readCounters.isUnread else {
        return []
    }
    return indices.filter { !readCounters.isIncomingMessageIndexRead($0) }.sorted()
}
