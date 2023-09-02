require "json"
require "shellwords"

class GH
  DOMAIN = "https://api.github.com"
  attr_reader :owner
  attr_reader :token

  def initialize(owner, token)
    @owner = owner
    @token = token
  end

  def gh(path, args)
    response = Curl.curl(*[
      "--url", [DOMAIN, path].join("/"),
      "--header", "Accept: application/vnd.github+json",
      "--header", "Authorization: Bearer #{@token}",
      "--header", "X-GitHub-Api-Version: 2022-11-28",
      "--write-out", '%{response_code}',
      *args
    ]).split("\n")

    code = response.pop.to_i
    return code, JSON.parse(response.join("\n"))
  end

  def get(path)
    gh(path, [
      "--request", "GET",
    ])
  end

  def delete(path)
    gh(path, [
      "--request", "DELETE",
    ])
  end

  def post(path, data)
    gh(path, [
      "--request", "POST",
      "--data", data,
    ])
  end

  def get_repo(name:)
    get("repos/#{@owner}/#{name}")
  end

  def create_repo(name:, description: )
    post("orgs/#{@owner}/repos", {
      name: name,
      description: description,
      private: false,
      visibility: "public",
      has_issues: false,
      has_projects: false,
      has_wiki: false,
    }.to_json)
  end

  def delete_repo(name:)
    delete("repos/#{@owner}/#{name}")
  end

  def get_pulls(repo:, query: {})
    query = query.map { |pair| pair.join("=") }.join("&")
    get("repos/#{@owner}/#{repo}/pulls?#{query}")
  end

  def get_pull(repo:, pull_number:, query: {})
    query = query.map { |pair| pair.join("=") }.join("&")
    get("repos/#{@owner}/#{repo}/pulls/#{pull_number}?#{query}")
  end

  def get_artifacts(repo:, query: {})
    query = query.map { |pair| pair.join("=") }.join("&")
    get("repos/#{@owner}/#{repo}/actions/artifacts?#{query}")
  end

  # query: head_sha
  def get_workflow_runs(repo:, query: {})
    query = query.map { |pair| pair.join("=") }.join("&")
    get("repos/#{@owner}/#{repo}/actions/runs?#{query}")
  end

  def get_issue_comments(issue_number:, repo:, query: {})
    query = query.map { |pair| pair.join("=") }.join("&")
    get("repos/#{@owner}/#{repo}/issues/#{issue_number}/comments?#{query}")
  end

  def create_issue_comment(issue_number:, repo:, body:)
    post("repos/#{@owner}/#{repo}/issues/#{issue_number}/comments", {
      body: body,
    }.to_json)
  end

  def update_issue_comment(comment_id:, repo:, body:)
    post("repos/#{@owner}/#{repo}/issues/comments/#{comment_id}", {
      body: body,
    }.to_json)
  end
end
