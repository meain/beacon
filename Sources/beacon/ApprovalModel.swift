import Foundation

/// Owns the approval lifecycle for a fin turn: holds the pending request and
/// routes approve/deny decisions back to the runner.
@MainActor
final class ApprovalModel: ObservableObject {
    @Published var pending: ApprovalRequest?

    private weak var runner: FinRunner?

    init(runner: FinRunner) {
        self.runner = runner
    }

    func set(_ request: ApprovalRequest) {
        pending = request
    }

    func approve() {
        pending = nil
        runner?.respondToApproval(approve: true)
    }

    func deny() {
        pending = nil
        runner?.respondToApproval(approve: false)
    }

    func clear() {
        pending = nil
    }
}
