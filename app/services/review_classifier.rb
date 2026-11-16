# Works out where an open PR stands and who it is waiting on, from what GitHub
# says about its reviews. The answer drives the Reviews view's columns and the
# clock behind the age chip:
#
#   needs    no review yet                    waits on reviewers since it was ready
#   discuss  comments, no verdict             waits on reviewers if the author pushed
#                                             after the last review, else on the author
#   changes  a reviewer asked for changes     waits on the author, or on reviewers
#                                             again once the author pushed
#   approved approved                         waits on whoever merges, since the approval
class ReviewClassifier
  Result = Struct.new(:stage, :waiting_on, :waiting_since, keyword_init: true)
  Review = Struct.new(:login, :state, :submitted_at, keyword_init: true)

  COUNTED_STATES = %w[APPROVED CHANGES_REQUESTED COMMENTED].freeze

  def self.classify(**kwargs) = new(**kwargs).result

  # reviews: GitHub's latest review per reviewer, as hashes with "login",
  # "state" and "submitted_at" (a Time or an ISO 8601 string).
  def initialize(author:, opened_at:, ready_at: nil, last_push_at: nil, review_decision: nil, reviews: [])
    @author = author.to_s.downcase
    @ready_at = ready_at || opened_at
    @last_push_at = last_push_at
    @decision = review_decision.to_s
    @reviews = reviews.filter_map { |r| normalize(r) }
                      .reject { |r| r.login.downcase == @author }
                      .select { |r| COUNTED_STATES.include?(r.state) && r.submitted_at }
  end

  def result
    changes = @reviews.select { |r| r.state == "CHANGES_REQUESTED" }
    approvals = @reviews.select { |r| r.state == "APPROVED" }

    if changes.any? || @decision == "CHANGES_REQUESTED"
      since = changes.map(&:submitted_at).max || last_review_at
      ball(:changes, since)
    elsif approved?(approvals)
      Result.new(stage: "approved", waiting_on: "merge", waiting_since: approvals.map(&:submitted_at).max || last_review_at)
    elsif @reviews.any?
      ball(:discuss, last_review_at)
    else
      Result.new(stage: "needs", waiting_on: "reviewers", waiting_since: @ready_at)
    end
  end

  private

  # Approved when GitHub says so. Repos without branch protection report no
  # decision at all, so there any approval counts. REVIEW_REQUIRED with an
  # approval means more approvals are needed: still under discussion.
  def approved?(approvals)
    return true if @decision == "APPROVED"
    @decision.empty? && approvals.any?
  end

  # A push after the reviewer spoke hands the PR back to the reviewers.
  def ball(stage, reviewed_at)
    reviewed_at ||= @ready_at
    if @last_push_at && @last_push_at > reviewed_at
      Result.new(stage: stage.to_s, waiting_on: "reviewers", waiting_since: @last_push_at)
    else
      Result.new(stage: stage.to_s, waiting_on: "author", waiting_since: reviewed_at)
    end
  end

  def last_review_at = @reviews.map(&:submitted_at).max

  def normalize(raw)
    h = raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : {}
    login = h["login"].to_s
    return nil if login.empty?
    Review.new(login: login, state: h["state"].to_s, submitted_at: to_time(h["submitted_at"]))
  end

  def to_time(v)
    return v if v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone)
    v.present? ? Time.zone.parse(v.to_s) : nil
  rescue ArgumentError
    nil
  end
end
