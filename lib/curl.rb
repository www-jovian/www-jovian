require "shellwords"

module Curl
  extend self

  def curl(*args, return_failure: false)
    cmd = [
      "curl",
      "--no-progress-meter",
      "--show-error",
      "--location",
      *args,
    ]
    $stderr.puts " $ #{cmd.shelljoin}" if DEBUG
    response = `#{cmd.shelljoin}`

    if return_failure
      return $?.exitstatus, response
    end

    unless $?.success?
      $stderr.puts "Unexpected error when executing curl command."
      $stderr.puts "Exit code: #{$?.exitstatus}"
      exit 1
    end
    response
  end

  def download(url, output, return_failure: true, args: [])
    curl(*[
      url,
      "--output", output,
      *args,
    ], return_failure: return_failure)
  end
end
