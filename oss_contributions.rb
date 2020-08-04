require 'optparse'
require 'net/http'
require 'uri'
require 'json'
require 'erb'

params = { :min_stars => 0, :users => [] }
opt = OptionParser.new
opt.on('-u USER', '--user=USER') {|v| params[:users] << v}
opt.on('-o ORGANIZATION', '--organization=ORGANIZATION') {|v| params[:organization] = v}
opt.on('-m NUM', '--min-stargazers=NUM') {|v| params[:min_stars] = v.to_i}
opt.on('-c', '--contribution-only') {|v| params[:contribution_only] = v}
opt.on('-i', '--include-personal') {|v| params[:include_personal] = v}
opt.on('-s', '--sort=ORDER') {|v| params[:sort] = v}
opt.on('-r TEMPLATE', '--render=TEMPLATE') {|v| params[:template] = v}
opt.parse!(ARGV)

params[:users] += ARGV

abort 'You need specify GITHUB_TOKEN environment variable' unless ENV['GITHUB_TOKEN']

if params[:organization]
  page = 1
  loop do
    url = "https://api.github.com/orgs/#{params[:organization]}/members?page=#{page}"
    list = JSON.load(Net::HTTP.get(URI.parse(url)))
    list.each do |user|
      params[:users] << user['login']
    end

    break if list.empty?
    page += 1
  end
end

all_repos = {}
stats = {}
users = {}

params[:users].each do |user|
  require './github_api'

  GitHubAPI.repositories(user).each do |repo|
    all_repos[repo['name']] ||= repo
    all_repos[repo['name']]['contributors'] ||= []

    role = repo.delete('role')
    contributions = repo.delete('contributions')

    if !params[:contribution_only] || role != 'owner'
      users['all'] ||= {}
      users['all'][user] = true
      users[role] ||= {}
      users[role][user] = true
      stats['total_commits'] ||= 0
      stats['total_commits'] += contributions['commits'] || 0
      stats['total_pull_requests'] ||= 0
      stats['total_pull_requests'] += contributions['pull_requests'] || 0
      stats['total_reviews'] ||= 0
      stats['total_reviews'] += contributions['reviews'] || 0

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
    'owner'        => 3,
    'maintainer'   => 3,
    'collaborator' => 2,
    'contributor'  => 1,
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

filtered_repos = all_repos.values.filter do |repo|
  [
    repo['stargazers'] >= params[:min_stars],
    params[:include_personal] ?
      repo['contributors'].size > 0 :
      repo['contributors'].filter{|c| c['role'] != 'owner'}.size > 0,
  ].all?
end

sorted_repos =
  case params[:sort]
  when 'max-contribution'
    filtered_repos.sort do |a, b|
      b_max = b['contributors'].map{|c| contribution_ordering(c).drop(1)}.max{|x, y| x <=> y}
      a_max = a['contributors'].map{|c| contribution_ordering(c).drop(1)}.max{|x, y| x <=> y}
      b_max <=> a_max
    end
  when 'total-contributions'
    filtered_repos.sort do |a, b|
      b_total = [0, 0, 0]
      b['contributors'].each do |c|
        b_total = b_total.zip(contribution_ordering(c).drop(1)).map{|x, y| x + y}
      end

      a_total = [0, 0, 0]
      a['contributors'].each do |c|
        a_total = a_total.zip(contribution_ordering(c).drop(1)).map{|x, y| x + y}
      end

      b_total <=> a_total
    end
  when 'total-contributors'
    filtered_repos.sort do |a, b|
      b_total = [0, 0, 0]
      b['contributors'].each do |c|
        b_total = b_total.zip(contribution_ordering(c).drop(1)).map{|x, y| x + y}
      end
      b_total.unshift(b['contributors'].size)

      a_total = [0, 0, 0]
      a['contributors'].each do |c|
        a_total = a_total.zip(contribution_ordering(c).drop(1)).map{|x, y| x + y}
      end
      a_total.unshift(a['contributors'].size)

      b_total <=> a_total
    end
  else
    filtered_repos.sort do |a, b|
      b['stargazers'] <=> a['stargazers']
    end
  end

stats['total_users'] = (users['all'] || {}).size
stats['total_owners'] = (users['owner'] || {}).size
stats['total_maintainers'] = (users['maintainer'] || {}).size
stats['total_collaborators'] = (users['collaborator'] || {}).size
stats['total_contributors'] = (users['contributor'] || {}).size

result = {
  'stats'        => stats,
  'repositories' => sorted_repos,
}

if params[:template]
  puts(ERB.new(
         IO.read(params[:template]),
         trim_mode: 2,
       ).result_with_hash(result))
else
  puts(result.to_json)
end
