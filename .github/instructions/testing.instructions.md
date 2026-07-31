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

```bash
# All plugin tests
bundle exec rake redmine:plugins:test NAME=hrz_cmdb

# Units only
bundle exec rake redmine:plugins:test:units NAME=hrz_cmdb

# Functionals only
bundle exec rake redmine:plugins:test:functionals NAME=hrz_cmdb
```

Run from the Redmine root, not from the plugin directory. Report actual command output —
never claim tests pass without having run them.

## Fixtures

Fixture files are named after the table (`hrzcm_ci.yml`, `hrzcm_location.yml`). New
tables need a matching fixture file, and columns must use the `j_` / `b_` / `q_` prefixes.
