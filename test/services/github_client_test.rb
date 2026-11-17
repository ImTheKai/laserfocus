require "test_helper"
require "webmock/minitest"

class GithubClientTest < ActiveSupport::TestCase
  setup { WebMock.disable_net_connect! }

  def page(nodes, next_cursor: nil)
    { data: { search: { pageInfo: { hasNextPage: !next_cursor.nil?, endCursor: next_cursor }, nodes: nodes } } }.to_json
  end

  def pr(number, repo: "acme/server") = { number: number, repository: { nameWithOwner: repo } }

  test "the search asks for open, non-draft PRs in every repo" do
    q = GithubClient.search_query([ "acme/server", "acme/docs" ])
    assert_equal "is:pr is:open draft:false archived:false repo:acme/server repo:acme/docs", q
  end

  test "the issues search asks for open issues in every repo, with the issue query" do
    q = GithubClient.issues_query([ "acme/server", "acme/docs" ])
    assert_equal "is:issue is:open archived:false repo:acme/server repo:acme/docs", q

    stub_request(:post, "https://api.github.com/graphql")
      .with { |req| body = JSON.parse(req.body); body["query"].include?("... on Issue") && body.dig("variables", "q").start_with?("is:issue") }
      .to_return(status: 200, body: page([ pr(3) ]))
    assert_equal [ 3 ], GithubClient.new(token: "t").open_issues([ "acme/server" ]).map { |n| n["number"] }
  end

  test "pages through results with the token" do
    stub_request(:post, "https://api.github.com/graphql")
      .with(headers: { "Authorization" => "Bearer t0k" }) { |req| JSON.parse(req.body).dig("variables", "after").nil? }
      .to_return(status: 200, body: page([ pr(1) ], next_cursor: "c1"))
    stub_request(:post, "https://api.github.com/graphql")
      .with { |req| JSON.parse(req.body).dig("variables", "after") == "c1" }
      .to_return(status: 200, body: page([ pr(2) ]))

    nodes = GithubClient.new(token: "t0k").open_ready_pull_requests([ "acme/server" ])
    assert_equal [ 1, 2 ], nodes.map { |n| n["number"] }
  end

  test "raises without a token, before calling GitHub" do
    error = assert_raises(GithubClient::Error) { GithubClient.new(token: nil).open_ready_pull_requests([ "acme/server" ]) }
    assert_match "GITHUB_TOKEN", error.message
  end

  test "raises on an HTTP error" do
    stub_request(:post, "https://api.github.com/graphql").to_return(status: 401, body: "Bad credentials")
    error = assert_raises(GithubClient::Error) { GithubClient.new(token: "x").open_ready_pull_requests([ "acme/server" ]) }
    assert_match "401", error.message
  end

  test "raises on a GraphQL error" do
    stub_request(:post, "https://api.github.com/graphql")
      .to_return(status: 200, body: { errors: [ { message: "Something broke" } ] }.to_json)
    error = assert_raises(GithubClient::Error) { GithubClient.new(token: "x").open_ready_pull_requests([ "acme/server" ]) }
    assert_match "Something broke", error.message
  end
end
