require "test_helper"
require "turbo/broadcastable/test_helper"

class IssueSyncTest < ActiveSupport::TestCase
  include GithubIssueFactory
  include Turbo::Broadcastable::TestHelper

  class FakeClient
    attr_reader :asked_for
    def initialize(nodes = [], error: nil) = (@nodes, @error = nodes, error)
    def open_issues(repos)
      @asked_for = repos
      raise @error if @error
      @nodes
    end
  end

  def comment(login, association, at, name: nil, type: "User")
    { "createdAt" => at, "authorAssociation" => association, "author" => { "login" => login, "__typename" => type, "name" => name }.compact }
  end

  def node(number:, repo: "acme/server", author: "reporter", association: "NONE", comments: [], **extra)
    {
      "number" => number, "title" => extra[:title] || "Crash on #{number}", "url" => "https://github.com/#{repo}/issues/#{number}",
      "createdAt" => "2026-11-01T10:00:00Z", "updatedAt" => "2026-11-05T10:00:00Z", "authorAssociation" => association,
      "repository" => { "nameWithOwner" => repo }, "author" => { "login" => author, "__typename" => "User", "name" => "Rita Reporter" },
      "labels" => { "nodes" => [ { "name" => "bug" } ] },
      "assignees" => { "nodes" => Array(extra[:assignees]).map { |l| { "login" => l } } },
      "comments" => { "totalCount" => comments.size, "nodes" => comments }
    }
  end

  def sync(client, now: Time.current) = IssueSync.new(client: client).run!(now: now)

  test "stores open issues with who they wait on" do
    run = sync(FakeClient.new([ node(number: 5, assignees: [ "alice-gh" ],
                                     comments: [ comment("someone", "MEMBER", "2026-11-02T10:00:00Z") ]) ]))
    assert run.ok
    assert_equal "issues", run.kind
    issue = GithubIssue.find_by!(repo: "acme/server", number: 5)
    assert_equal [ "reporter", "reporter" ], [ issue.stage, issue.waiting_on ]
    assert_equal Time.zone.parse("2026-11-02T10:00:00Z"), issue.waiting_since
    assert_equal [ "alice-gh" ], issue.assignees
    assert_equal [ "bug" ], issue.labels
    assert_equal 1, issue.comment_count
    assert_equal({ "reporter" => "Rita Reporter" }, issue.people_names)
  end

  test "asks GitHub for the configured repos, which default to the reviews repos" do
    client = FakeClient.new
    sync(client)
    assert_equal LASER_FOCUS_CONFIG.reviews.repos, client.asked_for
  end

  test "board.users count as the team even when GitHub calls them a contributor; bots never count" do
    nodes = [
      node(number: 1, comments: [ comment("alice-gh", "CONTRIBUTOR", "2026-11-02T10:00:00Z") ]),
      node(number: 2, comments: [ comment("someone", "CONTRIBUTOR", "2026-11-02T10:00:00Z", name: "Bob") ]),
      node(number: 3, comments: [ comment("ex-member", "CONTRIBUTOR", "2026-11-02T10:00:00Z") ]),
      node(number: 4, comments: [ comment("github-actions", "NONE", "2026-11-02T10:00:00Z", type: "Bot") ])
    ]
    sync(FakeClient.new(nodes))
    stages = GithubIssue.order(:number).pluck(:stage)
    assert_equal %w[reporter reporter new new], stages
    assert_empty GithubIssue.find_by!(number: 4).comments
  end

  test "excluded authors never show, closed issues are dropped" do
    create_github_issue(number: 99)
    sync(FakeClient.new([ node(number: 1), node(number: 2, author: "dependabot[bot]") ]))
    assert_equal [ 1 ], GithubIssue.pluck(:number)
  end

  test "a failure is recorded and keeps the issues from the run before" do
    create_github_issue(number: 7)
    run = sync(FakeClient.new(error: GithubClient::Error.new("boom")))
    refute run.ok
    assert_equal "boom", run.error_message
    assert_equal 1, GithubIssue.count
  end

  test "refreshes the Issues view only when the issues changed, or once an hour" do
    now = Time.zone.parse("2026-11-17 10:05")
    refreshes = lambda do |nodes, at|
      pubsub_adapter.clear_messages("issues")
      sync(FakeClient.new(nodes), now: at)
      broadcasts("issues").size
    end
    assert_equal 1, refreshes.call([ node(number: 1) ], now)
    assert_equal 0, refreshes.call([ node(number: 1) ], now + 1.minute)
    assert_equal 1, refreshes.call([ node(number: 1, title: "New title") ], now + 2.minutes)
    assert_equal 1, refreshes.call([ node(number: 1, title: "New title") ], now + 1.hour)
  end

  test "drops issue snoozes once the ball moved, leaves PR snoozes to ReviewSync" do
    sync(FakeClient.new([ node(number: 1) ]))
    issue = GithubIssue.first
    StaleSnooze.create!(jira_key: issue.key, jira_status: issue.snooze_state, snoozed_until: 3.days.from_now, snoozed_by: "A")
    StaleSnooze.create!(jira_key: "acme/server#77", jira_status: "x", snoozed_until: 3.days.from_now, snoozed_by: "A")
    ReviewPullRequest.create!(repo: "acme/server", number: 77, title: "PR", url: "u", opened_at: 1.day.ago,
                              stage: "needs", waiting_on: "reviewers", waiting_since: 1.day.ago)

    sync(FakeClient.new([ node(number: 1) ]))
    assert_equal 2, StaleSnooze.count

    sync(FakeClient.new([ node(number: 1, comments: [ comment("someone", "MEMBER", "2026-11-02T10:00:00Z") ]) ]))
    assert_equal [ "acme/server#77" ], StaleSnooze.pluck(:jira_key)
  end
end
