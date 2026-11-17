# The signed-in person, for the Reviews and Issues views. ReviewPeople links
# them to a GitHub login by their board.users entry's github: override, or by
# any of their names matching a team member or a GitHub profile name: the name
# on their Google account, their board.users display name, and the name in
# their email address (jane.doe@... reads as "jane doe"), since the Google
# name is often spelled differently from Jira and GitHub.
module GithubViewer
  extend ActiveSupport::Concern

  private

  def viewer
    email = current_user_email.to_s.downcase
    google_name = session[:user_name].to_s.presence
    email_name = self.class.name_from_email(email)
    names = [ google_name, email_name ].compact
    users = LASER_FOCUS_CONFIG.board.users
    user = users.find { |u| u.email.present? && u.email.to_s.downcase == email } ||
           users.find { |u| names.any? { |n| ReviewPeople.normalize(u.display_name) == ReviewPeople.normalize(n) } }
    {
      names: [ user&.display_name.presence, *names ].compact.uniq,
      github: user&.github.presence,
      google_name: google_name,
      email: email.presence
    }
  end

  class_methods do
    # "jane.doe@example.com" => "jane doe"; nil for a one-word local part.
    def name_from_email(email)
      local = email.to_s.split("@", 2).first.to_s
      words = local.split(/[._-]+/).compact_blank
      words.size >= 2 ? words.join(" ") : nil
    end
  end
end
