---
description: "Use when you need to understand how hrz_cmdb is put together before changing it: plugin structure, the two hierarchies (locations, CI classes), models and associations, controllers and routes, the group-based permission system, views, frontend and integration points."
applyTo: "**"
---
# hrz_cmdb Architecture

Configuration Management Database for Redmine 6.1+. Tracks Configuration Items (CIs)
across a location hierarchy and a CI-class hierarchy, and links them to Redmine issues.

## Plugin structure

| Path | Role |
|------|------|
| [init.rb](init.rb) | Plugin registration: metadata, `version`, top menu entry, settings defaults, `project_module :cmdb`. Requires every `lib/**/*.rb` at the bottom — new lib files need no manual require. |
| [config/routes.rb](config/routes.rb) | All routes: CMDB collection actions, basic data scope, CI-issue nesting. |
| `app/models/hrzcm_*.rb` | Data model. |
| `app/controllers/` | `CmdbController`, `CmdbBasicDataController`, `IssueCisController`. |
| `app/views/` | `cmdb/`, `cmdb_basic_data/`, `issue_cis/`, `settings/`. |
| `lib/hrz_cmdb/` | `permission_helper.rb`, `seed_data.rb`, `seed_data_helper.rb`, `hooks/`, `patches/`. |
| `assets/` | `javascripts/hrz_cmdb.js`, `javascripts/issue_cis.js`, `stylesheets/hrz_cmdb.css`. |

The plugin must be installed at `<redmine>/plugins/hrz_cmdb` — the test helper and asset
paths depend on that exact directory name.

## Two hierarchies

**Location hierarchy**

- `HrzcmLocatHier` (`hrzcm_locat_hier`) defines the hierarchy *levels/types*.
  `j_level` is unique and ordered via `scope :ordered_by_level`.
- `HrzcmLocation` (`hrzcm_location`) holds the actual locations. Each location has a
  mandatory type (`j_type_id`) and **two optional parents** (`j_part_of1_id`,
  `j_part_of2_id`) via `parent1` / `parent2` + `children1` / `children2`. The dual-parent
  design is intentional — code that walks the location tree must consider both edges.
- `scope :root_locations` = both parent columns `nil`.

**CI class hierarchy**

- `HrzcmCiClass` (`hrzcm_ci_class`) is a single-parent tree via `j_subclass_of_id`
  (`parent_class` / `subclasses`), with `scope :root_classes` and `:for_parent`.

Both hierarchies use `dependent: :restrict_with_error` — a node with children or with
dependent CIs cannot be deleted. Deletion failures are expected behaviour, not bugs.

## Remaining models

| Model | Table | Notes |
|-------|-------|-------|
| `HrzcmCi` | `hrzcm_ci` | The CI itself. `belongs_to` `ci_class` (`j_ci_class_id`, required by validation), `location` (`j_location_id`), `lifecycle_status` (`j_status_id`). Carries `b_producer`, `b_model`, `b_tag_serial`, `b_url_doc`. |
| `HrzcmLifecycleStatus` | `hrzcm_lifecycle_status` | Status values (planning, active, decommissioned, …), keyed by unique `b_key`. |
| `HrzcmExtSys` | `hrzcm_ext_sys` | External systems. `j_redmine_user_id` is required and unique — an external system is identified by the Redmine user it authenticates as. |
| `HrzcmCiExt` | `hrzcm_ci_ext` | CI ↔ external system mapping; `b_key_ext` unique per (`j_ci_id`, `j_ext_sys_id`). |
| `HrzcmCiIssue` | `hrzcm_ci_issues` | Junction CI ↔ Redmine issue. **Uses plain `ci_id` / `issue_id`, not `j_*_id`**, because it joins Redmine core. Unique per (`ci_id`, `issue_id`). |

`HrzcmCi` reaches issues and external systems through `has_many :through`
(`issues` via `ci_issues`, `ext_systems` via `ci_ext_mappings`).

## Controllers and routes

