import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import PeerInfoScreen

// Локальные концепты: «Исключить из мьюта…» в меню поста замьюченного канала открывает тот же единственный
// редактор исключений (PeerInfoMuteExceptionsScreen), но карточкой и с подсказками слов из этого поста.
func conceptsPresentMuteExceptionEditor(context: AccountContext, message: EngineRawMessage, navigationController: NavigationController?) {
    guard let rawPeer = message.peers[message.id.peerId] else {
        return
    }
    let editor = peerInfoMuteExceptionsScreen(context: context, peer: EnginePeer(rawPeer), suggestionsFrom: message.text, isModal: true)
    navigationController?.pushViewController(editor)
}
