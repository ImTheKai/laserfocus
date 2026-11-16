module ReviewsHelper
  WAITING_TAG = {
    "needs" => [ "on reviewers", "kb-col-tag-reviewers" ],
    "discuss" => [ "back and forth", nil ],
    "changes" => [ "on the author", "kb-col-tag-author" ],
    "approved" => [ "ready to merge", "kb-col-tag-merge" ]
  }.freeze
  REVIEW_STATE_WORD = {
    "APPROVED" => "approved", "CHANGES_REQUESTED" => "changes requested", "COMMENTED" => "commented"
  }.freeze
  CI_WORD = { "ok" => "passing", "fail" => "failing", "pending" => "running" }.freeze

  # The board.users display name for a GitHub login, else the login itself.
  def github_person(login)
    @github_people ||= LASER_FOCUS_CONFIG.board.users
                         .select { |u| u.github.present? }
                         .to_h { |u| [ u.github.to_s.downcase, u.display_name.presence || u.github ] }
    @github_people[login.to_s.downcase] || login.to_s
  end

  def github_avatar(login, size:)
    av = avatar_for(github_person(login))
    tag.span(av[:initials], class: "kb-avatar",
             style: "background:#{av[:color]};width:#{size}px;height:#{size}px;font-size:#{(size * 0.42).round(1)}px;",
             title: github_person(login))
  end

  def review_waiting_tag(stage_id) = WAITING_TAG.fetch(stage_id)

  def ci_icon_svg(state)
    case state
    when "ok"
      %(<svg width="12" height="12" viewBox="0 0 12 12" role="img" aria-label="CI passing"><circle cx="6" cy="6" r="5.5" fill="#22c55e"/><path d="M3.4 6.2l1.8 1.8 3.4-3.6" stroke="#fff" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>).html_safe
    when "fail"
      %(<svg width="12" height="12" viewBox="0 0 12 12" role="img" aria-label="CI failing"><circle cx="6" cy="6" r="5.5" fill="#ef4444"/><path d="M4 4l4 4M8 4l-4 4" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/></svg>).html_safe
    when "pending"
      %(<svg width="12" height="12" viewBox="0 0 12 12" role="img" aria-label="CI running"><circle cx="6" cy="6" r="5" fill="none" stroke="#eab308" stroke-width="1.6" stroke-dasharray="3 2"/><circle cx="6" cy="6" r="1.8" fill="#eab308"/></svg>).html_safe
    end
  end

  def decision_flag_svg
    %(<svg width="9" height="9" viewBox="0 0 10 10" fill="currentColor" aria-hidden="true"><path d="M2 1h1v8H2zM3 1.5h5L6.6 3.6 8 5.7H3z"/></svg>).html_safe
  end

  # Reviewer avatars carry a small mark: approved, changes requested or
  # commented. Requested-but-not-given shows as a faded, ringed avatar.
  def reviewer_marks(card)
    pr = card.pr
    given = pr.review_list.map { |r| [ r["login"], r["state"] ] }
    asked = pr.requested_list.reject { |l| given.any? { |g, _| g.casecmp?(l) } }.map { |l| [ l, "REQUESTED" ] }
    given + asked
  end

  def review_tooltip(card, presenter)
    pr = card.pr
    reviews = reviewer_marks(card).map do |login, state|
      "#{github_person(login)} (#{REVIEW_STATE_WORD[state] || "requested"})"
    end
    {
      id: "#{pr.repo}##{pr.number}",
      title: pr.title,
      stage: ReviewsPresenter::STAGES.find { |s| s[:id] == pr.stage }&.dig(:label),
      color: ReviewsPresenter::STAGES.find { |s| s[:id] == pr.stage }&.dig(:color),
      author: github_person(pr.author) + (pr.community? ? (pr.first_time_contributor? ? " · first-time contributor" : " · community") : ""),
      waiting: "#{card.days} #{card.days == 1 ? "day" : "days"} on #{presenter.waiting_label(pr.waiting_on)}",
      stale: staleness_label(card.staleness),
      open: "#{card.age_days} #{card.age_days == 1 ? "day" : "days"}",
      decision: card.decision? ? "Open #{card.age_days} days: merge it, close it, or snooze it with the reason it stays open" : nil,
      reviews: reviews.any? ? reviews.join(", ") : "nobody yet",
      ci: CI_WORD[pr.ci_state] || "no checks",
      size: "+#{pr.additions} −#{pr.deletions}",
      jira: pr.jira_key_list.join(", ").presence,
      labels: pr.label_list.join(", ").presence,
      snooze: card.snooze ? snooze_summary(card.snooze) : nil,
      snoozable: card.snoozable?
    }.compact
  end
end
