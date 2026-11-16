require "net/http"
require "json"

# Read-only GitHub access for the Reviews view: one GraphQL search for the open,
# non-draft PRs in the watched repos. Nothing here writes to GitHub.
class GithubClient
  class Error < StandardError; end

  ENDPOINT = URI("https://api.github.com/graphql").freeze
  PAGE_SIZE = 50
  MAX_PAGES = 20
  # GitHub search ORs repeated repo: qualifiers. A handful per query keeps each
  # query well inside the search limits however long the list grows.
  REPOS_PER_QUERY = 10

  QUERY = <<~GRAPHQL.freeze
    query($q: String!, $first: Int!, $after: String) {
      search(type: ISSUE, query: $q, first: $first, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on PullRequest {
            number title url isDraft createdAt updatedAt additions deletions headRefName
            authorAssociation reviewDecision
            repository { nameWithOwner }
            author { login }
            labels(first: 10) { nodes { name } }
            reviewRequests(first: 10) {
              nodes { requestedReviewer { ... on User { login } ... on Team { slug } } }
            }
            latestReviews(first: 20) { nodes { author { login } state submittedAt } }
            commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
            ready: timelineItems(itemTypes: [READY_FOR_REVIEW_EVENT], last: 1) {
              nodes { ... on ReadyForReviewEvent { createdAt } }
            }
            forcePushes: timelineItems(itemTypes: [HEAD_REF_FORCE_PUSHED_EVENT], last: 1) {
              nodes { ... on HeadRefForcePushedEvent { createdAt } }
            }
          }
        }
      }
    }
  GRAPHQL

  def initialize(token: LASER_FOCUS_CONFIG.reviews&.github_token)
    @token = token
  end

  # Raw PullRequest nodes for every open, ready-for-review PR in the repos.
  def open_ready_pull_requests(repos)
    raise Error, "GITHUB_TOKEN is not set" if @token.blank?

    repos.each_slice(REPOS_PER_QUERY).flat_map do |slice|
      search_all(self.class.search_query(slice))
    end.uniq { |n| [ n.dig("repository", "nameWithOwner").to_s.downcase, n["number"] ] }
  end

  def self.search_query(repos)
    ([ "is:pr", "is:open", "draft:false", "archived:false" ] + repos.map { |r| "repo:#{r}" }).join(" ")
  end

  private

  def search_all(query)
    nodes = []
    after = nil
    MAX_PAGES.times do
      data = post(QUERY, q: query, first: PAGE_SIZE, after: after)
      search = data.fetch("search")
      nodes.concat(search.fetch("nodes").select { |n| n.is_a?(Hash) && n["number"] })
      break unless search.dig("pageInfo", "hasNextPage")
      after = search.dig("pageInfo", "endCursor")
    end
    nodes
  end

  def post(query, variables)
    req = Net::HTTP::Post.new(ENDPOINT)
    req["Authorization"] = "Bearer #{@token}"
    req["Content-Type"] = "application/json"
    req["User-Agent"] = "laserfocus"
    req.body = JSON.generate(query: query, variables: variables)

    res = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(req)
    end
    raise Error, "GitHub answered #{res.code}: #{res.body.to_s.first(200)}" unless res.is_a?(Net::HTTPSuccess)

    body = JSON.parse(res.body)
    if body["errors"].present?
      raise Error, "GitHub GraphQL error: #{body["errors"].map { |e| e["message"] }.join("; ").first(300)}"
    end
    body.fetch("data")
  end
end
