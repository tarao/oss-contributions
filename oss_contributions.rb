# coding: utf-8
require 'optparse'
require 'date'
require 'net/http'
require 'uri'
require 'json'
require 'erb'

class OptionParser
  TERM_WIDTH = `tput cols`.to_i

  def wrap_desc(*str)
    # normalize word/sentence separators
    str = str
            .map{|s| s.gsub(/(?<=[^\s])\z/, ' ')}
            .join('')
            .gsub(/(?<![\n ])[ ]+/, ' ')
            .split(/[.](?=(?:\s|$))/, -1)
            .map{|s| s.gsub(/(\A +| +\z)/, '')}
            .join('.  ')
    width = TERM_WIDTH - (self.summary_width + self.summary_indent.length + 1)
    result = ''

    str.lines(chomp: true) do |line|
      new_line = ''
      i = 0
      indent = line.match(/\A\s*/).to_s
      line_width = width - indent.length
      loop do
        sub_str = line[i, line_width]
        sub_str.gsub!(/[^\s]*\z/, '') if (line[i + line_width] || '').match?(/[^\s]/)
        sub_str = line[i, line_width] if sub_str.empty?
        new_line += indent + sub_str.gsub(/^\A[ ]*/, '').rstrip
        i += sub_str.length
        break unless i < line.length
        new_line += "\n"
      end
      result += new_line + "\n"
    end

    result.gsub("\n",  "\n" + self.summary_indent + ' ' * self.summary_width + ' ')
  end
end

SORT_MAX_CONTRIBUTION =
  [ 'pull-requests', 'commits', 'reviews', 'issues', 'contributors', 'role', 'stargazers', ]
SORT_TOTAL_CONTRIBUTIONS =
  [ 'pull-requests', 'commits', 'reviews', 'issues', 'contributors', 'role', 'stargazers', ]
SORT_TOTAL_CONTRIBUTORS =
  [ 'contributors', 'role', 'pull-requests', 'commits', 'reviews', 'issues', 'stargazers', ]
SORT_STARGAZERS =
  [ 'stargazers', 'contributors', 'role', 'pull-requests', 'commits', 'reviews', 'issues', ]

params = {
  :min_stars => 0,
  :users => [],
  :sort => SORT_STARGAZERS,
  :ordering_accumulation_strategy => 'sum',
}
opt = OptionParser.new
opt.banner = "Usage: GITHUB_TOKEN=xxxx bundle exec ruby #{$0} [OPTIONS] [<USER>...]"
opt.separator('Options:')
opt.on(
  '-u USER',
  '--user=USER',
  opt.wrap_desc(
    'User whose contribution is analyzed.',
    'Use this option multiple times to specify more than one user.',
  ),
) {|v| params[:users] << v}
opt.on(
  '-o ORGANIZATION',
  '--organization=ORGANIZATION',
  opt.wrap_desc('Organization whose members are added to --user option.'),
) {|v| params[:organization] = v}
opt.on(
  '-f YYYY-MM-DD',
  '--from=YYYY-MM-DD',
  opt.wrap_desc('Date from when to start enumerating contributions.'),
) {|v| params[:from] = Date.parse(v).to_time}
opt.on(
  '-t YYYY-MM-DD',
  '--to=YYYY-MM-DD',
  opt.wrap_desc('Date to when to stop enumerating contributions.'),
) {|v| params[:to] = Date.parse(v).to_time}
opt.on(
  '-m NUM',
  '--min-stargazers=NUM',
  opt.wrap_desc('Exclude repositories which have stargazers less than this value.'),
) {|v| params[:min_stars] = v.to_i}
opt.on(
  '-c',
  '--contribution-only',
  opt.wrap_desc('Exclude contributions by the repository owner.'),
) {|v| params[:contribution_only] = v}
opt.on(
  '-i',
  '--include-personal',
  opt.wrap_desc(
    'By default, repositories which only have contributions by their owners are excluded.',
    'Specify this option to include them.',
  ),
) {|v| params[:include_personal] = v}
opt.on(
  '-s',
  '--sort=ORDER',
  opt.wrap_desc(
    'The order of repositories and contributors.  The following values are available.',
    "\n",
    "\nmax-contribution",
    "\n  Order by #{SORT_MAX_CONTRIBUTION.join(', ')}",
    "    with taking maximum values of criteria among contributions in a single repository.",
    "\n",
    "\ntotal-contributions",
    "\n  Order by #{SORT_TOTAL_CONTRIBUTIONS.join(', ')}",
    "    with taking the sum of each criterion among contributions in a single repository.",
    "\n",
    "\ntotal-contributors",
    "\n  Order by #{SORT_TOTAL_CONTRIBUTORS.join(', ')}",
    "    with taking the sum of each criterion among contributions in a single repository.",
    "\n",
    "\nstargazers",
    "\n  Order by #{SORT_STARGAZERS.join(', ')}",
    "    with taking the sum of each criterion among contributions in a single repository.",
    "    This is the default value in case no --sort=ORDER is specified.",
    "\n",
    "\n<sort-criterion>, ...",
    "\n  Order by comma separated criteria.",
    "\n  Available criteria:",
    "\n    #{SORT_STARGAZERS.sort.join("\n    ")}",
  ),
) do |v|
  case v
  when 'max-contribution'
    params[:sort] = SORT_MAX_CONTRIBUTION
    params[:ordering_accumulation_strategy] = 'max'
  when 'total-contributions'
    params[:sort] = SORT_TOTAL_CONTRIBUTIONS
    params[:ordering_accumulation_strategy] = 'sum'
  when 'total-contributors'
    params[:sort] = SORT_TOTAL_CONTRIBUTORS
    params[:ordering_accumulation_strategy] = 'sum'
  when 'stargazers'
    params[:sort] = SORT_STARGAZERS
    params[:ordering_accumulation_strategy] = 'sum'
  else
    params[:sort] = v.split(/,\s*/)
    params[:ordering_accumulation_strategy] = 'sum'
  end
