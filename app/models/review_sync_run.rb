# One pass of ReviewSync against GitHub. Kept apart from SyncRun so a GitHub
# hiccup never makes the Jira board look stale, or the other way round.
class ReviewSyncRun < ApplicationRecord
  scope :ok, -> { where(ok: true) }
  scope :most_recent, -> { order(started_at: :desc) }
end
