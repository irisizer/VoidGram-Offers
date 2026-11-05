import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ChatListFilterSettingsHeaderItem
import PresentationDataUtils
import AccountContext

// Локальные концепты: экран «Исключения» для канала без звука. Сначала ключевые слова (работают
// для любого поста), затем типы постов. По умолчанию всё выключено (ConceptsMuteExceptions.swift).
// Устройство повторяет настройки: строки с иконками как в «Сохранять в Фото», слова — фишками
// в одном поле, как получатели в поле «Кому» (PeerInfoMuteExceptionsKeywordsItem.swift).

func conceptsMuteExceptionsString(_ strings: PresentationStrings, _ en: String, _ ru: String) -> String {
    return strings.baseLanguageCode == "ru" ? ru : en
}

func muteExceptionContentTitle(_ strings: PresentationStrings, _ content: ConceptsMuteExceptionContent) -> String {
    switch content {
    case .text:
        return conceptsMuteExceptionsString(strings, "All Text Posts", "Все текстовые посты")
    case .photo:
        return conceptsMuteExceptionsString(strings, "Photos", "Фото")
    case .video:
        return conceptsMuteExceptionsString(strings, "Videos", "Видео")
    case .sticker:
        return conceptsMuteExceptionsString(strings, "Stickers", "Стикеры")
    case .gif:
        return conceptsMuteExceptionsString(strings, "GIFs", "GIF")
    case .audio:
        return conceptsMuteExceptionsString(strings, "Music", "Музыка")
    case .voice:
        return conceptsMuteExceptionsString(strings, "Voice Messages", "Голосовые")
    case .roundVideo:
        return conceptsMuteExceptionsString(strings, "Video Messages", "Видеосообщения")
    case .file:
        return conceptsMuteExceptionsString(strings, "Files", "Файлы")
    case .link:
        return conceptsMuteExceptionsString(strings, "Links", "Ссылки")
    case .poll:
        return conceptsMuteExceptionsString(strings, "Polls", "Опросы")
    case .giveaway:
        return conceptsMuteExceptionsString(strings, "Giveaways", "Розыгрыши")
    case .location:
        return conceptsMuteExceptionsString(strings, "Locations", "Геопозиции")
    case .contact:
        return conceptsMuteExceptionsString(strings, "Contacts", "Контакты")
    case .story:
        return conceptsMuteExceptionsString(strings, "Stories", "Истории")
    case .paid:
        return conceptsMuteExceptionsString(strings, "Paid Media", "Платное медиа")
    }
}

private let roundVideoIcon = renderSettingsIcon(name: "Item List/Icons/Video", backgroundColors: [UIColor(rgb: 0x00c7be)])
private let linkIcon = renderSettingsIcon(name: "Item List/Icons/Link", backgroundColors: [UIColor(rgb: 0xffcc02)])
private let pollIcon = renderSettingsIcon(name: "Item List/Icons/Stats", backgroundColors: [UIColor(rgb: 0xff2d55)])
private let giveawayIcon = renderSettingsIcon(name: "Item List/Icons/Gift", backgroundColors: [UIColor(rgb: 0xaf52de)])
private let otherIcon = renderSettingsIcon(name: "Item List/Icons/Multiple", backgroundColors: [UIColor(rgb: 0x8e8e93)])

func muteExceptionContentIcon(_ content: ConceptsMuteExceptionContent) -> UIImage? {
    switch content {
    case .text:
        return PresentationResourcesSettings.messages
    case .photo:
        return PresentationResourcesSettings.photosLightBlue
    case .video:
        return PresentationResourcesSettings.videos
    case .sticker:
        return PresentationResourcesSettings.stickersGreen
    case .gif:
        return PresentationResourcesSettings.gifs
    case .audio:
        return PresentationResourcesSettings.music
    case .voice:
        return PresentationResourcesSettings.voices
    case .roundVideo:
        return roundVideoIcon
    case .file:
        return PresentationResourcesSettings.files
    case .link:
        return linkIcon
    case .poll:
        return pollIcon
    case .giveaway:
        return giveawayIcon
    case .paid:
        return PresentationResourcesSettings.photosLightBlue
    case .location, .contact, .story:
        return otherIcon
    }
}

