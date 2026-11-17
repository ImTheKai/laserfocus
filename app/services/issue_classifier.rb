# Works out who an open issue is waiting on, from who spoke last. "Team" is
# anyone GitHub calls a member or collaborator of the org, or who is in
# board.users (see IssueSync). The answer drives the Issues view's columns and
# the clock behind the age chip:
#
#   new       from outside, nobody on the team replied yet  waits on the team since it was opened
#   us        someone outside spoke after the team did      waits on the team since they spoke
#   reporter  the team had the last word                    waits on the reporter since then
#   backlog   filed by the team, nothing outside pending    waits on the team since the last word
class IssueClassifier
  Result = Struct.new(:stage, :waiting_on, :waiting_since, keyword_init: true)

  def self.classify(**kwargs) = new(**kwargs).result

  # comments: oldest first, hashes with "login", "team" (true/false) and "at".
  def initialize(author_team:, opened_at:, comments: [])
    @author_team = author_team
    @opened_at = opened_at
    @comments = comments.filter_map do |c|
      at = to_time(c["at"] || c[:at])
      at && { team: !!(c["team"] || c[:team]), at: at }
    end.sort_by { |c| c[:at] }
  end

  def result
    last_team_at = @comments.select { |c| c[:team] }.map { |c| c[:at] }.max
    if !@author_team && last_team_at.nil?
      return Result.new(stage: "new", waiting_on: "team", waiting_since: @opened_at)
    end

    # The team spoke last at last_team_at (or opened it themselves): anything
    # from outside after that is waiting for an answer.
    baseline = last_team_at || @opened_at
    pending = @comments.reject { |c| c[:team] }.select { |c| c[:at] > baseline }
    if pending.any?
      Result.new(stage: "us", waiting_on: "team", waiting_since: pending.first[:at])
    elsif @author_team
      Result.new(stage: "backlog", waiting_on: "team", waiting_since: baseline)
    else
      Result.new(stage: "reporter", waiting_on: "reporter", waiting_since: last_team_at)
    end
  end

  private

  def to_time(v)
    return v if v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone)
    v.present? ? Time.zone.parse(v.to_s) : nil
  rescue ArgumentError
    nil
  end
end
