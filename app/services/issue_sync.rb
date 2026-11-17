# Mirrors the open issues of the watched repos into github_issues. Runs on the
# same tick as ReviewSync, and like it records its runs in ReviewSyncRun (kind
# "issues") so a GitHub failure never touches anything else.
class IssueSync
  TEAM_ASSOCIATIONS = %w[MEMBER OWNER COLLABORATOR].freeze

  def self.configured? = LASER_FOCUS_CONFIG.issues.present? && LASER_FOCUS_CONFIG.issues.repos.any?

  def initialize(config: LASER_FOCUS_CONFIG.issues, client: GithubClient.new, users: LASER_FOCUS_CONFIG.board.users)
    @config = config
    @client = client
    @users = users
  end

  def run!(now: Time.current)
    previous = ReviewSyncRun.issues.ok.most_recent.first
    run = ReviewSyncRun.create!(kind: "issues", started_at: now)
    @changed = false
    nodes = @client.open_issues(@config.repos)
    excluded = @config.exclude_authors

    seen_ids = []
    nodes.each do |node|
      next if excluded.include?(node.dig("author", "login").to_s.downcase)
      seen_ids << upsert(node).id
    end
    # Closed, transferred, or from a repo no longer listed.
    @changed = true if GithubIssue.where.not(id: seen_ids).delete_all.positive?
    prune_snoozes!(now)

    run.update!(finished_at: Time.current, ok: true, fetched_count: seen_ids.size)
    broadcast if @changed || hour_turned?(previous, now)
    run
  rescue => e
    Rails.logger.warn("[IssueSync] failed: #{e.class}: #{e.message}")
    run&.update!(finished_at: Time.current, ok: false, error_message: e.message.to_s.first(500))
    run
  end

  private

  def upsert(node)
    repo = node.dig("repository", "nameWithOwner").to_s
    issue = GithubIssue.where("lower(repo) = ?", repo.downcase).find_by(number: node["number"]) ||
            GithubIssue.new(repo: repo, number: node["number"])

    names = people_names(node)
    people = ReviewPeople.new(names: names, users: @users)
    team = ->(login, association) { TEAM_ASSOCIATIONS.include?(association.to_s) || people.team?(login) }

    author = node.dig("author", "login").to_s.presence || "ghost"
    opened_at = time(node["createdAt"])
    comments = Array(node.dig("comments", "nodes")).filter_map do |c|
      login = c.dig("author", "login")
      next if login.blank? || bot?(c["author"])
      { "login" => login, "team" => team.call(login, c["authorAssociation"]), "at" => c["createdAt"] }
    end
    verdict = IssueClassifier.classify(
      author_team: team.call(author, node["authorAssociation"]), opened_at: opened_at, comments: comments
    )

    issue.update!(
      repo: repo,
      title: node["title"].to_s,
      url: node["url"].to_s,
      author: author,
      author_association: node["authorAssociation"],
      opened_at: opened_at,
      github_updated_at: time(node["updatedAt"]),
      labels: Array(node.dig("labels", "nodes")).filter_map { |l| l["name"] },
      assignees: Array(node.dig("assignees", "nodes")).filter_map { |a| a["login"] },
      comments: comments,
      comment_count: node.dig("comments", "totalCount").to_i,
      people_names: names,
      stage: verdict.stage,
      waiting_on: verdict.waiting_on,
      waiting_since: verdict.waiting_since
    )
    @changed = true if issue.saved_changes?
    issue
  end

  def bot?(actor) = actor["__typename"] == "Bot" || actor["login"].to_s.end_with?("[bot]")

  # login => the name on the GitHub profile, for ReviewPeople.
  def people_names(node)
    actors = [ node["author"] ] + Array(node.dig("assignees", "nodes")) +
             Array(node.dig("comments", "nodes")).map { |c| c["author"] }
    actors.compact.each_with_object({}) do |a, h|
      h[a["login"]] = a["name"] if a["login"].present? && a["name"].present?
    end
  end

  # An issue snooze holds while the ball stays where it was when it was snoozed.
  def prune_snoozes!(now)
    states = GithubIssue.all.index_by { |i| i.key.downcase }
    dead = StaleSnooze.all.select do |s|
      next false unless GithubKeyed.key?(s.jira_key)
      next false if ReviewPullRequest.find_by_key(s.jira_key) # ReviewSync looks after those
      issue = states[s.jira_key.downcase]
      s.snoozed_until <= now || issue.nil? || issue.snooze_state != s.jira_status
    end
    return if dead.empty?
    StaleSnooze.where(id: dead.map(&:id)).delete_all
    @changed = true
  end

  # A refresh resets nothing any more, but there is no point sending one when
  # nothing changed. Once an hour anyway, so the waiting days keep counting up.
  def broadcast
    BoardBroadcasts.issues
    BoardBroadcasts.board # the red count on the Issues tab
  end

  def hour_turned?(previous, now)
    previous.nil? || previous.started_at.beginning_of_hour != now.beginning_of_hour
  end

  def time(v) = v.present? ? Time.zone.parse(v.to_s) : nil
end
