---
description: "Use when working on the hrz_cmdb REST API: API-key authentication, JSON/XML endpoints, api.rsb templates, pagination, status codes, or making a further controller action callable by external clients and scripts."
---
# The hrz_cmdb Redmine REST API

## Current state

The plugin **has** a REST API since version 0.8.0. It is not a separate namespace — the
existing controllers serve both the browser UI and API clients.

| Controller | API actions |
|---|---|
| `CmdbController` | index/show/create/update/destroy for locations, CI classes, CIs, lifecycle statuses, external systems |
| `CmdbBasicDataController` | index/show/create/update/destroy for location hierarchy levels |
| `IssueCisController` | index/create/destroy for the CIs of an issue |

Redmine's global "Enable REST web service" setting must be on for API keys to work.

## How the UI and the API are kept apart

`format.api` is an alias for `any(:xml, :json)`. The plugin's own AJAX calls send
`Accept: application/json` **without** a format extension in the URL, so a `format.api`
branch would swallow them and break the web interface.

Therefore every API branch is an explicit early return guarded by `api_request?`, placed
**before** the existing `respond_to` block:

```ruby
def show_ci
  return render(:action => 'show_ci') if api_request?

  respond_to do |format|
    format.html { ... }
    format.json { ... }   # unchanged UI contract
  end
end
```

`api_request?` is true only for a `params[:format]` of `json` or `xml`, i.e. only for a
`.json` / `.xml` URL suffix. Never replace these guards with `format.api`.

## Rules for adding a further API action

### 1. Declare it in `accept_api_auth`

`accept_api_auth` is what enables `X-Redmine-API-Key` / basic auth and skips CSRF for
API formats. It must list every action reachable by an API client:

```ruby
class CmdbController < ApplicationController
  accept_api_auth :show_ci, :create_ci, :update_ci, :destroy_ci
```

It authenticates only — the `before_action` permission checks still do the authorising.

### 2. Routes

Rails appends `(.:format)` to every route, so the existing UI routes already accept
`.json` / `.xml`. Pure API collection endpoints are declared in the `collection do … end`
block of `resources :cmdb`:

```ruby
get 'cis', action: :index_cis
```

Keep the existing UI routes intact — add API routes alongside rather than rewriting the
AJAX contract that [assets/javascripts/hrz_cmdb.js](assets/javascripts/hrz_cmdb.js) depends on.

### 3. Response rendering

Render through an `.api.rsb` builder template, never `render json:`, so that XML and JSON
come from one source. The serialisation itself lives in `CmdbHelper` as a
`render_api_<entity>(record, api)` method, following Redmine's own `render_api_attachment`
pattern, so that the show template and the index template share one definition:

```ruby
# app/helpers/cmdb_helper.rb
def render_api_ci(ci, api, with_issues = false)
  api.hrzcm_ci do
    api.id ci.id
    api.ci_class(:id => ci.ci_class.id, :name => ci.ci_class.b_name_abbr) if ci.ci_class
  end
end

# app/views/cmdb/show_ci.api.rsb
render_api_ci(@ci, api, true)
```

Controllers other than `CmdbController` declare `helper :cmdb` to reach those methods.

`.api.rsb` files are Ruby, so they carry the normal AGPL header and `# Purpose:` comment.
The last line must be code, not a comment — Redmine appends `; self.output_buffer = …` to
the template source, and a trailing comment would swallow it.

### 4. Pagination on collections

```ruby
@offset, @limit = api_offset_and_limit          # Redmine caps limit at 100, default 25
@cis_count = scope.count
@cis = scope.limit(@limit).offset(@offset).to_a
```

```ruby
api.array :hrzcm_cis, api_meta(:total_count => @cis_count, :offset => @offset, :limit => @limit) do
```

### 5. Status codes

Use Redmine's response helpers: `render_api_ok` (204), `render_validation_errors` (422),
`render_api_errors('message')` (422 for business rules), `render_404`, `render_403`.

Create returns `:status => :created` plus a `Location` header built with
`url_for(..., :format => params[:format], :only_path => false)` — the `resources :cmdb`
route helpers are ambiguous, so do not use named helpers there.

Do not return `200` with `{success: false}` for API requests.

### 6. Attribute naming

Request and response bodies use the real column names (`b_name_full`, `j_ci_class_id`, …)
so that a create payload looks like a read payload. Associations are nested objects with
`id` and `name` only.


## Security requirements — non-negotiable

- **Every** API action keeps its `before_action` permission check. `accept_api_auth`
  authenticates, it does not authorize.
- Group-based CMDB permissions (`HrzCmdb::PermissionHelper`) apply unchanged to API users,
  whose `User.current` is set from the API key.
- Issue-scoped actions must load the issue through `Issue.visible`, so that issue
  visibility rules apply and not only the project permission.
- Never expose CI data to a user lacking `view_cmdb`; never accept writes from a user
  lacking `edit_cmdb` / `edit_basic_data`.
- Whitelist attributes with strong parameters — do not pass raw `params` into
  `create` / `update`.
- Do not leak `created_by` / `updated_by` user details beyond id and name.
- Treat every id coming from a request body as untrusted: rescue
  `ActiveRecord::RecordNotFound` and answer `render_404`.

## Tests

API tests are integration tests under `test/integration/api_test/`, subclassing
`Redmine::ApiTest::Base`, which enables the REST setting and provides `credentials(login)`.

Every API action needs a test asserting: authenticated success, unauthenticated rejection
(401), permission-denied rejection (403), response body shape, and status code
(200 / 201 / 204 / 404 / 422).
