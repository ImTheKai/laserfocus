# Builds GithubIssue rows for tests without going through GitHub.
module GithubIssueFactory
  def create_github_issue(repo: "acme/server", number: 101, stage: "new", waiting_on: "team",
                          waiting_since: 1.day.ago, opened_at: nil, **attrs)
    GithubIssue.create!(
      repo: repo, number: number, title: attrs.delete(:title) || "Issue #{number}",
      url: "https://github.com/#{repo}/issues/#{number}",
      author: attrs.delete(:author) || "reporter", author_association: attrs.delete(:author_association) || "NONE",
      opened_at: opened_at || waiting_since,
      stage: stage, waiting_on: waiting_on, waiting_since: waiting_since, **attrs
    )
  end
end