- **`CmdbController`** — CRUD for locations, CI classes, CIs, lifecycle statuses and
  external systems. Because all five entity types live in one controller, routes are
  declared as explicit `collection do … end` actions (`new_ci`, `show_ci`, `create_ci`,
  `update_ci`, `destroy_ci`, and the same pattern per entity) rather than nested
  `resources`. Follow that naming when adding an entity. `tree_data` feeds the jsTree
  navigation and dispatches on `parent_id`.
- **`CmdbBasicDataController`** — location hierarchy levels plus seed data management
  (`show_seed_data_management`, `add_seed_data`, `remove_unused_seed_data`), backed by
  [lib/hrz_cmdb/seed_data.rb](lib/hrz_cmdb/seed_data.rb) and
  [lib/hrz_cmdb/seed_data_helper.rb](lib/hrz_cmdb/seed_data_helper.rb).
- **`IssueCisController`** — `available_cis`, `index`, `create`, `destroy` under
  `/issues/:issue_id/cis`. The issue is loaded with `Issue.visible`, so issue visibility
  rules apply on top of the project permission.

## Two permission systems

They are deliberately different — do not mix them up.

1. **CMDB-wide, group-based** (not Redmine roles). Groups are configured per permission
   in `Setting.plugin_hrz_cmdb` (`view_cmdb_groups`, `edit_cmdb_groups`,
   `edit_basic_data_groups`) via Administration → Plugins → CMDB AF → Configure, and
   checked with:

   ```ruby
   HrzCmdb::PermissionHelper.user_has_permission?(User.current, 'edit_cmdb')
   ```

   Admins always pass. This guards `CmdbController` and `CmdbBasicDataController`, and
   the top-menu entry in [init.rb](init.rb).

2. **Issue-level, role-based**, declared in `project_module :cmdb`:
   `view_issue_cis` (read-only) and `manage_issue_cis`. These guard `IssueCisController`
   and require the CMDB module to be enabled on the project.

Every controller action needs a permission check.

## Views and frontend

- [app/views/cmdb/index.html.erb](app/views/cmdb/index.html.erb) is the single CMDB page;
  the jsTree on the left calls `tree_data`, and selecting a node loads a
  `_*_details.html.erb` partial into the right pane by AJAX.
- Per entity there is a `_<entity>_form.html.erb` and a `_<entity>_details.html.erb`.
  A new entity type needs both plus a `tree_data` branch.
- [assets/javascripts/hrz_cmdb.js](assets/javascripts/hrz_cmdb.js) drives tree navigation
  and the AJAX CRUD calls; [assets/javascripts/issue_cis.js](assets/javascripts/issue_cis.js)
  drives the CI selection modal on issue pages.

## REST API

Since 0.8.0 the same three controllers also serve JSON and XML to external clients. There
is no separate API controller: `accept_api_auth` lists the API-reachable actions, and each
action has an early `return … if api_request?` branch **before** its `respond_to` block.
`format.api` is deliberately not used, because it aliases `any(:xml, :json)` and would
capture the UI's own `Accept: application/json` AJAX calls.

Rendering goes through `*.api.rsb` builder templates next to the HTML views; the actual
serialisation lives in `render_api_<entity>(record, api)` methods in
[app/helpers/cmdb_helper.rb](app/helpers/cmdb_helper.rb), so index and show share it.
Details and rules: [redmine-rest-api.instructions.md](.github/instructions/redmine-rest-api.instructions.md).

## Integration points

- **Issues** — [lib/hrz_cmdb/patches/issue_patch.rb](lib/hrz_cmdb/patches/issue_patch.rb)
  adds `has_many :cis` to `Issue`;
  [lib/hrz_cmdb/patches/issues_helper_patch.rb](lib/hrz_cmdb/patches/issues_helper_patch.rb)
  extends `IssuesHelper`;
  [lib/hrz_cmdb/hooks/view_issues_hook.rb](lib/hrz_cmdb/hooks/view_issues_hook.rb) injects
  the CI section into issue show/edit views. Extend the patches, never edit Redmine core.
- **TikiWiki** — optional, base URL from the `tiki_base_url` plugin setting.

## Audit columns

Every model has `created_by` / `created_on` and `updated_by` / `updated_on`, filled by
`before_create :set_creator` and `before_save :set_updater` from `User.current&.id`.
New models must follow the same pattern.
