# PRs and issues in a watched GitHub repo are known as "owner/repo#123". That
# is also their key in stale_snoozes, where it can never clash with a Jira key.
# GitHub numbers issues and PRs from one sequence, so it never clashes between
# the two either.
module GithubKeyed
  extend ActiveSupport::Concern

  KEY_FORMAT = %r{\A[\w.-]+/[\w.-]+#\d+\z}

  class_methods do
    def snooze_key?(key) = GithubKeyed.key?(key)

    def find_by_key(key)
      return nil unless GithubKeyed.key?(key)
      repo, number = key.to_s.split("#", 2)
      where("lower(repo) = ?", repo.downcase).find_by(number: number.to_i)
    end
  end

  def self.key?(key) = KEY_FORMAT.match?(key.to_s)

  # The open PR or issue behind a key, if it is still open.
  def self.find(key) = ReviewPullRequest.find_by_key(key) || GithubIssue.find_by_key(key)

  def key = "#{repo}##{number}"
  def repo_name = repo.split("/", 2).last

  # Changes whenever the ball moves, which is what ends a snooze early, the way
  # a status change does for a ticket.
  def snooze_state = "#{stage}:#{waiting_on}:#{waiting_since.to_i}"

  # Set by GitHub for anyone who is not a member or collaborator of the org.
  def community? = %w[MEMBER OWNER COLLABORATOR].exclude?(author_association.to_s)

  def first_time_contributor? = %w[FIRST_TIME_CONTRIBUTOR FIRST_TIMER].include?(author_association.to_s)

  def label_list = Array(labels).map(&:to_s)
  def people_name_map = people_names.is_a?(Hash) ? people_names : {}
end
