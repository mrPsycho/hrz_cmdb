# CMDB Plugin for Redmine

A Configuration Management DataBase (CMDB) plugin for Redmine 6.1+ where you can keep an inventory of your software and hardware items and connect them to tickets.

<img src="assets/images/cmdb_logo.svg" alt="CMDB Logo" width="300" height="300" style="zoom:25%; max-width:50%; max-height:40em;" />

## Features

- Hierarchy of locations, tree structure
- Hierarchy of Configuration Item classes (CI classes), tree structure
- Multilingual
- Fine-grained access control
- Documentation links 
- Tiki (TikiWiki) integration
- REST API (JSON and XML) for all CMDB data and for the CIs of a ticket

## Installation

This is the standard Redmine plugin installation procedure.

### Testing in a Redmine container

If Redmine is running inside a container, prefer Podman and execute the test commands
inside the container so the Redmine app and Bundler environment match the runtime
stack.

```bash
# ensure the plugin is mounted into the Redmine container
ls /usr/src/redmine/plugins/hrz_cmdb

# run the full plugin test suite in the Redmine container
podman exec -it <redmine-container> bash -lc 'cd /usr/src/redmine && bundle exec rake redmine:plugins:test NAME=hrz_cmdb'

# run only the functional tests
podman exec -it <redmine-container> bash -lc 'cd /usr/src/redmine && bundle exec rake redmine:plugins:test:functionals NAME=hrz_cmdb'

# run only the unit tests
podman exec -it <redmine-container> bash -lc 'cd /usr/src/redmine && bundle exec rake redmine:plugins:test:units NAME=hrz_cmdb'
```

For a disposable test run, use the bundled script. It starts a Podman Redmine container
on SQLite, installs the plugin, migrates the databases, runs the test suite, verifies
that Redmine boots with the plugin and removes the container afterwards:

```bash
./test/run_container_tests.sh
```

Podman needs the fully qualified image reference, which the script uses by default
(`docker.io/library/redmine:latest`, override with `REDMINE_IMAGE`).

The plugin path inside the container must be `/usr/src/redmine/plugins/hrz_cmdb`.
This is the container-safe equivalent of running the plugin tests from a local
Redmine checkout.

1. Copy the plugin into the Redmine plugin dirctory:

   a) If it is already in the current directory:

   ```bash
   cp -r hrz_cmdb /path/to/redmine/plugins/.
   ```
   
   b) If you want a fresh clone of the latest version:
   
   ```bash
   cd /path/to/redmine/plugins
   git clone https://github.com/franz-ap/hrz_cmdb
   ```


2. Install pre-requisites:

   ```bash
   bundle install
   ```

3. Database migration:
   ```bash
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate
   ```

4. Restart Redmine


## Configuration

### Access rights CMDB page

You can skip this step, if only Redmine administrators need to work with the CMDB: define CIs, etc. In that case you would not be able to delegate a part of that CMDB work to your colleagues.

1. Login as Redmine administrator.

2. Make sure, that you have created at least one standard Redmine group.

3. Go to Administration → Plugins

4. Near "CMDB AF" click "Configure"

5. Assign one or more Redmine groups to the three access levels:
   - **View CMDB**: Read only access to the CMDB page
   - **Edit CMDB**: Edit locations and CIs. This right implies "View CMDB". So, there is no need to add persons to both groups.
   - **Edit basic data**:  Hierarchy levels of locations, CI classes. This right implies "View CMDB". So, there is no need to add persons to both groups.

### User rights in tickets

1. Go to Administration → Roles and permissions

2. Grant these CMDB rights to one or more roles:
   - **View CIs in issues**: View the list of CIs that are connected to a ticket.
   - **Manage CIs in issues**: Connect CIs to tickets, remove them from a ticket.

### Add the CMDB module to Redmine project(s)

Enable the module "CMDB" in the settings of one or more Redmine projects, where you wish to connect Configuration Items (CIs) to tickets/issues.
Otherwise you could use the CMDB only standalone.


### Initial data setup

Automatic creation of seed data is available:

- Menu: "CMDB"
- Open folder "Settings" → open "Seed Data"
- There click on the "Add Seed Data" button.

If you prefer to do that manually:

1. **Create at least one location hierarchy level**:
   - Menu: "CMDB"
   - Open folders "Basic Data" → "Location hierarchy"
   - Click on "Create new hierarchy level"
   - Enter data about a new location type into the form, then click "Create new entry".
2. **Create at least one location**:
   - Click on "Create new location"
   - Enter data into the form and choose one of the location types. Click "Create new entry".

In case you do not need all of the seed values and want to get rid of the unused ones (after entering your CIs): 

* Click on the "Remove Unused Seed Data" button.

You can repeat these Add/Remove Seed Data steps whenever you need, even after manual configuration.



## Languages

The plugin supports the following languages:

- bg: български - Bulgarian

