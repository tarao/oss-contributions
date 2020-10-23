oss-contributions
=================

List OSS contributions (GitHub repositories) of specified users.

```
Usage: GITHUB_TOKEN=xxxx bundle exec ruby oss_contributions.rb [OPTIONS] [<USER>...]
Options:
    -u, --user=USER                  User whose contribution is analyzed.  Use this option multiple
                                     times to specify more than one user.
                                     
    -o, --organization=ORGANIZATION  Organization whose members are added to --user option.
                                     
    -m, --min-stargazers=NUM         Exclude repositories which have stargazers less than this
                                     value.
                                     
    -c, --contribution-only          Exclude contributions by the repository owner.
                                     
    -i, --include-personal           By default, repositories which only have contributions by their
                                     owners are excluded.  Specify this option to include them.
                                     
    -s, --sort=ORDER                 The order of repositories and contributors.  The following
                                     values are available.
                                     
                                     max-contribution
                                       Order by pull-requests, commits, reviews, issues,
                                       contributors, role, stargazers with taking maximum values of
                                       criteria among contributions in a single repository.
                                     
                                     total-contributions
                                       Order by pull-requests, commits, reviews, issues,
                                       contributors, role, stargazers with taking the sum of each
                                       criterion among contributions in a single repository.
                                     
                                     total-contributors
                                       Order by contributors, role, pull-requests, commits,
                                       reviews, issues, stargazers with taking the sum of each
                                       criterion among contributions in a single repository.
                                     
                                     stargazers
                                       Order by stargazers, contributors, role, pull-requests,
                                       commits, reviews, issues with taking the sum of each
                                       criterion among contributions in a single repository.
                                       This is the default value in case no --sort=ORDER is
                                       specified.
                                     
                                     <sort-criterion>, ...
                                       Order by comma separated criteria.
                                       Available criteria:
                                         commits
                                         contributors
                                         issues
                                         pull-requests
                                         reviews
                                         role
                                         stargazers
                                     
    -r, --render=TEMPLATE            Template file (.erb) to generate the output.  JSON value is
                                     printed without this option.
```

Example
-------

![screenshot](./screenshot.png)

See [#1](https://github.com/tarao/oss-contributions/issues/1) for a complete example.

License
-------

MIT
