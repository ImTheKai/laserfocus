require "test_helper"

class GithubIssuesControllerTest < ActionDispatch::IntegrationTest
  include GithubIssueFactory

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    get "/auth/google_oauth2/callback"
  end

  test "requires login" do
    reset!
    get "/issues"
    assert_redirected_to "/login"
  end

  test "renders the columns with issue cards" do
    freeze_time do
      ReviewSyncRun.create!(kind: "issues", started_at: 1.minute.ago, finished_at: 1.minute.ago, ok: true)
      create_github_issue(number: 42, title: "Crash on start", waiting_since: 8.days.ago, opened_at: 100.days.ago,
                          author_association: "FIRST_TIME_CONTRIBUTOR", labels: [ "bug" ], assignees: [ "alice-gh" ],
                          comment_count: 3, comments: [ { "login" => "x9", "team" => false, "at" => 9.days.ago.iso8601 } ])
      create_github_issue(number: 7, stage: "reporter", waiting_on: "reporter", waiting_since: 1.day.ago)

      get "/issues"

      assert_response :success
      assert_select ".kb-reviews-col", 4
      assert_select "#kb-issues-new .kb-col-name", text: "New"
      assert_select "#kb-issues-new .kb-issue-card[data-staleness='really'][data-decision='1'][data-snooze-key='acme/server#42']"
      assert_select "#kb-issues-new .kb-issue-card[data-requested='alice-gh'][data-replied='x9'][data-needs-me='1']"
      assert_select "#kb-issues-new .kb-issue-label", text: "bug"
      assert_select "#kb-issues-new .kb-pr-chip-community", text: /first issue/
      assert_select "#kb-issues-reporter .kb-issue-card", 1
      assert_select ".kb-shell[data-reviews-viewer-value='alice-gh']"
      assert_select ".kb-view-tabs a[href='/issues'][data-on='1']", text: /Issues/
      assert_select ".kb-view-tabs a[href='/issues'] .kb-tab-badge", text: "1"
      assert_select "input.kb-search[placeholder='Search issues…']"
      assert_select ".kb-seg button[data-role='requested']", text: "Assigned"
    end
  end

  test "says when the last sync failed" do
    ReviewSyncRun.create!(kind: "issues", started_at: 2.minutes.ago, finished_at: 2.minutes.ago, ok: false, error_message: "boom")
    ReviewSyncRun.create!(kind: "pulls", started_at: 1.minute.ago, finished_at: 1.minute.ago, ok: true)
    ENV["GITHUB_TOKEN"] = "x"
    get "/issues"
    assert_select ".kb-reviews-notice[data-tone='warn']", text: /issues are from the sync before/
  ensure
    ENV.delete("GITHUB_TOKEN")
  end
end
