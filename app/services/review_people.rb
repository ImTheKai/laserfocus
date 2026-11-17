# Who is who on the Reviews view. GitHub only gives logins; the team is known by
# its Jira display names in board.users. A login belongs to a team member when
# the member's github: override names it, or else when the name on the GitHub
# profile matches the display name (ignoring case, accents and extra spaces).
class ReviewPeople
  def self.normalize(name) = I18n.transliterate(name.to_s).downcase.squish

  # names: login => GitHub profile name, as collected by ReviewSync.
  # viewer_names / viewer_github: the signed-in person, see GithubViewer. Any
  # of the names matching is enough (Google name, Jira name, from the email).
  def initialize(names: {}, users: LASER_FOCUS_CONFIG.board.users, viewer_names: [], viewer_name: nil, viewer_github: nil)
    @names = names.each_with_object({}) { |(login, name), h| h[login.to_s.downcase] = name.to_s }
    @users = users
    @by_github = users.select { |u| u.github.present? }.index_by { |u| u.github.to_s.downcase }
    @by_name = users.select { |u| u.display_name.present? }.index_by { |u| self.class.normalize(u.display_name) }
    @viewer_names = (Array(viewer_names) + [ viewer_name ]).map { |n| self.class.normalize(n) }.compact_blank.uniq
    @viewer_github = viewer_github.to_s.downcase.presence
  end

  def self.from_prs(prs, **kwargs)
    names = prs.each_with_object({}) { |pr, h| h.merge!(pr.people_name_map) }
    new(names: names, **kwargs)
  end

  # The board.users entry behind a login, or nil for someone outside the team.
  def member(login)
    key = login.to_s.downcase
    @by_github[key] || (name = @names[key]).presence && @by_name[self.class.normalize(name)]
  end

  def team?(login) = member(login).present?

  # Jira display name for the team, the GitHub profile name for everyone else,
  # the login when GitHub has no name either.
  def display(login)
    member(login)&.display_name.presence || @names[login.to_s.downcase].presence || login.to_s
  end

  # Team members none of the given logins resolved to: either nothing of theirs
  # is open, or their GitHub name differs from Jira and needs a github: entry.
  def unmatched_members(logins)
    matched = logins.filter_map { |l| member(l) }
    @users.reject { |u| matched.include?(u) }
  end

  def viewer? = @viewer_names.any? || @viewer_github.present?
  def viewer_github? = @viewer_github.present?

  def me?(login)
    key = login.to_s.downcase
    return true if @viewer_github && key == @viewer_github
    return false if @viewer_names.empty?
    m = member(login)
    candidates = [ m&.display_name, @names[key] ].compact_blank.map { |n| self.class.normalize(n) }
    candidates.intersect?(@viewer_names)
  end
end
