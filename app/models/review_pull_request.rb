# An open, ready-for-review pull request in one of the repos the Reviews view
# watches. ReviewSync rewrites these on every tick; the stage, who the PR waits
# on and since when are worked out at sync time, so the view only reads.
class ReviewPullRequest < ApplicationRecord
  include GithubKeyed

  STAGES = %w[needs discuss changes approved].freeze

  validates :repo, :number, :title, :url, :opened_at, :stage, :waiting_on, :waiting_since, presence: true
  validates :stage, inclusion: { in: STAGES }

  def review_list = Array(reviews).select { |r| r.is_a?(Hash) }
  def requested_list = Array(requested_reviewers).map(&:to_s)
  def jira_key_list = Array(jira_keys).map(&:to_s)

  # Logins other than the author that left a review: a comment, an approval or
  # a change request.
  def replied_logins
    review_list.filter_map do |r|
      r["login"] if ReviewClassifier::COUNTED_STATES.include?(r["state"]) && !r["login"].to_s.casecmp?(author.to_s)
    end
  end

  # Nobody but the author has commented or reviewed yet.
  def no_reply? = replied_logins.empty?

  def reviewer_logins = (review_list.map { |r| r["login"] } + requested_list).compact.uniq

  # What the shared People filter asks of every item, see GithubViewPresenter.
  def asked_logins = requested_list
  def participant_logins = reviewer_logins
end
