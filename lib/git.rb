require "shellwords"

def git(*args)
  cmd = [
    "git",
    *args,
  ]
  $stderr.puts " $ #{cmd.shelljoin}" if DEBUG
  response = `#{cmd.shelljoin}`
  unless $?.success?
    raise [
      "Unexpected error when executing git command.",
      "Exit code: #{$?.exitstatus}",
    ].join("\n")
  end
  response
end
