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
# Purpose: Post-migration check executed by rails runner inside the containerised test run.
#          Asserts that every hrz_cmdb table exists, that the plugin is registered and that
#          the application eager loads, i.e. that Redmine can actually start with the plugin.

# Tables that the plugin migrations must have created.
PLUGIN_TABLES = %w[
  hrzcm_locat_hier
  hrzcm_location
  hrzcm_ci_class
  hrzcm_lifecycle_status
  hrzcm_ci
  hrzcm_ci_issues
  hrzcm_ext_sys
  hrzcm_ci_ext
  hrzcm_ci_history
].freeze

missing = PLUGIN_TABLES.reject { |table| ActiveRecord::Base.connection.table_exists?(table) }
abort("SCHEMA_FAILED missing_tables=#{missing.join(',')}") if missing.any?

Rails.application.eager_load!

plugin = Redmine::Plugin.registered_plugins[:hrz_cmdb]
abort('BOOT_FAILED plugin hrz_cmdb is not registered') if plugin.nil?

puts "SCHEMA_OK env=#{Rails.env} tables=#{PLUGIN_TABLES.size}"
puts "BOOT_OK plugin=hrz_cmdb version=#{plugin.version}"
