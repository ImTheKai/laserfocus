# Mirrors the open, ready-for-review PRs of the configured repos into
# review_pull_requests. Runs on the same tick as JiraSync, but on its own: a
# GitHub failure is recorded in ReviewSyncRun and never touches the Jira data.
class ReviewSync
  JIRA_KEY = /\b([A-Z][A-Z0-9]+-\d+)\b/
  CI_STATES = {
    "SUCCESS" => "ok", "FAILURE" => "fail", "ERROR" => "fail",
    "PENDING" => "pending", "EXPECTED" => "pending"
  }.freeze

  def self.configured? = LASER_FOCUS_CONFIG.reviews.present? && LASER_FOCUS_CONFIG.reviews.repos.any?

  def initialize(config: LASER_FOCUS_CONFIG.reviews, client: GithubClient.new)
    @config = config
    @client = client
  end

  def run!(now: Time.current)
    previous = ReviewSyncRun.pulls.ok.most_recent.first
    run = ReviewSyncRun.create!(kind: "pulls", started_at: now)
    @changed = false
    nodes = @client.open_ready_pull_requests(@config.repos)
    excluded = @config.exclude_authors

    seen_ids = []
    nodes.each do |node|
      next if node["isDraft"]
      next if excluded.include?(node.dig("author", "login").to_s.downcase)
      seen_ids << upsert(node).id
    end
    # Merged, closed, turned back into a draft, or from a repo no longer listed.
    @changed = true if ReviewPullRequest.where.not(id: seen_ids).delete_all.positive?
    prune_snoozes!(now)

    run.update!(finished_at: Time.current, ok: true, fetched_count: seen_ids.size)
    broadcast if @changed || hour_turned?(previous, now)
    run
  rescue => e
    Rails.logger.warn("[ReviewSync] failed: #{e.class}: #{e.message}")
    run&.update!(finished_at: Time.current, ok: false, error_message: e.message.to_s.first(500))
    run
  end

  private

  def upsert(node)
    repo = node.dig("repository", "nameWithOwner").to_s
    pr = ReviewPullRequest.where("lower(repo) = ?", repo.downcase).find_by(number: node["number"]) ||
         ReviewPullRequest.new(repo: repo, number: node["number"])

    opened_at = time(node["createdAt"])
    ready_at = time(node.dig("ready", "nodes", 0, "createdAt"))
    commit = node.dig("commits", "nodes", 0, "commit") || {}
    last_push_at = [ time(commit["committedDate"]), time(node.dig("forcePushes", "nodes", 0, "createdAt")) ].compact.max
    author = node.dig("author", "login").to_s.presence || "ghost"
    reviews = Array(node.dig("latestReviews", "nodes")).filter_map do |r|
      login = r.dig("author", "login")
      next unless login
      { "login" => login, "state" => r["state"], "submitted_at" => r["submittedAt"] }
    end
    verdict = ReviewClassifier.classify(
      author: author, opened_at: opened_at, ready_at: ready_at, last_push_at: last_push_at,
      review_decision: node["reviewDecision"], reviews: reviews
    )

    pr.update!(
      repo: repo,
      title: node["title"].to_s,
      url: node["url"].to_s,
      author: author,
      author_association: node["authorAssociation"],
      head_ref: node["headRefName"],
      opened_at: opened_at,
      ready_at: ready_at,
      last_push_at: last_push_at,
      github_updated_at: time(node["updatedAt"]),
      review_decision: node["reviewDecision"],
      ci_state: CI_STATES[commit.dig("statusCheckRollup", "state").to_s],
      additions: node["additions"].to_i,
      deletions: node["deletions"].to_i,
      labels: Array(node.dig("labels", "nodes")).filter_map { |l| l["name"] },
      reviews: reviews,
      requested_reviewers: Array(node.dig("reviewRequests", "nodes")).filter_map do |r|
        rr = r["requestedReviewer"] || {}
        rr["login"] || (rr["slug"] && "@#{rr["slug"]}")
      end,
      jira_keys: "#{node["title"]} #{node["headRefName"]}".scan(JIRA_KEY).flatten.uniq,
      people_names: people_names(node),
      stage: verdict.stage,
      waiting_on: verdict.waiting_on,
      waiting_since: verdict.waiting_since
    )
    @changed = true if pr.saved_changes?
    pr
  end

  # A refresh resets whatever the reader is doing, so only send one when the
  # PRs changed, or once an hour so the waiting days keep counting up.
  def broadcast
    BoardBroadcasts.reviews
    BoardBroadcasts.board # the red count on the Reviews tab
  end

  def hour_turned?(previous, now)
    previous.nil? || previous.started_at.beginning_of_hour != now.beginning_of_hour
  end

  # login => the name on the GitHub profile, for everyone on the PR who set
  # one. ReviewPeople matches these against the Jira display names.
  def people_names(node)
    actors = [ node["author"] ] +
             Array(node.dig("latestReviews", "nodes")).map { |r| r["author"] } +
             Array(node.dig("reviewRequests", "nodes")).map { |r| r["requestedReviewer"] }
    actors.compact.each_with_object({}) do |a, h|
      h[a["login"]] = a["name"] if a["login"].present? && a["name"].present?
    end
  end

  # A PR snooze holds while the ball stays where it was when it was snoozed.
  def prune_snoozes!(now)
    states = ReviewPullRequest.all.index_by { |pr| pr.key.downcase }
    dead = StaleSnooze.all.select do |s|
      next false unless ReviewPullRequest.snooze_key?(s.jira_key)
      next false if GithubIssue.find_by_key(s.jira_key) # IssueSync looks after those
      pr = states[s.jira_key.downcase]
      s.snoozed_until <= now || pr.nil? || pr.snooze_state != s.jira_status
    end
    return if dead.empty?
    StaleSnooze.where(id: dead.map(&:id)).delete_all
    @changed = true
  end

  def time(v) = v.present? ? Time.zone.parse(v.to_s) : nil
end
