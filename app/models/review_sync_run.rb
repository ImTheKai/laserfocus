# One pass of ReviewSync (kind "pulls") or IssueSync ("issues") against GitHub. Kept apart from SyncRun so a GitHub
# hiccup never makes the Jira board look stale, or the other way round.
class ReviewSyncRun < ApplicationRecord
  scope :ok, -> { where(ok: true) }
  scope :most_recent, -> { order(started_at: :desc) }
  scope :pulls, -> { where(kind: "pulls") }
  scope :issues, -> { where(kind: "issues") }
end
