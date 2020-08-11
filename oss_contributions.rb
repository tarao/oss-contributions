require 'optparse'
require 'net/http'
require 'uri'
require 'json'
require 'erb'

params = { :min_stars => 0, :users => [], :ordering_accumulation_strategy => 'sum' }
opt = OptionParser.new
opt.on('-u USER', '--user=USER') {|v| params[:users] << v}
opt.on('-o ORGANIZATION', '--organization=ORGANIZATION') {|v| params[:organization] = v}
opt.on('-m NUM', '--min-stargazers=NUM') {|v| params[:min_stars] = v.to_i}
opt.on('-c', '--contribution-only') {|v| params[:contribution_only] = v}
opt.on('-i', '--include-personal') {|v| params[:include_personal] = v}
opt.on('-s', '--sort=ORDER') do |v|
  case v
  when 'max-contribution'
    params[:sort] = [ 'pull-requests', 'commits', 'reviews', 'contributors', 'role', 'stargazers', ]
    params[:ordering_accumulation_strategy] = 'max'
  when 'total-contributions'
    params[:sort] = [ 'pull-requests', 'commits', 'reviews', 'contributors', 'role', 'stargazers', ]
    params[:ordering_accumulation_strategy] = 'sum'
  when 'total-contributors'
    params[:sort] = [ 'contributors', 'role', 'pull-requests', 'commits', 'reviews', 'stargazers', ]
    params[:ordering_accumulation_strategy] = 'sum'
  when 'stargazers'
    params[:sort] = [ 'stargazers', 'contributors', 'role', 'pull-requests', 'commits', 'reviews', ]
    params[:ordering_accumulation_strategy] = 'sum'
  else
    params[:sort] = v.split(',')
    params[:ordering_accumulation_strategy] = 'sum'
  end
end
opt.on('-r TEMPLATE', '--render=TEMPLATE') {|v| params[:template] = v}
opt.parse!(ARGV)

params[:users] += ARGV

abort 'You need specify GITHUB_TOKEN environment variable' unless ENV['GITHUB_TOKEN']

if params[:organization]
  page = 1
  loop do
    http = Net::HTTP.new("api.github.com", 443)
    http.use_ssl = true
    res = http.get(
      "/orgs/#{params[:organization]}/members?page=#{page}",
      { 'Authorization' => "token #{ENV['GITHUB_TOKEN']}" },
    )
    break unless res.code == '200'

    list = JSON.load(res.body)
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

class Ordering
  ROLE_SCORE = {
    'owner'        => 3,
    'maintainer'   => 3,
    'collaborator' => 2,
    'contributor'  => 1,
  }
  DEFAULT_SORT = ['stargazers', 'role', 'contributors', 'pull-requests', 'commits', 'reviews' ]
  ACCUMULATE = {
    'sum' => proc{|x,y| x + y},
    'max' => proc{|x,y| [x, y].max(&:<=>)},
  }

  def initialize
    @order = {
      'stargazers'    => 0,
      'role'          => 0,
      'contributors'  => 0,
      'pull-requests' => 0,
      'commits'       => 0,
      'reviews'       => 0,
    }
  end

  def self.of(contributor: contributor=nil, repository: repository=nil, strategy: strategy='sum')
    ordering = self.new
    ordering.add_contributor(contributor, strategy) if contributor
    ordering.add_repository(repository, strategy) if repository
    ordering
  end

  def add_contributor(contributor, strategy)
    role = ROLE_SCORE[contributor['role']] || 0

    pull_reqs = contributor['contributions']['pull_requests'] || 0
    commits = contributor['contributions']['commits'] || 0
    reviews = contributor['contributions']['reviews'] || 0

    @order['role'] = ACCUMULATE[strategy][@order['role'], role]
    @order['contributors'] += 1
    @order['pull-requests'] = ACCUMULATE[strategy][@order['pull-requests'], pull_reqs]
    @order['commits'] = ACCUMULATE[strategy][@order['commits'], commits]
    @order['reviews'] = ACCUMULATE[strategy][@order['reviews'], reviews]
  end

  def add_repository(repository, strategy)
    @order['stargazers'] = ACCUMULATE[strategy][@order['stargazers'], repository['stargazers'] || 0]
    repository['contributors'].each do |c|
      add_contributor(c, strategy)
    end
  end

  def to_lexicographical(sort = DEFAULT_SORT)
    (sort || DEFAULT_SORT).map{|s| @order[s] || 0}
  end
end

all_repos.each do |k, repo|
  sort = params[:sort]
  strategy = params[:ordering_accumulation_strategy]
  repo['contributors'].sort! do |a, b|
    ordering_b = Ordering.of(contributor: b, strategy: strategy).to_lexicographical(sort)
    ordering_a = Ordering.of(contributor: a, strategy: strategy).to_lexicographical(sort)
    ordering_b <=> ordering_a
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
  begin
    sort = params[:sort]
    strategy = params[:ordering_accumulation_strategy]

    filtered_repos.sort do |a, b|
      ordering_b = Ordering.of(repository: b, strategy: strategy).to_lexicographical(sort)
      ordering_a = Ordering.of(repository: a, strategy: strategy).to_lexicographical(sort)
      ordering_b <=> ordering_a
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
