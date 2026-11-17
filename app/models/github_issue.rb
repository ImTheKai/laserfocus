# An open issue in one of the repos the Issues view watches. IssueSync rewrites
# these on every tick; the stage, who the issue waits on and since when are
# worked out at sync time (see IssueClassifier), so the view only reads.
class GithubIssue < ApplicationRecord
  include GithubKeyed

  STAGES = %w[new us reporter backlog].freeze

  validates :repo, :number, :title, :url, :opened_at, :stage, :waiting_on, :waiting_since, presence: true
  validates :stage, inclusion: { in: STAGES }

  def comment_list = Array(comments).select { |c| c.is_a?(Hash) && c["login"].present? }
  def assignee_list = Array(assignees).map(&:to_s)

  # Everyone but the reporter who commented, latest last.
  def replied_logins
    comment_list.map { |c| c["login"] }.reject { |l| l.casecmp?(author.to_s) }.uniq(&:downcase)
  end

  # Nobody but the reporter has commented yet.
  def no_reply? = replied_logins.empty?

  def last_comment = comment_list.last

  # What the shared People filter asks of every item, see GithubViewPresenter.
  def asked_logins = assignee_list
  def participant_logins = (replied_logins + assignee_list).uniq(&:downcase)
end