- de: Deutsch - German
- el: Ελληνικά - Greek
- en: English
- fr: Français - French    (soon)
- hr: Hrvatski - Croatian
- hu: Magyar - Hungarian
- it: Italiano - Italian   (soon)
- pl: Polski - Polish
- ro: Română - Romanian
- ru: русский - Russian
- sk: slovenský - Slovak   (soon)
- sl: Slovenščina - Slovenian  (soon)
- tr: Türkçe - Turkish
- ua: українська - Ukrainian 


## REST API

The plugin exposes its data through the standard Redmine REST API. Enable
*Administration → Settings → API → Enable REST web service* first. Authenticate with an
API key (`X-Redmine-API-Key` header or `key=` parameter) or HTTP basic auth, and append
`.json` or `.xml` to the URL — an `Accept` header alone is not enough.

Access is governed by the same permissions as the web interface: the group based
`view_cmdb` / `edit_cmdb` / `edit_basic_data` settings for the CMDB endpoints, and the
project roles `view_issue_cis` / `manage_issue_cis` for the issue endpoints.

Collections support `offset`, `limit` (default 25, maximum 100) and `page`, and return
`total_count`, `offset` and `limit` alongside the records.

| Resource | Endpoints |
|---|---|
| Locations | `GET /cmdb/locations`, `GET /cmdb/location/:id`, `POST /cmdb/location`, `PUT /cmdb/location/:id`, `DELETE /cmdb/location/:id` |
| CI classes | `GET /cmdb/ci_classes`, `GET /cmdb/ci_class/:id`, `POST /cmdb/ci_classes`, `PUT /cmdb/ci_classes/:id`, `DELETE /cmdb/ci_classes/:id` |
| Configuration items | `GET /cmdb/cis`, `GET /cmdb/ci/:id`, `POST /cmdb/cis`, `PUT /cmdb/cis/:id`, `DELETE /cmdb/cis/:id` |
| Lifecycle statuses | `GET /cmdb/lifecycle_statuses`, `GET /cmdb/lifecycle_status/:id`, `POST /cmdb/lifecycle_statuses`, `PUT /cmdb/lifecycle_statuses/:id`, `DELETE /cmdb/lifecycle_statuses/:id` |
| External systems | `GET /cmdb/external_systems`, `GET /cmdb/ext_sys/:id`, `POST /cmdb/external_systems`, `PUT /cmdb/external_systems/:id`, `DELETE /cmdb/external_systems/:id` |
| Location hierarchy levels | `GET /cmdb_basic_data`, `GET /cmdb_basic_data/location_hierarchies/:id`, `POST /cmdb_basic_data/location_hierarchies`, `PUT /cmdb_basic_data/location_hierarchies/:id`, `DELETE /cmdb_basic_data/location_hierarchies/:id` |
| CIs of an issue | `GET /issues/:issue_id/cis`, `POST /issues/:issue_id/cis`, `DELETE /issues/:issue_id/cis/:ci_id` |

Filters: locations accept `j_type_id` and `j_part_of1_id`, CI classes accept
`j_subclass_of_id`, CIs accept `j_ci_class_id`, `j_location_id`, `j_status_id` and
`b_tag_serial`.

Request bodies use the database field names, wrapped in the object name:

```bash
curl -X POST https://redmine.example.org/cmdb/cis.json \
     -H "Content-Type: application/json" \
     -H "X-Redmine-API-Key: <your api key>" \
     -d '{"ci": {"b_name_full": "Database Server 02", "b_name_abbr": "DB02",
                 "j_ci_class_id": 2, "j_location_id": 3, "j_status_id": 2}}'
```

Responses: `201 Created` with the new record (and a `Location` header) for `POST`,
`204 No Content` for `PUT` and `DELETE`, `422 Unprocessable Entity` with an `errors` list
for validation failures, `403` when a permission is missing and `404` for unknown records.

## Uninstall

1. Undo database migration:
   ```bash
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=hrz_cmdb VERSION=0
   ```

2. Remove plugin directory:
   ```bash
   rm -rf /path/to/redmine/plugins/hrz_cmdb
   ```

3. Restart Redmine.

## Support

Please file an issue: https://github.com/franz-ap/hrz_cmdb/issues

## License

![Logo GNU Affero General Public License](assets/images/agplv3-155x51.png)

This program is free software: you can redistribute it and/or modify it under the terms
of the **GNU Affero General Public License** as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

## Versions

The latest version can be found here: https://github.com/franz-ap/hrz_cmdb

In case you wonder, why there is a *"hrz"* prefix: To avoid a potential name clash with other CMDBs. You can read it as *"Home-brewed Redmine-add-on Zone"*.

###### Version 0.8.0  31.07.2026

Adds a REST API, see the *REST API* section above. Every entity that can be maintained in
the web interface can now also be read and written by external clients and scripts, using
an API key or HTTP basic auth, in JSON or XML.

Also fixed: the CIs of a ticket were only protected by the project permission, not by the
issue visibility rules. Private tickets and "own issues only" roles are now honoured.

###### Version 0.7.0  26.10.2025

The Minimum Viable Product. 

It is very basic, but usable. A proof-of-concept. Expect improved versions very soon.
