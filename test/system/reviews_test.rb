require "application_system_test_case"

class ReviewsSystemTest < ApplicationSystemTestCase
  include ReviewPrFactory

  SERVER = ".kb-pr-card[data-snooze-key='acme/server#1']".freeze

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice Adams" }
    )
    StaleSnooze.delete_all
    create_review_pr(repo: "acme/server", number: 1, waiting_since: 9.days.ago)
    create_review_pr(repo: "acme/docs", number: 2, waiting_since: 9.days.ago, author: "outsider",
                     author_association: "FIRST_TIME_CONTRIBUTOR")
    visit "/auth/google_oauth2/callback"
    visit "/reviews"
    assert_selector ".kb-pr-card", count: 2
  end

  test "the repo filter hides the other repos' PRs and updates the count" do
    find("[data-reviews-target='repoBtn']").click
    find(".kb-filter-row[data-repo='acme/docs']").click

    assert_selector ".kb-pr-card", count: 1
    assert_selector "#kb-reviews-needs .kb-col-count", text: "1/2"
    assert_selector "[data-reviews-target='repoBadge']", text: "1"

    click_button "✕ Clear selection"
    assert_selector ".kb-pr-card", count: 2
  end

  test "the community toggle keeps only PRs from outside the org" do
    find(".kb-community-btn").click
    assert_selector ".kb-pr-card", count: 1
    assert_selector ".kb-pr-card .kb-pr-chip-community"
  end

  test "right-clicking a stale PR snoozes it" do
    find(SERVER).right_click
    within "#kb-snooze" do
      assert_text "acme/server#1 has been in Needs review for"
      assert_text "until the PR gets a new push or review"
      click_button "Snooze #{LASER_FOCUS_CONFIG.board.snooze_days} days"
    end

    assert_selector "#{SERVER}[data-staleness='snoozed']"
    assert StaleSnooze.exists?(jira_key: "acme/server#1")
  end
end
