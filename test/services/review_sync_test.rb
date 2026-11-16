require "test_helper"

class ReviewSyncTest < ActiveSupport::TestCase
  include ReviewPrFactory

  class FakeClient
    attr_reader :asked_for
    def initialize(nodes = [], error: nil) = (@nodes, @error = nodes, error)
    def open_ready_pull_requests(repos)
      @asked_for = repos
      raise @error if @error
      @nodes
    end
  end

  def node(number:, repo: "acme/server", author: "bob-gh", draft: false, reviews: [], decision: nil, **extra)
    {
      "number" => number, "title" => extra[:title] || "PG-12: fix #{number}", "url" => "https://github.com/#{repo}/pull/#{number}",
      "isDraft" => draft, "createdAt" => "2026-11-01T10:00:00Z", "updatedAt" => "2026-11-05T10:00:00Z",
      "additions" => 10, "deletions" => 2, "headRefName" => extra[:branch] || "fix-#{number}",
      "authorAssociation" => extra[:association] || "MEMBER", "reviewDecision" => decision,
      "repository" => { "nameWithOwner" => repo }, "author" => { "login" => author },
      "labels" => { "nodes" => [ { "name" => "bug" } ] },
      "reviewRequests" => { "nodes" => [ { "requestedReviewer" => { "login" => "ann-gh" } }, { "requestedReviewer" => { "slug" => "core" } } ] },
      "latestReviews" => { "nodes" => reviews },
      "commits" => { "nodes" => [ { "commit" => { "committedDate" => "2026-11-01T09:00:00Z", "statusCheckRollup" => { "state" => extra[:ci] || "FAILURE" } } } ] },
      "ready" => { "nodes" => extra[:ready_at] ? [ { "createdAt" => extra[:ready_at] } ] : [] },
      "forcePushes" => { "nodes" => [] }
    }
  end

  def sync(client) = ReviewSync.new(config: LASER_FOCUS_CONFIG.reviews, client: client).run!

  test "stores open ready PRs with stage, clock and details" do
    run = sync(FakeClient.new([ node(number: 7, ready_at: "2026-11-02T10:00:00Z") ]))

    assert run.ok
    pr = ReviewPullRequest.find_by!(repo: "acme/server", number: 7)
    assert_equal "needs", pr.stage
    assert_equal "reviewers", pr.waiting_on
    assert_equal Time.zone.parse("2026-11-02T10:00:00Z"), pr.waiting_since
    assert_equal "fail", pr.ci_state
    assert_equal [ "ann-gh", "@core" ], pr.requested_reviewers
    assert_equal [ "PG-12" ], pr.jira_keys
    assert_equal [ "bug" ], pr.labels
  end

  test "asks GitHub for the configured repos" do
    client = FakeClient.new
    sync(client)
    assert_equal [ "acme/server", "acme/docs" ], client.asked_for
  end

  test "drafts and excluded authors never show" do
    sync(FakeClient.new([ node(number: 1, draft: true), node(number: 2, author: "dependabot[bot]"), node(number: 3) ]))
    assert_equal [ 3 ], ReviewPullRequest.pluck(:number)
  end

  test "PRs no longer returned are dropped" do
    create_review_pr(number: 99)
    sync(FakeClient.new([ node(number: 1) ]))
    assert_equal [ 1 ], ReviewPullRequest.pluck(:number)
  end

  test "updates an existing PR in place" do
    sync(FakeClient.new([ node(number: 1) ]))
    approved = node(number: 1, decision: "APPROVED",
                    reviews: [ { "author" => { "login" => "ann-gh" }, "state" => "APPROVED", "submittedAt" => "2026-11-03T10:00:00Z" } ])
    sync(FakeClient.new([ approved ]))
    assert_equal 1, ReviewPullRequest.count
    assert_equal "approved", ReviewPullRequest.first.stage
  end

  test "a failure is recorded and keeps the PRs from the run before" do
    create_review_pr(number: 5)
    run = sync(FakeClient.new(error: GithubClient::Error.new("GitHub answered 502")))
    assert_not run.ok
    assert_match "502", run.error_message
    assert_equal [ 5 ], ReviewPullRequest.pluck(:number)
  end

  test "drops PR snoozes once the ball moved, keeps ticket snoozes alone" do
    sync(FakeClient.new([ node(number: 1), node(number: 2) ]))
    one, two = ReviewPullRequest.order(:number).to_a
    StaleSnooze.create!(jira_key: one.key, jira_status: one.snooze_state, snoozed_until: 3.days.from_now, snoozed_by: "A")
    StaleSnooze.create!(jira_key: two.key, jira_status: "needs:reviewers:0", snoozed_until: 3.days.from_now, snoozed_by: "A")
    StaleSnooze.create!(jira_key: "PG-1", jira_status: "In Review", snoozed_until: 3.days.from_now, snoozed_by: "A")

    sync(FakeClient.new([ node(number: 1), node(number: 2) ]))

    assert_equal [ one.key, "PG-1" ].sort, StaleSnooze.pluck(:jira_key).sort
  end
end
