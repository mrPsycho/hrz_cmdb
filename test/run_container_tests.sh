#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------#
# Redmine CMDB plugin: Configuration Management DataBase                                    #
# Copyright (C) 2025 Franz Apeltauer                                                        #
#                                                                                           #
# This program is free software: you can redistribute it and/or modify it under the terms   #
# of the GNU Affero General Public License as published by the Free Software Foundation,    #
# either version 3 of the License, or (at your option) any later version.                   #
#                                                                                           #
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; #
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. #
# See the GNU Affero General Public License for more details.                               #
#                                                                                           #
# You should have received a copy of the GNU Affero General Public License                  #
# along with this program.  If not, see <https://www.gnu.org/licenses/>.                    #
#-------------------------------------------------------------------------------------eohdr-#
# Purpose: End-to-end pre-push test run for the hrz_cmdb plugin inside a disposable Podman
#          Redmine container backed by SQLite. Installs the plugin, migrates the test and
#          production databases, runs the plugin test suite and verifies that Redmine still
#          boots with the plugin loaded. The container is always removed afterwards.

set -uo pipefail

IMAGE="${REDMINE_IMAGE:-docker.io/library/redmine:latest}"
CONTAINER="${REDMINE_TEST_CONTAINER:-hrz-redmine-test}"
PLUGIN_NAME="hrz_cmdb"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REDMINE_ROOT="/usr/src/redmine"

# Removes the disposable test container. Runs on every exit path, including failures,
# so no test container is ever left behind.
cleanup() {
  podman rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Runs a shell snippet inside the Redmine container from the Redmine root.
# $1: shell code to execute.
in_container() {
  podman exec "$CONTAINER" bash -lc "cd $REDMINE_ROOT && $1"
}

# Prints a step banner so the log of a delegated run stays readable.
# $1: step description.
step() {
  echo ""
  echo "=== $1 ==="
}

# Migrates one Rails environment and asserts the resulting schema.
# Redmine 6 already applies the plugin migrations during the core db:migrate run, so the
# redmine:plugins:migrate task can legitimately report "already exists"; the resulting
# schema is asserted by container_boot_check.rb instead of trusting that task's exit code.
# $1: RAILS_ENV value, 'test' or 'production'.
migrate_env() {
  local env="$1"
  in_container "RAILS_ENV=$env bundle exec rake db:migrate" >/dev/null || return 1
  in_container "RAILS_ENV=$env bundle exec rake redmine:plugins:migrate NAME=$PLUGIN_NAME" >/dev/null 2>&1
  in_container "RAILS_ENV=$env bundle exec rails runner plugins/$PLUGIN_NAME/test/container_boot_check.rb" || return 1
}

step "Starting disposable Redmine container ($IMAGE)"
podman rm -f "$CONTAINER" >/dev/null 2>&1 || true
podman run -d --name "$CONTAINER" \
  -v "$PLUGIN_DIR":"$REDMINE_ROOT/plugins/$PLUGIN_NAME":Z \
  -e SECRET_KEY_BASE=hrz_cmdb_test_secret_key_base \
  "$IMAGE" tail -f /dev/null >/dev/null || exit 1

step "Verifying plugin is mounted"
in_container "test -f plugins/$PLUGIN_NAME/init.rb && echo PLUGIN_MOUNTED" || exit 1

step "Configuring SQLite databases"
# The image only generates config/database.yml through its own entrypoint, which this
# script bypasses, so both environments are written explicitly here.
in_container "mkdir -p sqlite files && printf 'production:\n  adapter: sqlite3\n  database: \"sqlite/redmine.db\"\n  encoding: \"utf8\"\n\ntest:\n  adapter: sqlite3\n  database: \"sqlite/redmine_test.db\"\n  encoding: \"utf8\"\n' > config/database.yml && cat config/database.yml" || exit 1

step "Installing gems (including the test group)"
in_container "bundle config unset without >/dev/null 2>&1; bundle install --quiet" || exit 1

step "Migrating the test database (Redmine core + plugin)"
migrate_env test || exit 1

step "Running the plugin test suite"
in_container "RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=$PLUGIN_NAME"
TEST_STATUS=$?

step "Migrating the production database (install check)"
migrate_env production || exit 1

step "Verifying Redmine boots with the plugin loaded"
in_container "RAILS_ENV=production bundle exec rails runner plugins/$PLUGIN_NAME/test/container_boot_check.rb" || exit 1

step "Result"
if [ "$TEST_STATUS" -eq 0 ]; then
  echo "PRE_PUSH_OK: tests passed and Redmine boots with the plugin"
else
  echo "PRE_PUSH_FAILED: plugin test suite exited with status $TEST_STATUS"
fi
exit "$TEST_STATUS"
