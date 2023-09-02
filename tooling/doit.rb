#!/usr/bin/env ruby

# Scopes needed on all target org repos
#  - R/W contents (to git push)
#  - R/W admin    (to create/remove repos)
#
# Scopes needed on source repos by app
#  - R actions         (to access artifacts)
#  - R/W pull requests (to make comments)

require_relative "lib"
require "fileutils"
require "tmpdir"

# NOTE: THIS WILL LEAK ENVIRONMENT AND TOKENS!!!!!!!
DEBUG = false

ENV["GIT_AUTHOR_NAME"] = "Jovian Experiments"
ENV["GIT_AUTHOR_EMAIL"] = "<jovian-experiments@>"
ENV["GIT_COMMITTER_NAME"] = ENV["GIT_AUTHOR_NAME"]
ENV["GIT_COMMITTER_EMAIL"] = ENV["GIT_AUTHOR_EMAIL"]

missing = [
  "TARGET_TOKEN",
  "SOURCE_APP_ID",
  "SOURCE_PRIVATE_KEY",
].select do |var|
  !ENV[var]
end

if missing.length > 0 then
  $stderr.puts "ERROR: Missing secrets from ENV:"
  missing.each do |var|
    $stderr.puts "  - #{var}"
  end
  exit 1
end

$target = GH.new("www-jovian", ENV["TARGET_TOKEN"])
$source = GH.initialize_for_app_secret("Jovian-Experiments", ENV["SOURCE_APP_ID"], ENV["SOURCE_PRIVATE_KEY"])
$source_repo = "Jovian-NixOS"

def get_PRs_artifacts()
  code, pulls = $source.get_pulls(repo: $source_repo, query: {state: "open", per_page: 100, sort: "updated", direction: "desc"})
  if code < 200 || code >= 300 then
    raise "Unexpected response #{code}, #{pulls.inspect}"
  end

  pulls.each do |pull|
    sha = pull["head"]["sha"]

    puts ""
    puts ":: #{pull["html_url"]}"
    puts "   #{pull["number"]}"
    puts "   #{pull["title"]}"

    code, response = $source.get_workflow_runs(repo: $source_repo, query: {status: "completed", head_sha: sha})
    runs = response["workflow_runs"]
    ci_run = runs.select do |run|
      run["path"] == ".github/workflows/docs.yml"
    end
      .first

    if ci_run then
      archive = File.join(Dir.pwd(),"#{sha}.zip")
      puts "   Downloading artifact..."
      code, response = $source.get(ci_run["artifacts_url"].split("/", 4).last)
      success = false

      # Try a few times, connection sometimes is iffy?
      5.times do |i|
        puts "   Attempt ##{i+1}"
        status, artifact_response = Curl.download(
          response["artifacts"].first["archive_download_url"],
          archive,
          args: [
              "--header", "X-GitHub-Api-Version: 2022-11-28",
              "--header", "Authorization: Bearer #{$source.token}",
        ])
        if status == 0
          success = true
          break
        else
          puts "   ... Failed to download (#{status})"
          sleep 5
        end
      end
      unless success
        puts "   !!! could not download artifact..."
        puts "   Skipping hoping next run will succeed..."
        return
      end
      puts "   ... done!"

      was_updated = push_render(pr_num: pull["number"], archive: archive, sha: sha)
      if was_updated
        code, pull = $source.get_pull(repo: $source_repo, pull_number: pull["number"])
        comment(pull: pull)
      else
        puts "   (No update to pages...)"
      end
    else
      puts "   Skipping; no artifacts_url"
    end
  end
end

def comment(pull:)
    comments_count = pull["comments"]
    sha = pull["head"]["sha"]
    repo_name = "#{$source_repo}-PR#{pull["number"]}"
    url = "https://www-jovian.github.io/#{repo_name}/"

    puts "   -> Commenting..."

    marker = "*Beep-boop, this comment was auto-generated for #{$target.owner}.*"

    message = [
      "Hi there!",
      "",
      "In the next few minutes a fresh preview of the docs for #{sha} will be available at #{url}.",
      "",
      "See also the generated diff at: https://github.com/#{$target.owner}/#{repo_name}",
      "",
      "Cheers!",
      "",
      "* * *",
      "",
      marker,
    ].join("\n")

    code, response = $source.get_issue_comments(
      repo: $source_repo,
      issue_number: pull["number"],
      query: {
        per_page: 1,
        page: comments_count,
      }
    )

    if response && response.first
      comment = response.first
      body = comment["body"]
      if body[marker]
        puts "   ... updating comment"
        code, response = $source.update_issue_comment(
          repo: $source_repo,
          comment_id: comment["id"],
          body: message
        )
        return
      end
    end

    puts "   ... adding a comment"
    code, response = $source.create_issue_comment(
      repo: $source_repo,
      issue_number: pull["number"],
      body: message
    )

    if code < 200 || code >= 300 then
      raise "Unexpected response #{code}, #{response.inspect}"
    end
end

def push_render(pr_num:, archive:, sha:)
  repo_name = "#{$source_repo}-PR#{pr_num}"
  puts ""
  puts "   -> Attempting to push to #{repo_name}"
  puts ""
  code, response = $target.get_repo(name: repo_name)

  if code == 404 then
    puts ":: Creating repo..."
    $target.create_repo(
      name: repo_name,
      description: "https://www-jovian.github.io/#{repo_name}/ From: https://github.com/#{$source.owner}/#{$source_repo}/pull/#{pr_num}"
    )
  else
    puts ":: Already created..."
  end

  remote_url = "https://#{$target.token}@github.com/#{$target.owner}/#{repo_name}.git"
  tag = "sha_#{sha}"
  was_updated = true

  git("clone", remote_url, "_repo")
  Dir.mkdir("repo")
  FileUtils.mv("_repo/.git", "repo/.git")
  FileUtils.rm_rf("_repo")
  Dir.chdir("repo") do
    begin
      git("checkout", "-b", "gh-pages")
    rescue
      git("checkout", "gh-pages")
    end

    system("unzip", archive)

    message = [
      "Preview for PR##{pr_num}",
      "",
      "See https://www-jovian.github.io/#{repo_name}/",
      "From: https://github.com/#{$source.owner}/#{$source_repo}/pull/#{pr_num}",
    ].join("\n")

    begin
      git("add", ".")
      git("commit", "-m", message)
    rescue
      # Failure to commit implies it's not been updated here.
      # (Or worse, but other stuff should have failed.)
      was_updated = false
    end
    git("tag", "--force", tag)
    git("push", "--force", "--set-upstream", "origin", "gh-pages")
    git("push", "--force", "--tags", "origin")
  end
  FileUtils.rm_rf("repo")

  return was_updated
end

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    get_PRs_artifacts()
  end
end
