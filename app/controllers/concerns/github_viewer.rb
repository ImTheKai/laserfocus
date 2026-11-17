# The signed-in person, for the Reviews and Issues views: their board.users
# entry when one matches their email or name, else the name from their Google
# account. ReviewPeople finds their GitHub login by that name, or by the
# entry's github: override.
module GithubViewer
  extend ActiveSupport::Concern

  private

  def viewer
    email = current_user_email.to_s.downcase
    name = session[:user_name].to_s
    user = LASER_FOCUS_CONFIG.board.users.find { |u| u.email.present? && u.email.to_s.downcase == email } ||
           LASER_FOCUS_CONFIG.board.users.find { |u| name.present? && ReviewPeople.normalize(u.display_name) == ReviewPeople.normalize(name) }
    { name: user&.display_name.presence || name.presence, github: user&.github.presence }
  end
end