end
opt.on(
  '-r TEMPLATE',
  '--render=TEMPLATE',
  opt.wrap_desc(
    'Template file (.erb) to generate the output.',
    'JSON value is printed without this option.',
  ),
) {|v| params[:template] = v}
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

  GitHubAPI.repositories(user, from: params[:from], to: params[:to]).each do |repo|
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
      stats['total_issues'] ||= 0
      stats['total_issues'] += contributions['issues'] || 0

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
      'issues'        => 0,
    }
  end

  def self.of(
        contributor: contributor=nil,
        contributions: contributions=nil,
        repository: repository=nil,
        strategy: strategy='sum'
      )
    ordering = self.new
    ordering.add_contributor(contributor, strategy) if contributor
    ordering.add_contributions(contributions, strategy) if contributions
    ordering.add_repository(repository, strategy) if repository
    ordering
  end

  def add_contributor(contributor, strategy)
    role = if contributor['role']
             ROLE_SCORE[contributor['role']] || 0
           else
             nil
           end
    @order['role'] = ACCUMULATE[strategy][@order['role'], role] if role

    contributions = contributor['contributions']
    if contributions
      if contributions.is_a?(Array)
        contributions.each do |c|
          add_contributions(c, strategy)
        end
      else
        add_contributions(contributions, strategy)
      end
    end
  end

  def add_contributions(contributions, strategy)
    role = if contributions['role']
             ROLE_SCORE[contributions['role']] || 0
           else
             nil
           end
    pull_reqs = contributions['pull_requests'] || 0
    commits = contributions['commits'] || 0
    reviews = contributions['reviews'] || 0
    issues = contributions['issues'] || 0

    @order['contributors'] += 1
    @order['role'] = ACCUMULATE[strategy][@order['role'], role] if role
    @order['pull-requests'] = ACCUMULATE[strategy][@order['pull-requests'], pull_reqs]
    @order['commits'] = ACCUMULATE[strategy][@order['commits'], commits]
    @order['reviews'] = ACCUMULATE[strategy][@order['reviews'], reviews]
    @order['issues'] = ACCUMULATE[strategy][@order['issues'], issues]
  end

  def add_repository(repository, strategy)
    @order['stargazers'] = ACCUMULATE[strategy][@order['stargazers'], repository['stargazers'] || 0]
    repository['contributors'].each do |c|
      add_contributor(c, strategy)
    end
  end

  def to_lexicographical(sort)
    sort.map{|s| @order[s] || 0}
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

all_users = {}
all_repos.each do |k, repo|
  repo['contributors'].each do |c|
    all_users[c['user']] ||= { 'user' => c['user'], 'contributions' => [] }
    all_users[c['user']]['contributions'] << {
      'repository'    => repo.filter{|k, v| k != 'contributors'},
      'role'          => c['role'],
    }.merge(c['contributions'])
  end
end

filtered_users = all_users.values.map do |user|
  contributions = user['contributions'].filter do |c|
    repo = c['repository']
    [
      c['repository']['stargazers'] >= params[:min_stars],
      params[:include_personal] || c['role'] != 'owner',
    ].all?
  end

  total = {
    'commits'       => 0,
    'pull_requests' => 0,
    'reviews'       => 0,
    'issues'        => 0,
  }
  contributions.each do |c|
    total['commits'] += c['commits'] || 0
    total['pull_requests'] += c['pull_requests'] || 0
    total['reviews'] += c['reviews'] || 0
    total['issues'] += c['issues'] || 0
  end

  {
    'user'          => user['user'],
    'total'         => total,
    'contributions' => contributions,
  }
end.filter{|user| !user['contributions'].empty?}

sorted_users =
  begin
    sort = params[:sort]
    strategy = params[:ordering_accumulation_strategy]

    filtered_users.map do |user|
      sorted_contributions = user['contributions'].sort do |a, b|
        ordering_b = Ordering.of(contributions: b, strategy: strategy).to_lexicographical(sort)
        ordering_a = Ordering.of(contributions: a, strategy: strategy).to_lexicographical(sort)
        ordering_b <=> ordering_a
      end
      user.merge({ 'contributions' => sorted_contributions })
    end.sort do |a, b|
      ordering_b = Ordering.of(contributor: b, strategy: strategy).to_lexicographical(sort)
      ordering_a = Ordering.of(contributor: a, strategy: strategy).to_lexicographical(sort)
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
  'users'        => sorted_users,
}

if params[:template]
  puts(ERB.new(
         IO.read(params[:template]),
         trim_mode: 2,
       ).result_with_hash(result))
else
  puts(result.to_json)
end
