// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreData
import Combine
import Pulse

/// Keeps track of hosts, paths, etc.
final class LoggerStoreIndex {
    var hosts: Set<String> = []
    var paths: Set<String> = []

    private let store: LoggerStore
    private var cancellable: AnyCancellable?

    init(store: LoggerStore) {
        self.store = store

        store.backgroundContext.perform {
            self.prepopulate()
        }
        cancellable = store.events.subscribe(on: DispatchQueue.main).sink { [weak self] in
            self?.handle($0)
        }
    }

    private func handle(_ event: LoggerStore.Event) {
        switch event {
        case .networkTaskCompleted(let event):
            if let host = event.originalRequest.url.flatMap(getHost) {
                var hosts = self.hosts
                let (isInserted, _) = hosts.insert(host)
                if isInserted { self.hosts = hosts }
            }
        default:
            break
        }
    }

    private func prepopulate() {
        let urls: Set<String> = {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "NetworkTaskEntity")
            request.resultType = .dictionaryResultType
            request.returnsDistinctResults = true
            request.propertiesToFetch = ["url"]
            guard let results = try? store.backgroundContext.fetch(request) as? [[String: String]] else {
                return []
            }
            return Set(results.flatMap { $0.values })
        }()

        var hosts = Set<String>()
        var paths = Set<String>()

        for url in urls {
            guard let components = URLComponents(string: url) else {
                continue
            }
            if let host = components.host, !host.isEmpty {
                hosts.insert(host)
            }
            paths.insert(components.path)
        }

        DispatchQueue.main.async {
            self.hosts = hosts
            self.paths = paths
        }
    }
}

private func getHost(for url: URL) -> String? {
    if let host = url.host {
        return host
    }
    if url.scheme == nil, let url = URL(string: "https://" + url.absoluteString) {
        return url.host ?? "" // URL(string: "example.com")?.host with not scheme returns host: ""
    }
    return nil
}
