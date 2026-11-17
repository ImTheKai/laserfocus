module GithubIssuesHelper
  def comment_icon_svg
    %(<svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" aria-hidden="true"><path d="M2 2.5h8v5.5H5.5L3 10V8H2z"/></svg>).html_safe
  end

  def issue_tooltip(card, presenter)
    issue = card.issue
    stage = IssuesPresenter::STAGES.find { |s| s[:id] == issue.stage }
    last = issue.last_comment
    last_at = last && Time.zone.parse(last["at"].to_s)
    {
      id: "#{issue.repo}##{issue.number}",
      title: issue.title,
      stage: stage&.dig(:label),
      color: stage&.dig(:color),
      author: github_person(issue.author) + (issue.community? ? (issue.first_time_contributor? ? " · first-time contributor" : " · community") : ""),
      waiting: "#{card.days} #{card.days == 1 ? "day" : "days"} on #{presenter.waiting_label(issue.waiting_on)}",
      stale: staleness_label(card.staleness),
      open: "#{card.age_days} #{card.age_days == 1 ? "day" : "days"}",
      decision: card.decision? ? "Open #{card.age_days} days: fix it, close it, or snooze it with the reason it stays open" : nil,
      lastword: last_at ? "#{github_person(last["login"])}#{" (team)" if last["team"]}, #{time_ago_in_words(last_at)} ago" : "nobody yet",
      comments: issue.comment_count.to_s,
      assigned: issue.assignee_list.map { |l| github_person(l) }.join(", ").presence || "nobody",
      labels: issue.label_list.join(", ").presence,
      snooze: card.snooze ? snooze_summary(card.snooze) : nil,
      snoozable: card.snoozable?
    }.compact
  end
end
