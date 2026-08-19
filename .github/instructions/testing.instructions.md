---
description: "Use when writing or running automated tests for the hrz_cmdb Redmine plugin: unit tests for models, functional tests for controllers, fixtures, and the rake test commands."
applyTo: "test/**"
---
# Testing Rules

## Everything testable gets a test

Every model, controller, helper and lib function must have a corresponding test.
A feature is not finished until its tests exist and pass.

## Layout

```
test/
  fixtures/          # YAML test data, one file per table
  unit/              # Model + lib tests      -> hrzcm_*_test.rb, *_helper_test.rb
  functional/        # Controller tests       -> *_controller_test.rb
  integration/       # End-to-end workflows
  test_helper.rb     # Loads Redmine's test_helper, adds CMDB permission helpers
```

`test/test_helper.rb` loads Redmine's own helper via a relative path
(`../../../test/test_helper`), so the plugin must sit under `plugins/hrz_cmdb` of a
Redmine checkout for tests to run.

## Coverage requirements

| Layer | Must cover |
|-------|-----------|
| Model | validations, associations, scopes, instance methods, class methods, callbacks |
| Controller | every action, permission checks (allowed **and** denied), success and error paths, JSON response shape |
| Helper | every public method with varied inputs, including nil/empty |
| Integration | critical user workflows |

## Permission helpers available in tests

Defined in [test/test_helper.rb](test/test_helper.rb):

- `user_with_cmdb_permission(permission_type)` — `'view_cmdb'`, `'edit_cmdb'`, `'edit_basic_data'`
- `user_without_cmdb_permission`
- `setup_user_current(user)`

Because permissions are group-based via `Setting.plugin_hrz_cmdb`, a denial test must
assert the actual response (redirect / 403), not just that the helper returned false.

## Naming

Descriptive, behaviour-based method names:

```ruby
test_should_validate_presence_of_ci_class
test_should_deny_create_ci_without_edit_permission
```

## Commands

The supported way to run the suite is the containerised script — it is the only path that
is verified to work end to end:

```bash
./test/run_container_tests.sh
```

It starts a disposable Podman Redmine container with SQLite, mounts the plugin at
`/usr/src/redmine/plugins/hrz_cmdb`, installs the gems, migrates the test **and**
production databases, runs the plugin tests, verifies that Redmine boots with the plugin
registered, and removes the container on every exit path — including failures.

Markers to look for in the output:

| Marker | Meaning |
|---|---|
| `SCHEMA_OK env=… tables=9` | all plugin tables were created |
| `BOOT_OK plugin=hrz_cmdb version=…` | Redmine starts with the plugin loaded |
| `PRE_PUSH_OK` / `PRE_PUSH_FAILED` | final verdict, mirrored in the exit code |

Overrides: `REDMINE_IMAGE` (default `docker.io/library/redmine:latest`) and
`REDMINE_TEST_CONTAINER` (default `hrz-redmine-test`).

**Podman needs fully qualified image references** — a short name like `redmine:latest`
fails with `short-name … did not resolve to an alias`.

### Run before every push

Delegate the whole run to the [pre-push-tests](../agents/pre-push-tests.agent.md) agent,
which is pinned to Claude Haiku, so a push is always preceded by a real test run:

```
@pre-push-tests
```

### Running the rake tasks directly

Inside an already running Redmine container:

```bash
podman exec -it <redmine-container> bash -lc 'cd /usr/src/redmine && bundle exec rake redmine:plugins:test NAME=hrz_cmdb'
podman exec -it <redmine-container> bash -lc 'cd /usr/src/redmine && bundle exec rake redmine:plugins:test:units NAME=hrz_cmdb'
podman exec -it <redmine-container> bash -lc 'cd /usr/src/redmine && bundle exec rake redmine:plugins:test:functionals NAME=hrz_cmdb'
```

That container needs a `test:` entry in `config/database.yml` and the test-group gems
(`bundle config unset without && bundle install`); the official image ships neither,
because it generates `config/database.yml` only through its own entrypoint.

Run from the Redmine root, not from the plugin directory. Report actual command output —
never claim tests pass without having run them.

## Migrations must stay SQLite-compatible

The containerised run uses SQLite, so migrations may not use vendor-specific DDL.
`ALTER TABLE … ADD PRIMARY KEY` is not valid in SQLite; declare composite keys through
`create_table :t, primary_key: [:a, :b]` instead.

Note that Redmine 6 already applies plugin migrations during the core `db:migrate` run, so
a subsequent `redmine:plugins:migrate` can report "table already exists". The script
therefore asserts the resulting schema via [test/container_boot_check.rb](../../test/container_boot_check.rb)
rather than trusting that task's exit code.

## Fixtures

Fixture files are named after the table (`hrzcm_ci.yml`, `hrzcm_location.yml`). New
tables need a matching fixture file, and columns must use the `j_` / `b_` / `q_` prefixes.
