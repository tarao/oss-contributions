require 'optparse'
require 'json'

abort 'You need specify GITHUB_TOKEN environment variable' unless ENV['GITHUB_TOKEN']

params = { :min_stars => 0 }
opt = OptionParser.new
opt.on('-s NUM', '--min-stargazers=NUM') {|v| params[:min_stars] = v.to_i}
opt.on('-c', '--contribution-only') {|v| params[:contribution_only] = v}
opt.parse!(ARGV)

all_repos = {}

ARGV.each do |user|
  require './github_api'

  GitHubAPI.repositories(user).each do |repo|
    all_repos[repo['name']] ||= repo
    all_repos[repo['name']]['contributors'] ||= []

    role = repo.delete('role')
    contributions = repo.delete('contributions')

    if !params[:contribution_only] || role != 'owner'
      all_repos[repo['name']]['contributors'] << {
        'user'          => user,
        'role'          => role,
        'contributions' => contributions,
      }
    end
  end
end

def contribution_ordering(contributor)
  role_score = {
    'owner'       => 2,
    'committer'   => 2,
    'contributor' => 1,
  }[contributor['role']] || 0

  pull_reqs = contributor['contributions']['pull_requests'] || 0
  commits = contributor['contributions']['commits'] || 0
  reviews = contributor['contributions']['reviews'] || 0

  [ role_score, pull_reqs, commits, reviews ]
end

all_repos.each do |k, repo|
  repo['contributors'].sort! do |a, b|
    contribution_ordering(b) <=> contribution_ordering(a)
  end

  [k, repo]
end

sorted_repos = all_repos.values.filter do |repo|
  repo['contributors'].size > 0 && repo['stargazers'] >= params[:min_stars]
end.sort do |a, b|
  b['stargazers'] <=> a['stargazers']
end

print(sorted_repos.to_json)
