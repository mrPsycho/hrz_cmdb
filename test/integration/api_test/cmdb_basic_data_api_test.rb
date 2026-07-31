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
# Purpose: Integration tests for the REST API of the location hierarchy (basic data) endpoints.

require File.expand_path('../../../test_helper', __FILE__)

class Redmine::ApiTest::CmdbBasicDataApiTest < Redmine::ApiTest::Base
  fixtures :users, :email_addresses, :roles, :hrzcm_locat_hier, :hrzcm_location

  # Enables the REST API and uses the admin account, which bypasses the group based
  # edit_basic_data permission.
  def setup
    super
    @admin = credentials('admin')
  end

  # Resets the plugin settings that the permission helpers of the test suite modify.
  def teardown
    Setting.plugin_hrz_cmdb = {}
    super
  end

  test "should reject anonymous request for location hierarchies" do
    get '/cmdb_basic_data.json'
    assert_response :unauthorized
  end

  test "should reject request of user without edit_basic_data permission" do
    user_without_cmdb_permission
    get '/cmdb_basic_data.json', :headers => credentials('dlopper')
    assert_response :forbidden
  end

  test "should index location hierarchies with pagination meta" do
    get '/cmdb_basic_data.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['hrzcm_locat_hiers']
    assert_equal HrzcmLocatHier.count, json['total_count']
    assert_equal 0, json['offset']
    assert_equal 25, json['limit']
  end

  test "should show location hierarchy" do
    get '/cmdb_basic_data/location_hierarchies/1.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['hrzcm_locat_hier']['id']
    assert_not_nil json['hrzcm_locat_hier']['j_level']
  end

  test "should create location hierarchy" do
    assert_difference 'HrzcmLocatHier.count' do
      post '/cmdb_basic_data/location_hierarchies.json',
           :params => { :hierarchy => { :b_name_full => 'Rack', :b_name_abbr => 'RCK',
                                        :b_key => 'rack', :j_level => 99 } },
           :headers => @admin
    end
    assert_response :created

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'Rack', json['hrzcm_locat_hier']['b_name_full']
    assert_not_nil response.headers['Location']
  end

  test "should not create location hierarchy without level" do
    assert_no_difference 'HrzcmLocatHier.count' do
      post '/cmdb_basic_data/location_hierarchies.json',
           :params => { :hierarchy => { :b_name_abbr => 'BAD' } },
           :headers => @admin
    end
    assert_response :unprocessable_entity

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['errors']
  end

  test "should update location hierarchy" do
    put '/cmdb_basic_data/location_hierarchies/1.json',
        :params => { :hierarchy => { :b_name_full => 'Renamed Level' } },
        :headers => @admin
    assert_response :no_content
    assert_equal 'Renamed Level', HrzcmLocatHier.find(1).b_name_full
  end

  test "should not destroy location hierarchy that is still in use" do
    assert_no_difference 'HrzcmLocatHier.count' do
      delete '/cmdb_basic_data/location_hierarchies/1.json', :headers => @admin
    end
    assert_response :unprocessable_entity
  end
end
