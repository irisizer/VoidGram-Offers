import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit

// Локальные концепты: офлайн-демо без сервера (флаг запуска `--concepts-offline-demo`).
// Сеть заменяется движком, который никогда не отвечает и ничего не отправляет, а аккаунт
// и чаты записываются прямо в Postbox. Без флага поведение приложения не меняется.

/// Устанавливается приложением при старте до создания первого аккаунта.
public var conceptsOfflineDemoEnabled = false

/// MTContext сам создаёт служебные соединения (ключи, синхронизация времени) в обход движка.
/// В офлайн-демо все его TCP-соединения идут через закрытый локальный порт и сразу обрываются.
let conceptsOfflineDemoProxySettings = MTSocksProxySettings(ip: "127.0.0.1", port: 1, username: nil, password: nil, secret: nil)

final class ConceptsOfflineNetworkEngine: NetworkEngine {
    let kind: NetworkEngineKind = .mtProtoKit

    func makeSession(datacenterId: Int, role: NetworkEngineSessionRole, usageCalculationInfo: MTNetworkUsageCalculationInfo?, delegate: NetworkEngineSessionDelegate?) -> NetworkEngineSession {
        return ConceptsOfflineNetworkSession(datacenterId: datacenterId, delegate: delegate)
    }
}

private final class ConceptsOfflineRequestService: NetworkEngineRequestService {
    func add(_ request: NetworkEngineRequest) -> Disposable {
        // Запрос принят, но ответа не будет: экраны остаются на данных из Postbox.
        return ActionDisposable {
            let _ = request
        }
    }
}

private final class ConceptsOfflineNetworkSession: NetworkEngineSession {
    let datacenterId: Int
    let requestService: NetworkEngineRequestService = ConceptsOfflineRequestService()
    private weak var delegate: NetworkEngineSessionDelegate?

    init(datacenterId: Int, delegate: NetworkEngineSessionDelegate?) {
        self.datacenterId = datacenterId
        self.delegate = delegate
    }

    func setPaused(_ paused: Bool) {
        // Шапка «Чаты» без «Соединение…»: сессия сразу сообщает, что она онлайн.
        self.delegate?.networkSessionConnectionStateChanged(NetworkEngineConnectionState(isNetworkAvailable: true, isConnected: true, isUpdatingConnectionContext: false, isPerformingServiceTasks: false, proxyAddress: nil, proxyHasConnectionIssues: false))
    }

    func setOnline(_ online: Bool) {
    }

    func addUpdateSink(_ sink: NetworkEngineUpdateSink) {
    }

    func stop() {
    }

    func movePendingRequests(to service: NetworkEngineRequestService, deadline: Double, completion: @escaping () -> Void) {
        completion()
    }
}

/// Тот же переход, что после настоящего входа: состояние авторизации в Postbox и смена записи
/// аккаунта в AccountManager. `seed` наполняет Postbox демо-данными в той же транзакции.
public func conceptsOfflineDemoSignIn(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount, accountPeerId: PeerId, seed: @escaping (Transaction) -> Void) -> Signal<Void, NoError> {
    let appliedState = account.postbox.transaction { transaction -> Void in
        if let hole = account.postbox.seedConfiguration.initializeChatListWithHole.topLevel {
            transaction.replaceChatListHole(groupId: .root, index: hole.index, hole: nil)
        }
        initializedAppSettingsAfterLogin(transaction: transaction, appVersion: account.networkArguments.appVersion, syncContacts: false)
        seed(transaction)
        transaction.setState(AuthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, peerId: accountPeerId, state: nil, invalidatedChannels: []))
    }
    return appliedState
    |> mapToSignal { _ -> Signal<Void, NoError> in
        return accountManager.transaction { transaction -> Void in
            switchToAuthorizedAccount(transaction: transaction, account: account, isSupportUser: false)
        }
    }
}
