# AGENTS.md

Guidance for AI coding agents working on **hrz_cmdb** — a Configuration Management
Database plugin for Redmine 6.1+.

## Project at a glance

| | |
|---|---|
| Type | Redmine plugin (Ruby on Rails engine) |
| Requires | Redmine >= 6.1.0 |
| License | AGPL v3 |
| Version | declared in [init.rb](init.rb) |
| Install path | must live at `<redmine>/plugins/hrz_cmdb` |

Tracks Configuration Items (CIs) across a location hierarchy and a CI-class hierarchy,
and links them to Redmine issues.

## Detailed rules

Read the relevant file before editing:

| Topic | File |
|-------|------|
| Architecture: models, hierarchies, controllers, permissions, integration | [.github/instructions/architecture.instructions.md](.github/instructions/architecture.instructions.md) |
| Headers, purpose comments, method docs, DB naming, permissions | [.github/instructions/plugin-conventions.instructions.md](.github/instructions/plugin-conventions.instructions.md) |
| Translations (all 11 locale files) | [.github/instructions/locales.instructions.md](.github/instructions/locales.instructions.md) |
| Tests and rake commands | [.github/instructions/testing.instructions.md](.github/instructions/testing.instructions.md) |
| Migrations and three-layer validation | [.github/instructions/migrations.instructions.md](.github/instructions/migrations.instructions.md) |
| REST API: endpoints, api.rsb templates, API auth | [.github/instructions/redmine-rest-api.instructions.md](.github/instructions/redmine-rest-api.instructions.md) |

Background architecture notes are in [CLAUDE.md](CLAUDE.md).

## Non-negotiables

1. Never modify the AGPL license header block in any file.
2. Every file has a `Purpose:` comment below the header.
3. Every `def` has documentation covering parameters, values and return.
4. Never delete an existing comment — correct it instead.
5. New UI text goes into all 11 locale files at once.
6. New functionality ships with tests.
7. Every controller action has a permission check.

## Commands

```bash
bundle install                                                        # from Redmine root
RAILS_ENV=production bundle exec rake redmine:plugins:migrate         # migrate
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=hrz_cmdb VERSION=0   # rollback
bundle exec rake redmine:plugins:test NAME=hrz_cmdb                   # tests
```
