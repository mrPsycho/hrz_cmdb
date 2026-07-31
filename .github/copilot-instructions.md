# hrz_cmdb — Copilot Instructions

**hrz_cmdb** is a Configuration Management Database plugin for **Redmine 6.1+** (Ruby on
Rails engine, AGPL v3). It must live at `<redmine>/plugins/hrz_cmdb`. It tracks
Configuration Items (CIs) across a location hierarchy and a CI-class hierarchy and links
them to Redmine issues.

## Non-negotiables

1. **Never modify the AGPL license header block** in any file. Copy it verbatim from an
   existing file of the same type; it ends with the `eohdr-#` marker.
2. **Every file has a `Purpose:` comment** directly below the header —
   `# Purpose:` (rb), `<%# Purpose: %>` (erb), `// Purpose:` (js), `/* Purpose: */` (css).
3. **Every `def` is documented** immediately above it: what it does, every parameter with
   its possible values and meaning, the return value, and side effects.
4. **Never delete an existing comment.** Correct or supplement it instead — and update any
   comment your change makes wrong, in the same edit.
5. **New user-visible text goes into all 11 locale files at once**: `bg, de, el, en, hr,
   hu, pl, ro, ru, tr, uk`. Never a subset.
6. **New functionality ships with tests.** A feature is not done until its tests exist and
   pass — and pass means actually run, never assumed.
7. **Every controller action has a permission check** (`before_action`).
8. **Required fields are validated in three layers**: `change_column_null` in a migration,
   `validates … presence: true` in the model, and `required: true` plus a
   `<span class="required">*</span>` marker in the view.

## Database naming

Tables `hrzcm_*`; integer fields `j_*`; text fields `b_*`; boolean/data fields `q_*`;
foreign keys `j_*_id`. Because these do not follow Rails defaults, models set
`self.table_name` and every association names `class_name:` and `foreign_key:` explicitly.

## Detailed rules

Read the matching file before editing:

| Topic | File |
|-------|------|
| Architecture: models, hierarchies, controllers, permissions, integration | [.github/instructions/architecture.instructions.md](.github/instructions/architecture.instructions.md) |
| Headers, purpose comments, method docs, DB naming, permissions | [.github/instructions/plugin-conventions.instructions.md](.github/instructions/plugin-conventions.instructions.md) |
| Translations (all 11 locale files) | [.github/instructions/locales.instructions.md](.github/instructions/locales.instructions.md) |
| Tests and rake commands | [.github/instructions/testing.instructions.md](.github/instructions/testing.instructions.md) |
| Migrations and three-layer validation | [.github/instructions/migrations.instructions.md](.github/instructions/migrations.instructions.md) |
| Adding a REST API | [.github/instructions/redmine-rest-api.instructions.md](.github/instructions/redmine-rest-api.instructions.md) |

Background notes: [CLAUDE.md](CLAUDE.md) · agent overview: [AGENTS.md](AGENTS.md).

## Commands

Run from the **Redmine root**, not from the plugin directory:

```bash
bundle install                                                                          # dependencies
RAILS_ENV=production bundle exec rake redmine:plugins:migrate                            # migrate
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=hrz_cmdb VERSION=0    # rollback
bundle exec rake redmine:plugins:test NAME=hrz_cmdb                                      # all tests
bundle exec rake redmine:plugins:test:units NAME=hrz_cmdb                                # units only
bundle exec rake redmine:plugins:test:functionals NAME=hrz_cmdb                          # functionals only
```

User-visible changes bump `version` in [init.rb](init.rb).
