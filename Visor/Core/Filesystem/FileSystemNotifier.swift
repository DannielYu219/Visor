import Foundation

/// 文件变更通知中心
/// 任何文件写/删操作后调用 `notify(sessionId:path:kind:)`；
/// 画布 / 侧边栏订阅对应 session 的 publisher 即可刷新。
/// 设计：单进程内 NotificationCenter，避免 FSEvents/DispatchSource 的复杂度
nonisolated final class FileSystemNotifier {
    static let shared = FileSystemNotifier()

    /// Notification.Name.userInfo:
    /// - "sessionId": UUID
    /// - "path": String (相对路径，删时为 nil)
    /// - "kind": "write" | "remove"
    /// - "switchTo": Bool（仅用户上传 HTML 时为 true，画布应切换渲染目标）
    nonisolated static let didChange = Notification.Name("FileSystemStore.didChange")

    private init() {}

    nonisolated func notify(
        sessionId: UUID,
        path: String,
        kind: ChangeKind,
        switchTo: Bool = false
    ) {
        NotificationCenter.default.post(
            name: Self.didChange,
            object: nil,
            userInfo: [
                "sessionId": sessionId,
                "path": path,
                "kind": kind.rawValue,
                "switchTo": switchTo
            ]
        )
    }

    enum ChangeKind: String {
        case write
        case remove
    }

    /// 指定 session 的变更流（AsyncStream）
    /// - 用途：画布 / 侧边栏订阅，文件变更时自动刷新
    /// - Yield: 切换目标的相对路径（switchTo=true 时）；否则为 nil（仅刷新当前文件）
    nonisolated func notifications(for sessionId: UUID) -> AsyncStream<String?> {
        AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: Self.didChange,
                object: nil,
                queue: .main
            ) { note in
                guard let info = note.userInfo,
                      let sid = info["sessionId"] as? UUID,
                      sid == sessionId else { return }
                let switchTo = info["switchTo"] as? Bool ?? false
                let path = info["path"] as? String
                if switchTo, let path = path {
                    continuation.yield(path)
                } else {
                    continuation.yield(nil)
                }
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
