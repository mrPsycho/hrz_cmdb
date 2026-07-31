---
description: "Use when adding a database migration, changing a schema, adding a column, or making a field required in the hrz_cmdb plugin. Covers numbering, reversibility and the mandatory three-layer validation."
applyTo: "db/migrate/**"
---
# Migration Rules

## Numbering and class name

Files are sequentially numbered with three digits: `012_<snake_case_description>.rb`.
The class name is the CamelCase form of the description, and it inherits from the
Rails version used by Redmine 6.1:

```ruby
class AddNotNullConstraintToCiClassId < ActiveRecord::Migration[6.1]
```

Never renumber or edit an already-released migration — add a new one.

## Always reversible

Use `up` / `down` (or a `change` that is genuinely reversible). `down` must restore the
previous state so `VERSION=0` rollback works:

```bash
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=hrz_cmdb
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=hrz_cmdb VERSION=0
```

## Backfill before constraining

Adding a NOT NULL constraint to an existing column requires cleaning existing rows first,
otherwise the migration fails on live data — see
[db/migrate/011_add_not_null_constraint_to_ci_class_id.rb](db/migrate/011_add_not_null_constraint_to_ci_class_id.rb).

## Three-layer validation for required fields

Making a field required means changing **all three** layers in the same task:

1. **Database**
   ```ruby
   change_column_null :hrzcm_ci, :j_ci_class_id, false
   ```
2. **Model**
   ```ruby
   validates :j_ci_class_id, presence: true
   ```
3. **View**
   ```erb
   <%= label_tag :j_ci_class_id, l('hrz_cmdb.label_ci_class') %> <span class="required">*</span>
   <%= select_tag 'j_ci_class_id', options, required: true %>
   ```

A required field implemented at only one or two layers is incomplete.

## Naming

New columns follow the prefix scheme: `j_*` integer, `b_*` text, `q_*` boolean/data,
`j_*_id` foreign key. Tables are `hrzcm_*`.

Add explicit indexes for foreign keys and for any column used in uniqueness rules.
