require "test_helper"

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  include ReviewPrFactory

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
    get "/reviews"
    assert_redirected_to "/login"
  end

  test "renders the stage columns with PR cards" do
    freeze_time do
      ReviewSyncRun.create!(started_at: 1.minute.ago, finished_at: 1.minute.ago, ok: true)
      create_review_pr(number: 42, title: "PG-77 Fix the thing", jira_keys: [ "PG-77" ], waiting_since: 8.days.ago,
                       opened_at: 40.days.ago, author_association: "FIRST_TIME_CONTRIBUTOR")
      create_review_pr(number: 7, stage: "approved", waiting_on: "merge", waiting_since: 1.day.ago)

      get "/reviews"

      assert_response :success
      assert_select ".kb-reviews-col", 4
      assert_select "#kb-reviews-needs .kb-col-name", text: "Needs review"
      assert_select "#kb-reviews-needs .kb-pr-card[data-staleness='really'][data-decision='1']", 1
      assert_select "#kb-reviews-needs .kb-pr-card .kb-pr-chip-jira", text: "PG-77"
      assert_select "#kb-reviews-needs .kb-pr-card .kb-pr-chip-community", text: /first PR/
      assert_select "#kb-reviews-needs .kb-pr-card[data-snooze-key='acme/server#42']"
      assert_select "#kb-reviews-approved .kb-pr-card", 1
      assert_select "#kb-reviews-changes .kb-col-empty", text: /waiting on an author/
      assert_select ".kb-counts", text: /2 open/
    end
  end

  test "the Reviews tab is current and carries the critical count on every view" do
    create_review_pr(number: 1, waiting_since: 9.days.ago)

    get "/reviews"
    assert_select ".kb-view-tabs a[data-on='1']", text: /Reviews/
    assert_select ".kb-view-tabs .kb-tab-badge", text: "1"

    get "/next"
    assert_select ".kb-view-tabs a[href='/reviews'] .kb-tab-badge", text: "1"
  end

  test "maps the signed-in user to their github login for Needs me" do
    create_review_pr(number: 1, requested_reviewers: [ "alice-gh" ])
    get "/reviews"
    assert_select ".kb-scope-pills button[data-scope='me']:not([disabled])"
    assert_select ".kb-pr-card[data-needs-me='1']", 1
  end

  test "says so when the last GitHub sync failed" do
    ReviewSyncRun.create!(started_at: 2.minutes.ago, finished_at: 2.minutes.ago, ok: false, error_message: "boom")
    ENV["GITHUB_TOKEN"] = "x"
    get "/reviews"
    assert_select ".kb-reviews-notice[data-tone='warn']", text: /last GitHub sync failed/
  ensure
    ENV.delete("GITHUB_TOKEN")
  end

  test "asks for a token when none is set" do
    get "/reviews"
    assert_select ".kb-reviews-notice", text: /GITHUB_TOKEN/
  end
end
