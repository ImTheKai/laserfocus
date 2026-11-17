require "test_helper"

class IssueClassifierTest < ActiveSupport::TestCase
  OPENED = Time.zone.parse("2026-11-01 10:00")

  def classify(author_team: false, comments: [])
    IssueClassifier.classify(author_team: author_team, opened_at: OPENED, comments: comments)
  end

  def c(team, days) = { "login" => team ? "us" : "them", "team" => team, "at" => (OPENED + days.days).iso8601 }

  test "an outside issue nobody on the team answered is new, waiting since it was opened" do
    r = classify(comments: [ c(false, 1), c(false, 2) ])
    assert_equal [ "new", "team", OPENED ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "the team had the last word: waiting on the reporter since then" do
    r = classify(comments: [ c(false, 1), c(true, 3) ])
    assert_equal [ "reporter", "reporter", OPENED + 3.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "someone outside spoke after the team: waiting on us since the first of them" do
    r = classify(comments: [ c(true, 1), c(false, 4), c(false, 6) ])
    assert_equal [ "us", "team", OPENED + 4.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end

  test "a team issue is backlog since the last word, until someone outside asks something" do
    r = classify(author_team: true, comments: [ c(true, 2) ])
    assert_equal [ "backlog", "team", OPENED + 2.days ], [ r.stage, r.waiting_on, r.waiting_since ]
    assert_equal OPENED, classify(author_team: true).waiting_since

    r = classify(author_team: true, comments: [ c(true, 2), c(false, 5) ])
    assert_equal [ "us", "team", OPENED + 5.days ], [ r.stage, r.waiting_on, r.waiting_since ]
  end
end
