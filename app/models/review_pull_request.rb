# An open, ready-for-review pull request in one of the repos the Reviews view
# watches. ReviewSync rewrites these on every tick; the stage, who the PR waits
# on and since when are worked out at sync time, so the view only reads.
class ReviewPullRequest < ApplicationRecord
  STAGES = %w[needs discuss changes approved].freeze
  KEY_FORMAT = %r{\A[\w.-]+/[\w.-]+#\d+\z}

  validates :repo, :number, :title, :url, :opened_at, :stage, :waiting_on, :waiting_since, presence: true
  validates :stage, inclusion: { in: STAGES }

  # Snoozes share the stale_snoozes table with tickets. A PR's key there is
  # "owner/repo#123", which can never clash with a Jira key.
  def self.snooze_key?(key) = KEY_FORMAT.match?(key.to_s)

  def self.find_by_key(key)
    return nil unless snooze_key?(key)
    repo, number = key.to_s.split("#", 2)
    where("lower(repo) = ?", repo.downcase).find_by(number: number.to_i)
  end

  def key = "#{repo}##{number}"
  def repo_name = repo.split("/", 2).last

  # Changes whenever the ball moves (a review, a push, an approval), which is
  # what ends a snooze early, the way a status change does for a ticket.
  def snooze_state = "#{stage}:#{waiting_on}:#{waiting_since.to_i}"

  # Set by GitHub for anyone who is not a member or collaborator of the org.
  def community? = %w[MEMBER OWNER COLLABORATOR].exclude?(author_association.to_s)

  def first_time_contributor? = %w[FIRST_TIME_CONTRIBUTOR FIRST_TIMER].include?(author_association.to_s)

  def review_list = Array(reviews).select { |r| r.is_a?(Hash) }
  def requested_list = Array(requested_reviewers).map(&:to_s)
  def jira_key_list = Array(jira_keys).map(&:to_s)
  def label_list = Array(labels).map(&:to_s)

  def reviewer_logins = (review_list.map { |r| r["login"] } + requested_list).compact.uniq
end
