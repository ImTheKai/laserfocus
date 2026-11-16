class ReviewsController < ApplicationController
  def show
    @configured = LASER_FOCUS_CONFIG.reviews.present?
    @presenter = ReviewsPresenter.build(viewer: viewer_github_login) if @configured
    @review_sync = ReviewSyncRun.most_recent.first
    @last_sync = SyncRun.ok.most_recent.first
    # Same count as on the board, see BoardController.
    @warnings = BoardPresenter.build.warnings
  end

  private

  # The signed-in person's GitHub login, from a board.users entry that matches
  # their email or display name and carries a github: login.
  def viewer_github_login
    email = current_user_email.to_s.downcase
    name = session[:user_name].to_s.strip.downcase
    user = LASER_FOCUS_CONFIG.board.users.find { |u| u.email.present? && u.email.to_s.downcase == email } ||
           LASER_FOCUS_CONFIG.board.users.find { |u| name.present? && u.display_name.to_s.downcase == name }
    user&.github.presence
  end
end
