# Builds ReviewPullRequest rows for tests without going through GitHub.
module ReviewPrFactory
  def create_review_pr(repo: "acme/server", number: 1, stage: "needs", waiting_on: "reviewers",
                       waiting_since: 1.day.ago, opened_at: nil, ready_at: nil, **attrs)
    ReviewPullRequest.create!(
      repo: repo, number: number, title: attrs.delete(:title) || "PR #{number}",
      url: "https://github.com/#{repo}/pull/#{number}",
      author: attrs.delete(:author) || "bob-gh", author_association: attrs.delete(:author_association) || "MEMBER",
      opened_at: opened_at || waiting_since, ready_at: ready_at,
      stage: stage, waiting_on: waiting_on, waiting_since: waiting_since, **attrs
    )
  end
end