/// Короткое описание для второй строки пункта меню: ««тон», Photos».
func conceptsMuteExceptionSummary(_ strings: PresentationStrings, _ exception: ConceptsMuteException) -> String {
    var parts = exception.keywords.map { "«\($0)»" }
    for content in ConceptsMuteExceptionContent.allCases where exception.contentTypes.contains(content) {
        parts.append(muteExceptionContentTitle(strings, content))
    }
    return parts.joined(separator: ", ")
}

private let maxKeywordCount = 50

/// Типы, которые собраны в раскрывающуюся группу «Media», как «Отправка медиа» в правах группы.
private let mediaContentTypes: [ConceptsMuteExceptionContent] = [.photo, .video, .sticker, .gif, .audio, .voice, .roundVideo, .file, .link, .paid]
/// Редкие типы постов — вторая раскрывающаяся группа «Other».
private let otherContentTypes: [ConceptsMuteExceptionContent] = [.location, .contact, .story]

private struct MuteExceptionsMediaItem: Equatable {
    let content: ConceptsMuteExceptionContent
    let title: String
    let isSelected: Bool
}

private final class MuteExceptionsArguments {
    let context: AccountContext
    let toggle: (ConceptsMuteExceptionContent, Bool) -> Void
    let setGroup: ([ConceptsMuteExceptionContent], Bool) -> Void
    let toggleExpanded: (Bool) -> Void
    let addKeyword: (String) -> Bool
    let removeKeyword: (String) -> Void
    let toggleSuggestion: (String) -> Void
    let reset: () -> Void

    init(context: AccountContext, toggle: @escaping (ConceptsMuteExceptionContent, Bool) -> Void, setGroup: @escaping ([ConceptsMuteExceptionContent], Bool) -> Void, toggleExpanded: @escaping (Bool) -> Void, addKeyword: @escaping (String) -> Bool, removeKeyword: @escaping (String) -> Void, toggleSuggestion: @escaping (String) -> Void, reset: @escaping () -> Void) {
        self.context = context
        self.toggle = toggle
        self.setGroup = setGroup
        self.toggleExpanded = toggleExpanded
        self.addKeyword = addKeyword
        self.removeKeyword = removeKeyword
        self.toggleSuggestion = toggleSuggestion
        self.reset = reset
    }
}

private enum MuteExceptionsSection: Int32 {
    case header
    case keywords
    case types
    case reset
}

private enum MuteExceptionsEntry: ItemListNodeEntry {
    case header(String, EnginePeer)
    case keywordsHeader(String)
    case keywords([String], [String], String, Bool)
    case keywordsFooter(String)
    case typesHeader(String)
    case text(String, Bool)
    case media(String, [MuteExceptionsMediaItem], Bool)
    case poll(String, Bool)
    case giveaway(String, Bool)
    case other(String, [MuteExceptionsMediaItem], Bool)
    case typesFooter(String)
    case reset(String)

    var section: ItemListSectionId {
        switch self {
        case .header:
            return MuteExceptionsSection.header.rawValue
        case .keywordsHeader, .keywords, .keywordsFooter:
            return MuteExceptionsSection.keywords.rawValue
        case .typesHeader, .text, .media, .poll, .giveaway, .other, .typesFooter:
            return MuteExceptionsSection.types.rawValue
        case .reset:
            return MuteExceptionsSection.reset.rawValue
        }
    }

    var sortIndex: Int32 {
        switch self {
        case .header:
            return 0
        case .keywordsHeader:
            return 10
        case .keywords:
            return 11
        case .keywordsFooter:
            return 12
        case .typesHeader:
            return 1000
        case .text:
            return 1001
        case .media:
            return 1002
        case .poll:
            return 1003
        case .giveaway:
            return 1004
        case .other:
            return 1005
        case .typesFooter:
            return 1900
        case .reset:
            return 2000
        }
    }

    var stableId: Int32 {
        return self.sortIndex
    }

