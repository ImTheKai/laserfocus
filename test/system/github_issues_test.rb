require "application_system_test_case"

class GithubIssuesSystemTest < ApplicationSystemTestCase
  include GithubIssueFactory

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice Adams" }
    )
    StaleSnooze.delete_all
    create_github_issue(repo: "acme/server", number: 11, waiting_since: 9.days.ago, assignees: [ "alice-gh" ])
    create_github_issue(repo: "acme/docs", number: 12, stage: "reporter", waiting_on: "reporter", waiting_since: 20.days.ago,
                        comments: [ { "login" => "bobby", "team" => true, "at" => 20.days.ago.iso8601 } ])
    visit "/auth/google_oauth2/callback"
    visit "/issues"
    assert_selector ".kb-issue-card", count: 2
  end

  test "Mine and Needs me keep the viewer's issues" do
    click_button "Needs me"
    assert_selector ".kb-issue-card", count: 1
    assert_selector ".kb-issue-card[data-snooze-key='acme/server#11']"

    click_button "All"
    assert_selector ".kb-issue-card", count: 2
    click_button "Mine"
    assert_selector ".kb-issue-card", count: 1
    assert_selector ".kb-issue-card .kb-avatar-hit[data-login='alice-gh']"
  end

  test "the People filter matches commenters and assignees" do
    find("[data-reviews-target='peopleBtn']").click
    within(".kb-review-people") { find(".kb-people-row[data-login='bobby']").click }
    assert_selector ".kb-issue-card", count: 1
    assert_selector ".kb-issue-card[data-snooze-key='acme/docs#12']"

    within(".kb-review-people") { click_button "Assigned" }
    assert_selector ".kb-issue-card", count: 0
  end

  test "right-clicking a stale issue snoozes it" do
    find(".kb-issue-card[data-snooze-key='acme/server#11']").right_click
    within "#kb-snooze" do
      assert_text "acme/server#11 has been in New for"
      assert_text "until someone comments and the ball moves"
      click_button "Snooze #{LASER_FOCUS_CONFIG.board.snooze_days} days"
    end
    assert_selector ".kb-issue-card[data-snooze-key='acme/server#11'][data-staleness='snoozed']"
    assert StaleSnooze.exists?(jira_key: "acme/server#11")
  end
end
