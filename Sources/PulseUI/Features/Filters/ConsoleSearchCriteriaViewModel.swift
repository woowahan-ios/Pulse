// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import CoreData
import Pulse
import Combine
import SwiftUI

final class ConsoleSearchCriteriaViewModel: ObservableObject {
    var isButtonResetEnabled: Bool { !isCriteriaDefault }

    @Published var isOnlyErrors = false
    @Published var isOnlyNetwork = false
    @Published var filterTerm = "" // Legacy, used on non-iOS platforms
    @Published var criteria = ConsoleSearchCriteria()

    @Published private(set) var labels: [String] = []
    @Published private(set) var domains: [String] = []

    private(set) var labelsCountedSet = NSCountedSet()
    private(set) var domainsCountedSet = NSCountedSet()

    private(set) var defaultCriteria = ConsoleSearchCriteria()

    private let store: LoggerStore
    private var isScreenVisible = false
    private var entities: [NSManagedObject] = []
    private var cancellables: [AnyCancellable] = []

    init(store: LoggerStore) {
        self.store = store

        if store.isArchive {
            self.criteria.shared.dates.startDate = nil
            self.criteria.shared.dates.endDate = nil
        }
        self.defaultCriteria = criteria
    }

    func bind(_ entities: some Publisher<[NSManagedObject], Never>) {
        entities.sink { [weak self] in
            guard let self else { return }
            self.entities = $0
            if self.isScreenVisible {
                self.reloadCounters()
            }
        }.store(in: &cancellables)
    }

    // MARK: Appearance

    func onAppear() {
        isScreenVisible = true
        reloadCounters()
    }

    func onDisappear() {
        isScreenVisible = false
    }

    // MARK: Helpers

    var isCriteriaDefault: Bool {
        guard criteria.shared == defaultCriteria.shared else { return false }
        if isOnlyNetwork {
            return criteria.messages == defaultCriteria.messages
        } else {
            return criteria.network == defaultCriteria.network
        }
    }

    func resetAll() {
        criteria = defaultCriteria
    }

    func removeAllPins() {
        store.pins.removeAllPins()

#if os(iOS)
        runHapticFeedback(.success)
        ToastView {
            HStack {
                Image(systemName: "trash")
                Text("All pins removed")
            }
        }.show()
#endif
    }

    private func reloadCounters() {
        if isOnlyNetwork {
            guard let tasks = entities as? [NetworkTaskEntity] else {
                return assertionFailure()
            }
            domainsCountedSet = NSCountedSet(array: tasks.compactMap { $0.host?.value })
            domains = (domainsCountedSet.allObjects as! [String]).sorted(by: { lhs, rhs in
                domainsCountedSet.count(for: lhs) > domainsCountedSet.count(for: rhs)
            })
        } else {
            guard let messages = entities as? [LoggerMessageEntity] else {
                return assertionFailure()
            }
            labelsCountedSet = NSCountedSet(array: messages.map(\.label.name))
            labels = (labelsCountedSet.allObjects as! [String]).sorted()
        }
    }

    // MARK: Binding (LogLevels)

    func binding(forLevel level: LoggerStore.Level) -> Binding<Bool> {
        Binding(get: {
            self.criteria.messages.logLevels.levels.contains(level)
        }, set: { isOn in
            if isOn {
                self.criteria.messages.logLevels.levels.insert(level)
            } else {
                self.criteria.messages.logLevels.levels.remove(level)
            }
        })
    }

    var isAllLogLevelsEnabled: Bool {
        get {
            criteria.messages.logLevels.levels.count == LoggerStore.Level.allCases.count
        }
        set {
            if newValue {
                criteria.messages.logLevels.levels = Set(LoggerStore.Level.allCases)
            } else {
                criteria.messages.logLevels.levels = []
            }
        }
    }

    // MARK: Binding (Labels)

    var selectedLabels: Set<String> {
        get {
            if let focused = criteria.messages.labels.focused {
                return [focused]
            } else {
                return Set(labels).subtracting(criteria.messages.labels.hidden)
            }
        }
        set {
            criteria.messages.labels.focused = nil
            criteria.messages.labels.hidden = []
            switch newValue.count {
            case 1:
                criteria.messages.labels.focused = newValue.first!
            default:
                criteria.messages.labels.hidden = Set(labels).subtracting(newValue)
            }
        }
    }

    // MARK: Bindings (Hosts)

    var selectedHost: Set<String> {
        get {
            Set(domains).subtracting(criteria.network.host.ignoredHosts)
        }
        set {
            criteria.network.host.ignoredHosts = Set(domains).subtracting(newValue)
        }
    }
}
