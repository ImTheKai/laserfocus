require "test_helper"

class ReviewClassifierTest < ActiveSupport::TestCase
  T0 = Time.zone.parse("2026-11-01 10:00")

  def classify(reviews: [], decision: nil, ready_at: nil, last_push_at: nil)
    ReviewClassifier.classify(author: "bob", opened_at: T0, ready_at: ready_at, last_push_at: last_push_at,
                              review_decision: decision, reviews: reviews)
  end

  def review(login, state, at) = { "login" => login, "state" => state, "submitted_at" => at.iso8601 }

  test "without reviews it needs review, on reviewers since it was opened" do
    r = classify
    assert_equal [ "needs", "reviewers", T0 ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "the clock starts when a draft was marked ready" do
    assert_equal T0 + 3.days, classify(ready_at: T0 + 3.days).waiting_since
  end

  test "the author's own comments do not count as a review" do
    assert_equal "needs", classify(reviews: [ review("bob", "COMMENTED", T0 + 1.day) ]).stage
  end

  test "comments without a verdict are a discussion waiting on the author" do
    r = classify(reviews: [ review("ann", "COMMENTED", T0 + 2.days) ])
    assert_equal [ "discuss", "author", T0 + 2.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "a push after the last review hands a discussion back to reviewers" do
    r = classify(reviews: [ review("ann", "COMMENTED", T0 + 2.days) ], last_push_at: T0 + 3.days)
    assert_equal [ "discuss", "reviewers", T0 + 3.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "requested changes wait on the author since the request" do
    r = classify(reviews: [ review("ann", "CHANGES_REQUESTED", T0 + 2.days), review("cid", "APPROVED", T0 + 1.day) ],
                 decision: "CHANGES_REQUESTED")
    assert_equal [ "changes", "author", T0 + 2.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "a push after requested changes puts the ball back with reviewers" do
    r = classify(reviews: [ review("ann", "CHANGES_REQUESTED", T0 + 2.days) ], last_push_at: T0 + 4.days)
    assert_equal [ "changes", "reviewers", T0 + 4.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "approved waits on a merge since the latest approval" do
    r = classify(reviews: [ review("ann", "APPROVED", T0 + 2.days), review("cid", "COMMENTED", T0 + 5.days) ],
                 decision: "APPROVED")
    assert_equal [ "approved", "merge", T0 + 2.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "an approval counts on repos without branch protection" do
    assert_equal "approved", classify(reviews: [ review("ann", "APPROVED", T0 + 1.day) ]).stage
  end

  test "an approval that is not enough yet stays in discussion" do
    r = classify(reviews: [ review("ann", "APPROVED", T0 + 1.day) ], decision: "REVIEW_REQUIRED")
    assert_equal "discuss", r.stage
  end

  test "dismissed and pending reviews are ignored" do
    reviews = [ review("ann", "DISMISSED", T0 + 1.day), review("cid", "PENDING", T0 + 1.day) ]
    assert_equal "needs", classify(reviews: reviews).stage
  end
end
