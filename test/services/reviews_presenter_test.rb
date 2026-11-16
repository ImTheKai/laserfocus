require "test_helper"

class ReviewsPresenterTest < ActiveSupport::TestCase
  include ReviewPrFactory

  def card(pr, viewer: nil) = ReviewsPresenter.build(viewer: viewer).cards.find { |c| c.pr.id == pr.id }

  test "waiting on reviewers: stale after 3 days, critical after 7" do
    freeze_time do
      assert_equal :fresh, card(create_review_pr(number: 1, waiting_since: 2.days.ago)).staleness
      assert_equal :somewhat, card(create_review_pr(number: 2, waiting_since: 3.days.ago)).staleness
      assert_equal :really, card(create_review_pr(number: 3, waiting_since: 7.days.ago)).staleness
    end
  end

  test "thresholds fire an hour early, like tickets" do
    freeze_time do
      assert_equal :somewhat, card(create_review_pr(waiting_since: 3.days.ago + 30.minutes)).staleness
    end
  end

  test "waiting on the author uses the slower clock" do
    freeze_time do
      pr = create_review_pr(stage: "changes", waiting_on: "author", waiting_since: 8.days.ago)
      assert_equal :somewhat, card(pr).staleness
    end
  end

  test "open 30 days needs a decision, whatever the waiting clock says" do
    freeze_time do
      pr = create_review_pr(stage: "discuss", waiting_on: "author", waiting_since: 1.day.ago, opened_at: 31.days.ago)
      assert card(pr).decision?
      assert_not card(create_review_pr(number: 2, opened_at: 20.days.ago)).decision?
    end
  end

  test "a snooze quiets a stale PR and its decision flag while the ball stays put" do
    freeze_time do
      pr = create_review_pr(waiting_since: 40.days.ago)
      StaleSnooze.create!(jira_key: pr.key, jira_status: pr.snooze_state, snoozed_until: 3.days.from_now, snoozed_by: "Alice")
      c = card(pr)
      assert_equal :snoozed, c.staleness
      assert_not c.decision?

      pr.update!(waiting_since: 39.days.ago)
      assert_equal :really, card(pr).staleness
    end
  end

  test "columns follow the stages, most stale first" do
    old = create_review_pr(number: 1, waiting_since: 9.days.ago)
    young = create_review_pr(number: 2, waiting_since: 1.day.ago)
    create_review_pr(number: 3, stage: "approved", waiting_on: "merge")

    columns = ReviewsPresenter.build.columns
    assert_equal %w[needs discuss changes approved], columns.map(&:id)
    assert_equal [ old.id, young.id ], columns.first.cards.map { |c| c.pr.id }
    assert_equal 1, columns.last.cards.size
  end

  test "needs me: requested, or reviewed and the author pushed since" do
    requested = create_review_pr(number: 1, requested_reviewers: [ "Alice-GH" ])
    pushed = create_review_pr(number: 2, stage: "discuss", waiting_on: "reviewers",
                              reviews: [ { "login" => "alice-gh", "state" => "COMMENTED" } ])
    answered = create_review_pr(number: 3, stage: "discuss", waiting_on: "author",
                                reviews: [ { "login" => "alice-gh", "state" => "COMMENTED" } ])
    presenter = ReviewsPresenter.build(viewer: "alice-gh")
    by_id = presenter.cards.index_by { |c| c.pr.id }

    assert presenter.needs_viewer?(by_id[requested.id])
    assert presenter.needs_viewer?(by_id[pushed.id])
    assert_not presenter.needs_viewer?(by_id[answered.id])
  end

  test "counts critical PRs for the tab badge, not snoozed ones" do
    freeze_time do
      create_review_pr(number: 1, waiting_since: 8.days.ago)
      create_review_pr(number: 2, waiting_since: 4.days.ago)
      snoozed = create_review_pr(number: 3, waiting_since: 8.days.ago)
      StaleSnooze.create!(jira_key: snoozed.key, jira_status: snoozed.snooze_state, snoozed_until: 1.day.from_now, snoozed_by: "A")
      assert_equal 1, ReviewsPresenter.critical_count
    end
  end

  test "lists every configured repo with its count" do
    create_review_pr(repo: "acme/server", number: 1)
    assert_equal [ [ "acme/server", 1 ], [ "acme/docs", 0 ] ], ReviewsPresenter.build.repos
  end
end