    static func ==(lhs: MuteExceptionsEntry, rhs: MuteExceptionsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.keywordsHeader(l), .keywordsHeader(r)), let (.keywordsFooter(l), .keywordsFooter(r)), let (.typesHeader(l), .typesHeader(r)), let (.typesFooter(l), .typesFooter(r)), let (.reset(l), .reset(r)):
            return l == r
        case let (.header(lt, lp), .header(rt, rp)):
            return lt == rt && lp == rp
        case let (.keywords(lk, ls, lp, le), .keywords(rk, rs, rp, re)):
            return lk == rk && ls == rs && lp == rp && le == re
        case let (.text(lt, lv), .text(rt, rv)), let (.poll(lt, lv), .poll(rt, rv)), let (.giveaway(lt, lv), .giveaway(rt, rv)):
            return lt == rt && lv == rv
        case let (.media(lt, li, le), .media(rt, ri, re)), let (.other(lt, li, le), .other(rt, ri, re)):
            return lt == rt && li == ri && le == re
        default:
            return false
        }
    }

    static func <(lhs: MuteExceptionsEntry, rhs: MuteExceptionsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MuteExceptionsArguments
        switch self {
        case let .header(text, peer):
            return ChatListFilterSettingsHeaderItem(context: arguments.context, theme: presentationData.theme, text: text, animation: .notifications, cornerPeer: peer, headline: conceptsMuteExceptionsString(presentationData.strings, "Unmute Similar Posts", "Звук для похожих постов"), sectionId: self.section)
        case let .keywordsHeader(text), let .typesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .keywords(keywords, suggestions, placeholder, isInputEnabled):
            return PeerInfoMuteExceptionsKeywordsItem(presentationData: presentationData, keywords: keywords, suggestions: suggestions, placeholder: placeholder, isInputEnabled: isInputEnabled, sectionId: self.section, add: { keyword in
                return arguments.addKeyword(keyword)
            }, remove: { keyword in
                arguments.removeKeyword(keyword)
            }, addSuggestion: { word in
                arguments.toggleSuggestion(word)
            })
        case let .keywordsFooter(text), let .typesFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .text(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: muteExceptionContentIcon(.text), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(.text, value)
            })
        case let .media(title, items, isExpanded):
            return expandableItem(presentationData: presentationData, arguments: arguments, icon: PresentationResourcesSettings.photosLightBlue, title: title, types: mediaContentTypes, items: items, isExpanded: isExpanded, isMedia: true, sectionId: self.section)
        case let .other(title, items, isExpanded):
            return expandableItem(presentationData: presentationData, arguments: arguments, icon: muteExceptionContentIcon(.location), title: title, types: otherContentTypes, items: items, isExpanded: isExpanded, isMedia: false, sectionId: self.section)
        case let .poll(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: muteExceptionContentIcon(.poll), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(.poll, value)
            })
        case let .giveaway(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: muteExceptionContentIcon(.giveaway), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(.giveaway, value)
            })
        case let .reset(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.reset()
            })
        }
    }
}

private func expandableItem(presentationData: ItemListPresentationData, arguments: MuteExceptionsArguments, icon: UIImage?, title: String, types: [ConceptsMuteExceptionContent], items: [MuteExceptionsMediaItem], isExpanded: Bool, isMedia: Bool, sectionId: ItemListSectionId) -> ListViewItem {
    return ItemListExpandableSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, value: items.allSatisfy { $0.isSelected }, isExpanded: isExpanded, subItems: items.map { item in
        return ItemListExpandableSwitchItem.SubItem(id: AnyHashable(item.content.rawValue), title: item.title, isSelected: item.isSelected, isEnabled: true)
    }, sectionId: sectionId, style: .blocks, updated: { value in
        arguments.setGroup(types, value)
    }, selectAction: {
        arguments.toggleExpanded(isMedia)
    }, subAction: { subItem in
        guard let rawValue = subItem.id.base as? String, let content = ConceptsMuteExceptionContent(rawValue: rawValue) else {
            return
        }
        arguments.toggle(content, !subItem.isSelected)
    })
}

