module BoardBroadcasts
  def self.board
    Turbo::StreamsChannel.broadcast_refresh_to("board")
  end

  # The Reviews view has its own stream, so the Jira sync's minutely refresh
  # does not reset it while someone is filtering.
  def self.reviews
    Turbo::StreamsChannel.broadcast_refresh_to("reviews")
  end
end
