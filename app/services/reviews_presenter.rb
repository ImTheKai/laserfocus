# Everything the Reviews view shows: the PRs grouped by review stage, each with
# its waiting clock, staleness, "decision needed" flag and snooze.
class ReviewsPresenter
  STAGES = [
    { id: "needs",    label: "Needs review",      color: "#8b5cf6", step: 0 },
    { id: "discuss",  label: "In discussion",     color: "#3b82f6", step: 1 },
    { id: "changes",  label: "Changes requested", color: "#ec4899", step: 1 },
    { id: "approved", label: "Approved",          color: "#22c55e", step: 2 }
  ].freeze
  WAITING_LABEL = { "reviewers" => "reviewers", "author" => "the author", "merge" => "whoever merges" }.freeze

  Card = Struct.new(:pr, :days, :age_days, :staleness, :decision, :snooze, :fresh_ready, keyword_init: true) do
    delegate :repo, :number, :key, :title, :author, :stage, :waiting_on, to: :pr
    def stale? = %i[somewhat really].include?(staleness)
    def snoozed? = staleness == :snoozed
    def decision? = decision
    # Right-click opens the snooze menu for these.
    def snoozable? = stale? || decision? || snoozed?
  end

  Column = Struct.new(:stage, :cards, keyword_init: true) do
    def id = stage[:id]
    def stale_count = cards.count(&:stale?)
    def snoozed_count = cards.count(&:snoozed?)
    def decision_count = cards.count(&:decision?)
  end

  # viewer: { name:, github: } for the signed-in person, see ReviewsController.
  def self.build(viewer: nil, now: Time.current)
    viewer ||= {}
    prs = ReviewPullRequest.all.to_a
    people = ReviewPeople.from_prs(prs, viewer_name: viewer[:name], viewer_github: viewer[:github])
    new(prs: prs, snoozes: StaleSnooze.running(now).to_a, people: people, now: now)
  end

  # Cheap enough for every page: the red count on the Reviews tab.
  def self.critical_count(now: Time.current)
    return 0 unless LASER_FOCUS_CONFIG.reviews
    build(now: now).cards.count { |c| c.staleness == :really }
  end

  attr_reader :people

  def initialize(prs:, snoozes: [], people: nil, now: Time.current,
                 config: LASER_FOCUS_CONFIG.reviews, lead: LASER_FOCUS_CONFIG.board.staleness_lead)
    @prs = prs
    @snoozes = snoozes.index_by { |s| s.jira_key.downcase }
    @people = people || ReviewPeople.from_prs(prs)
    @now = now
    @config = config
    @lead = lead
  end

  def cards
    @cards ||= @prs.map { |pr| card_for(pr) }
  end

  # Most stale first, like the board's Staleness mode; snoozed ones sink.
  def columns
    @columns ||= STAGES.map do |stage|
      list = cards.select { |c| c.stage == stage[:id] }
                  .sort_by { |c| [ c.snoozed? ? 1 : 0, -c.days, c.repo.downcase, c.number ] }
      Column.new(stage: stage, cards: list)
    end
  end

  def stale_count = cards.count(&:stale?)
  def snoozed_count = cards.count(&:snoozed?)
  def decision_count = cards.count(&:decision?)
  def community_count = cards.count { |c| c.pr.community? }

  def repos
    counts = cards.group_by { |c| c.repo.downcase }.transform_values(&:size)
    @config.repos.map { |r| [ r, counts.fetch(r.downcase, 0) ] }
  end

  # Everyone who wrote, replied to or is asked to review one of the PRs, for
  # the People filter: the team first, then everyone else, by display name.
  def logins
    @logins ||= cards.flat_map { |c| [ c.author, *c.pr.reviewer_logins ] }.compact
                     .reject { |l| l.start_with?("@") }.uniq(&:downcase)
  end

  def team_logins = logins.select { |l| @people.team?(l) }.sort_by { |l| @people.display(l).downcase }
  def outside_logins = logins.reject { |l| @people.team?(l) }.sort_by { |l| @people.display(l).downcase }
  def unmatched_members = @people.unmatched_members(logins)
  def no_reply_count = cards.count { |c| c.pr.no_reply? }

  # How many PRs a login wrote, replied to, and is asked to review.
  def involvement(login)
    prs = cards.map(&:pr)
    {
      wrote: prs.count { |pr| pr.author.to_s.casecmp?(login) },
      replied: prs.count { |pr| pr.replied_logins.any? { |l| l.casecmp?(login) } },
      asked: prs.count { |pr| pr.requested_list.any? { |l| l.casecmp?(login) } }
    }
  end

  def thresholds(waiting_on)
    if waiting_on == "author"
      [ @config.author_somewhat_days, @config.author_really_days ]
    else
      [ @config.somewhat_days, @config.really_days ]
    end
  end

  # Review requested from the viewer, or the viewer reviewed and the author has
  # pushed since.
  def needs_viewer?(card)
    pr = card.pr
    return false if @people.me?(pr.author)
    return true if pr.requested_list.any? { |l| @people.me?(l) }
    pr.waiting_on == "reviewers" && pr.review_list.any? { |r| @people.me?(r["login"]) }
  end

  # The viewer's GitHub login, so "Mine" matches exactly what ticking their
  # own name under People does. Nil until they show up on an open PR.
  def viewer_login
    return @viewer_login if defined?(@viewer_login)
    @viewer_login = logins.find { |l| @people.me?(l) }&.downcase
  end
  def viewer? = @people.viewer?

  def waiting_label(waiting_on) = WAITING_LABEL.fetch(waiting_on, waiting_on)

  private

  def card_for(pr)
    days = whole_days(pr.waiting_since)
    age_days = whole_days(pr.ready_at || pr.opened_at)
    somewhat, really = thresholds(pr.waiting_on)
    bucket = days >= really ? :really : days >= somewhat ? :somewhat : :fresh
    decision = age_days >= @config.decision_days
    snooze = @snoozes[pr.key.downcase]
    snooze = nil unless snooze && snooze.snoozed_until > @now && snooze.jira_status == pr.snooze_state
    snoozed = snooze && (bucket != :fresh || decision)
    Card.new(
      pr: pr, days: days, age_days: age_days,
      staleness: snoozed ? :snoozed : bucket,
      decision: decision && !snoozed,
      snooze: snoozed ? snooze : nil,
      fresh_ready: pr.stage == "needs" && (pr.ready_at || pr.opened_at) > @now - 1.day
    )
  end

  # Counts with the staleness lead, like days_in_state on the board, so a PR
  # looked at during standup is flagged again by the same standup days later.
  def whole_days(since)
    return 0 unless since
    [ ((@now - since + @lead) / 1.day).to_i, 0 ].max
  end
end
