---
description: "Use when exposing hrz_cmdb data over the Redmine REST API, adding API-key authentication, JSON/XML endpoints, api.rsb templates, or making existing controller actions callable by external clients and scripts."
---
# Adding a Redmine REST API to hrz_cmdb

## Current state

The plugin has **no REST API**. Controllers render JSON (`render json:`, `format.json`)
but only for the plugin's own AJAX calls inside an authenticated browser session:

- no `accept_api_auth` anywhere → API-key / basic-auth requests are redirected to login
- no `.api.rsb` templates
- CSRF is active, so `POST`/`PUT`/`DELETE` fail without a session token
- routes in [config/routes.rb](config/routes.rb) are custom collection routes
  (`get 'ci/:id'`, `post 'cis'`), not conventional REST resources

## Required steps

### 1. Declare API-authenticated actions

`accept_api_auth` is what enables `X-Redmine-API-Key` / basic auth and skips CSRF for
API formats. It must list every action reachable by an API client:

```ruby
class CmdbController < ApplicationController
  accept_api_auth :show_ci, :create_ci, :update_ci, :destroy_ci
```

Redmine's global "Enable REST web service" setting must be on for keys to work.

### 2. Routes with format

```ruby
resources :hrzcm_cis, controller: 'cmdb', only: [:index, :show, :create, :update, :destroy],
                      format: false
```

Keep the existing UI routes intact — add API routes alongside rather than rewriting the
AJAX contract that [assets/javascripts/hrz_cmdb.js](assets/javascripts/hrz_cmdb.js) depends on.

### 3. Response rendering

Use `.api.rsb` builder templates so XML and JSON come from one source:

```ruby
# app/views/cmdb/show_ci.api.rsb
api.hrzcm_ci do
  api.id      @ci.id
  api.name    @ci.display_name
  api.ci_class(id: @ci.ci_class.id, name: @ci.ci_class.b_name_abbr) if @ci.ci_class
end
```

Respond with `format.api` and keep the current `format.json` branch for the UI.

### 4. Pagination on collections

Follow Redmine's convention: accept `offset` / `limit` (or `page`), cap `limit` at 100,
and return `total_count`, `offset`, `limit` alongside the collection.

### 5. Status codes

`201` + `Location` on create, `204` on successful update/delete, `422` with an `errors`
array on validation failure, `403` on permission denial, `404` on missing record.
Do not return `200` with `{success: false}` for API requests.

## Security requirements — non-negotiable

- **Every** API action keeps its `before_action` permission check. `accept_api_auth`
  authenticates, it does not authorize.
- Group-based CMDB permissions (`HrzCmdb::PermissionHelper`) must be verified to behave
  correctly for API users, whose `User.current` is set from the API key.
- Never expose CI data to a user lacking `view_cmdb`; never accept writes from a user
  lacking `edit_cmdb` / `edit_basic_data`.
- Whitelist attributes with strong parameters — do not pass raw `params` into
  `create` / `update`.
- Do not leak `created_by` / `updated_by` user details beyond id and name.

## Tests

Every API action needs a functional test asserting: authenticated success, unauthenticated
rejection, permission-denied rejection, response body shape, and status code.