private func muteExceptionsEntries(strings: PresentationStrings, peer: EnginePeer, title: String, exception: ConceptsMuteException, suggestions: [String], isMediaExpanded: Bool, isOtherExpanded: Bool) -> [MuteExceptionsEntry] {
    var entries: [MuteExceptionsEntry] = []
    entries.append(.header(conceptsMuteExceptionsString(strings, "«\(title)» stays muted. You’ll get sound only for posts with these words or of these types.", "«\(title)» остаётся без звука. Звук будет только у постов с этими словами или такого типа."), peer))
    
    entries.append(.keywordsHeader(conceptsMuteExceptionsString(strings, "KEYWORDS", "КЛЮЧЕВЫЕ СЛОВА")))
    let isInputEnabled = exception.keywords.count < maxKeywordCount
    let placeholder = exception.keywords.isEmpty ? conceptsMuteExceptionsString(strings, "Add a word, e.g. TON", "Добавить слово, например «тон»") : conceptsMuteExceptionsString(strings, "Add a word", "Добавить слово")
    // Слова из поста — серые контурные фишки в этой же ячейке; уже добавленные не показываем.
    let addedKeywords = Set(exception.keywords.map { $0.lowercased() })
    let visibleSuggestions = suggestions.filter { !addedKeywords.contains($0.lowercased()) }
    entries.append(.keywords(exception.keywords, visibleSuggestions, placeholder, isInputEnabled))
    if !isInputEnabled {
        entries.append(.keywordsFooter(conceptsMuteExceptionsString(strings, "You've reached the limit of \(maxKeywordCount) words. Remove one to add another.", "Это максимум — \(maxKeywordCount) слов. Удалите одно, чтобы добавить новое.")))
    } else if !visibleSuggestions.isEmpty {
        entries.append(.keywordsFooter(conceptsMuteExceptionsString(strings, "Tap a gray word from this post to add it. Tap an added word twice to remove it.", "Нажмите на серое слово из поста, чтобы добавить его. Чтобы удалить добавленное, нажмите на него дважды.")))
    } else if exception.keywords.isEmpty {
        entries.append(.keywordsFooter(conceptsMuteExceptionsString(strings, "Posts and captions with these words will notify you. Separate words with Return or a comma.", "Посты и подписи с этими словами будут уведомлять. Слова разделяйте вводом или запятой.")))
    } else {
        entries.append(.keywordsFooter(conceptsMuteExceptionsString(strings, "Tap a word twice to remove it.", "Чтобы удалить слово, нажмите на него дважды.")))
    }
    
    entries.append(.typesHeader(conceptsMuteExceptionsString(strings, "ALSO NOTIFY ABOUT", "ТАКЖЕ УВЕДОМЛЯТЬ О")))
    entries.append(.text(muteExceptionContentTitle(strings, .text), exception.contentTypes.contains(.text)))
    entries.append(.media(conceptsMuteExceptionsString(strings, "Media", "Медиа"), mediaContentTypes.map { content in
        return MuteExceptionsMediaItem(content: content, title: muteExceptionContentTitle(strings, content), isSelected: exception.contentTypes.contains(content))
    }, isMediaExpanded))
    entries.append(.poll(muteExceptionContentTitle(strings, .poll), exception.contentTypes.contains(.poll)))
    entries.append(.giveaway(muteExceptionContentTitle(strings, .giveaway), exception.contentTypes.contains(.giveaway)))
    entries.append(.other(conceptsMuteExceptionsString(strings, "Other", "Другое"), otherContentTypes.map { content in
        return MuteExceptionsMediaItem(content: content, title: muteExceptionContentTitle(strings, content), isSelected: exception.contentTypes.contains(content))
    }, isOtherExpanded))
    entries.append(.typesFooter(conceptsMuteExceptionsString(strings, "Posts of these types notify you even without keywords.", "Посты этих типов уведомляют, даже если в них нет ключевых слов.")))
    
    if !exception.isEmpty {
        entries.append(.reset(conceptsMuteExceptionsString(strings, "Remove All Exceptions", "Удалить все исключения")))
    }
    return entries
}

