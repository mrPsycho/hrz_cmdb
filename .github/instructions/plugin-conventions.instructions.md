---
description: "Use when creating or editing any source file in the hrz_cmdb Redmine plugin: license headers, purpose comments, method documentation, database/column naming prefixes, and model callback conventions."
applyTo: "**/*.{rb,erb,rsb,js,css}"
---
# hrz_cmdb Source File Conventions

## 1. License header — mandatory, never modify

Every `.rb`, `.erb`, `.rsb`, `.js` and `.css` file starts with the AGPL v3 header.
The canonical text is in [.header.txt](.header.txt); the rendered block is 91 characters
wide and its last line ends with the `eohdr-#` marker.

**Never rewrite, reflow, reformat or "improve" this header.** When creating a new file,
copy the header verbatim from an existing file of the same type (e.g.
[app/models/hrzcm_ci.rb](app/models/hrzcm_ci.rb) for Ruby) and change nothing.

Comment syntax per file type:

| Type | Header comment char | Purpose comment |
|------|--------------------|-----------------|
| `.rb`  | `#`      | `# Purpose: <description>` |
| `.erb` | `<%# %>` | `<%# Purpose: <description> %>` |
| `.rsb` | `#`      | `# Purpose: <description>` |
| `.js`  | `//`     | `// Purpose: <description>` |
| `.css` | `/* */`  | `/* Purpose: <description> */` |

`.api.rsb` templates are Ruby, so they use `#`. Their **last line must be code, not a
comment** — Redmine appends `; self.output_buffer = api.output` to the template source,
and a trailing comment would swallow it.

## 2. Purpose comment — mandatory

Directly below the header, before any code, every file states what it does:

```ruby
#-------------------------------------------------------------------------------------eohdr-#
# Purpose: Model for Configuration Items (CIs) - individual hardware/software inventory items.
#          Tracks physical and virtual assets with location, class, lifecycle status, and external system links.
```

Continuation lines are indented to align under the text after `# Purpose: `.

## 3. Method documentation — mandatory for every `def`

Immediately above each `def`, document: what it does, every parameter with its
possible values and meaning, the return value, and any side effects.

```ruby
# Checks if a user has a specific permission based on group membership.
# Admin users always have all permissions.
# Parameter user: User instance to check permissions for
# Parameter permission_type: String permission type
#   * 'view_cmdb' ............... view CMDB data
#   * 'edit_cmdb' ............... edit locations and CIs
#   * 'edit_basic_data' ......... edit CI classes, lifecycle statuses, and external systems
# Returns: Boolean indicating if user has the specified permission
def user_has_permission?(user, permission_type)
```

Also document side effects (DB writes, external calls) and raised exceptions where relevant.

## 4. Never delete comments

Existing comments are corrected or supplemented, never removed. If code changes make a
comment wrong, update the comment in the same edit.

## 5. Database naming

| Element | Rule | Example |
|---------|------|---------|
| Table | `hrzcm_*` | `hrzcm_ci`, `hrzcm_location` |
| Integer field | `j_*` | `j_level`, `j_sort` |
| Text field | `b_*` | `b_name_full`, `b_name_abbr`, `b_comment` |
| Boolean/data field | `q_*` | `q_active` |
| Foreign key | `j_*_id` | `j_ci_class_id`, `j_location_id` |

Models set `self.table_name` explicitly and declare associations with explicit
`class_name:` and `foreign_key:` because the FK names do not follow Rails defaults:

```ruby
belongs_to :ci_class, class_name: 'HrzcmCiClass', foreign_key: 'j_ci_class_id', optional: true
```

## 6. Audit columns

Every model tracks `created_by` / `created_on` and `updated_by` / `updated_on` via
`before_create :set_creator` and `before_save :set_updater`, sourcing the user from
`User.current&.id`. New models must follow the same pattern.

## 7. Permissions

CMDB-wide access uses the group-based helper, not Redmine roles:

```ruby
HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'edit_cmdb')
```

Issue-level CI access (`view_issue_cis`, `manage_issue_cis`) uses standard Redmine role
permissions declared in [init.rb](init.rb) under `project_module :cmdb`.

Any new controller action must be covered by a `before_action` permission check. Never
add an action that reads or writes CMDB data without one.

## 8. Version bump

User-visible changes bump `version` in [init.rb](init.rb).
