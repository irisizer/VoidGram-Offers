import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import Postbox
import Display
import ChatControllerInteraction

// Локальные концепты: непрочитанные посты канала без звука, прошедшие через исключение.
// Питают кнопку доскролла с колокольчиком, как кнопки упоминаний и реакций.
func conceptsMuteExceptionUnreadMessages(context: AccountContext, peerId: EnginePeer.Id) -> Signal<[EngineMessage.Index], NoError> {
    return combineLatest(
        conceptsMuteExceptionUnseen(postbox: context.account.postbox)
        |> map { unseen -> [EngineMessage.Index] in
            return unseen[peerId] ?? []
        }
        |> distinctUntilChanged,
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId))
    )
    |> map { indices, readCounters -> [EngineMessage.Index] in
        return conceptsMuteExceptionUnreadIndices(indices, readCounters: readCounters)
    }
    |> distinctUntilChanged
}

/// Слово из исключения, найденное в тексте поста: его подсвечиваем внутри пузыря.
func conceptsMuteExceptionQuote(context: AccountContext, messageId: EngineMessage.Id) -> Signal<NavigateToMessageParams.Quote?, NoError> {
    return context.account.postbox.transaction { transaction -> NavigateToMessageParams.Quote? in
        guard let message = transaction.getMessage(messageId), !message.text.isEmpty else {
            return nil
        }
        let exception = conceptsMuteException(transaction: transaction, peerId: messageId.peerId)
        guard let keyword = conceptsMuteExceptionKeywordMatch(text: message.text, keywords: exception.keywords) else {
            return nil
        }
        let text = message.text as NSString
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            if found.location == NSNotFound {
                break
            }
            let isWordStart = found.location == 0 || !CharacterSet.alphanumerics.contains(UnicodeScalar(text.character(at: found.location - 1)) ?? " ")
            let endIndex = found.location + found.length
            let isWordEnd = endIndex >= text.length || !CharacterSet.alphanumerics.contains(UnicodeScalar(text.character(at: endIndex)) ?? " ")
            if isWordStart && isWordEnd {
                return NavigateToMessageParams.Quote(string: text.substring(with: found), offset: found.location)
            }
            searchRange = NSRange(location: endIndex, length: text.length - endIndex)
        }
        return nil
    }
}

/// Куда ставить пост при доскролле. В демо режим можно поменять без пересборки в /tmp/concepts-demo-coords.json:
/// {"scrollMode": [0..3, смещение]}: 0 — .top, 1 — .bottom, 2 — .center(.top), 3 — .center(.bottom).
func conceptsDemoScrollPosition(key: String, fallback: ListViewScrollPosition) -> ListViewScrollPosition {
    guard conceptsOfflineDemoEnabled, let data = FileManager.default.contents(atPath: "/tmp/concepts-demo-coords.json"), let json = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]], let value = json[key], value.count == 2 else {
        return fallback
    }
    let offset = CGFloat(value[1])
    switch Int(value[0]) {
    case 0: return .top(offset)
    case 1: return .bottom(offset)
    case 2: return .center(.top)
    default: return .center(.bottom)
    }
}