/// Единственный редактор исключений канала. `suggestionsFrom` — текст поста, из которого открыт редактор
/// (меню поста): слова из него показываются подсказками; `isModal` — открыт карточкой с кнопкой «Done».
public func peerInfoMuteExceptionsScreen(context: AccountContext, peer: EnginePeer, suggestionsFrom postText: String? = nil, isModal: Bool = false) -> ViewController {
    let peerId = peer.id
    let suggestions = postText.map { muteExceptionSuggestedWords(from: $0) } ?? []
    // Слова, известные экрану прямо сейчас: ячейка с фишками сразу узнаёт, принято ли слово.
    let currentKeywords = Atomic<[String]>(value: [])
    // Группа «Media» свёрнута, пока пользователь её не откроет (в демо её можно раскрыть флагом запуска).
    let initialMediaExpanded = conceptsOfflineDemoEnabled && ProcessInfo.processInfo.arguments.contains("--concepts-demo-expand-media")
    let isMediaExpanded = ValuePromise<Bool>(initialMediaExpanded, ignoreRepeated: true)
    let isMediaExpandedValue = Atomic<Bool>(value: initialMediaExpanded)
    let initialOtherExpanded = conceptsOfflineDemoEnabled && ProcessInfo.processInfo.arguments.contains("--concepts-demo-expand-other")
    let isOtherExpanded = ValuePromise<Bool>(initialOtherExpanded, ignoreRepeated: true)
    let isOtherExpandedValue = Atomic<Bool>(value: initialOtherExpanded)

    let update: (@escaping (ConceptsMuteException) -> ConceptsMuteException) -> Void = { f in
        let _ = updateConceptsMuteException(postbox: context.account.postbox, peerId: peerId, f).startStandalone()
    }

    var popImpl: (() -> Void)?

    let addKeywordImpl: (String) -> Bool = { keyword in
        var accepted = false
        let _ = currentKeywords.modify { keywords in
            if keywords.count >= maxKeywordCount || keywords.contains(where: { $0.lowercased() == keyword.lowercased() }) {
                return keywords
            }
            accepted = true
            return keywords + [keyword]
        }
        if accepted {
            update { exception in
                var exception = exception
                if !exception.keywords.contains(where: { $0.lowercased() == keyword.lowercased() }) && exception.keywords.count < maxKeywordCount {
                    exception.keywords.append(keyword)
                }
                return exception
            }
        }
        return accepted
    }
    let removeKeywordImpl: (String) -> Void = { keyword in
        let _ = currentKeywords.modify { keywords in
            return keywords.filter { $0 != keyword }
        }
        update { exception in
            var exception = exception
            exception.keywords.removeAll(where: { $0 == keyword })
            return exception
        }
    }

    let arguments = MuteExceptionsArguments(context: context, toggle: { content, value in
        update { exception in
            var exception = exception
            if value {
                exception.contentTypes.insert(content)
            } else {
                exception.contentTypes.remove(content)
            }
            return exception
        }
    }, setGroup: { types, value in
        update { exception in
            var exception = exception
            for content in types {
                if value {
                    exception.contentTypes.insert(content)
                } else {
                    exception.contentTypes.remove(content)
                }
            }
            return exception
        }
    }, toggleExpanded: { isMedia in
        if isMedia {
            let value = isMediaExpandedValue.modify { !$0 }
            isMediaExpanded.set(value)
        } else {
            let value = isOtherExpandedValue.modify { !$0 }
            isOtherExpanded.set(value)
        }
    }, addKeyword: { keyword in
        return addKeywordImpl(keyword)
    }, removeKeyword: { keyword in
        removeKeywordImpl(keyword)
    }, toggleSuggestion: { word in
        if let existing = currentKeywords.with({ $0 }).first(where: { $0.lowercased() == word.lowercased() }) {
            removeKeywordImpl(existing)
        } else {
            let _ = addKeywordImpl(word)
        }
    }, reset: {
        let _ = currentKeywords.swap([])
        update { _ in
            return ConceptsMuteException()
        }
        popImpl?()
    })

    let titleVisiblePromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var dismissImpl: (() -> Void)?
    let title: String
    if case let .channel(channel) = peer {
        title = channel.title
    } else {
        title = ""
    }
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        conceptsMuteException(postbox: context.account.postbox, peerId: peerId),
        isMediaExpanded.get(),
        isOtherExpanded.get(),
        titleVisiblePromise.get()
    )
    |> map { presentationData, exception, isMediaExpanded, isOtherExpanded, titleVisible -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let _ = currentKeywords.swap(exception.keywords)
        let rightNavigationButton: ItemListNavigationButton? = ItemListNavigationButton(content: .icon(.done), style: .bold, enabled: true, action: {
            dismissImpl?()
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(titleVisible ? conceptsMuteExceptionsString(presentationData.strings, "Unmute Similar", "Звук для похожих") : ""), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: muteExceptionsEntries(strings: presentationData.strings, peer: peer, title: title, exception: exception, suggestions: suggestions, isMediaExpanded: isMediaExpanded, isOtherExpanded: isOtherExpanded), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    if isModal {
        controller.navigationPresentation = .modal
    }
    controller.contentOffsetChanged = { offset, _ in
        // Крупный заголовок уходит под навбар — заголовок появляется в навбаре (как в нативе).
        if case let .known(value) = offset {
            titleVisiblePromise.set(value > 118.0)
        } else if case .none = offset {
            titleVisiblePromise.set(true)
        }
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss(animated: true)
    }
    popImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}
