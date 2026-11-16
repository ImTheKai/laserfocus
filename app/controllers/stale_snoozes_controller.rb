class StaleSnoozesController < ApplicationController
  def update
    key, state = snooze_target(params[:key].to_s)
    return head :not_found unless key

    snooze = StaleSnooze.find_or_initialize_by(jira_key: key)
    snooze.update!(
      jira_status: state,
      snoozed_until: (LASER_FOCUS_CONFIG.board.snooze_days.days - LASER_FOCUS_CONFIG.board.staleness_lead).from_now,
      snoozed_by: session[:user_name].presence || current_user_email,
      reason: params[:reason].to_s.strip.first(StaleSnooze::REASON_LIMIT).presence
    )
    BoardBroadcasts.board
    head :no_content
  end

  def destroy
    deleted = StaleSnooze.where(jira_key: params[:key].to_s).delete_all
    BoardBroadcasts.board if deleted.positive?
    head :no_content
  end

  private

  # A Jira ticket on the board, or an open PR on the Reviews view. Returns the
  # key to store and the state the snooze holds for.
  def snooze_target(raw)
    if ReviewPullRequest.snooze_key?(raw)
      pr = ReviewPullRequest.find_by_key(raw)
      pr && [ pr.key, pr.snooze_state ]
    else
      issue = Issue.active.find_by(jira_key: raw)
      issue && [ issue.jira_key, issue.jira_status ]
    end
  end
end
