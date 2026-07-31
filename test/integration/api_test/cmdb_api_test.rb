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
# Purpose: Integration tests for the CMDB REST API covering authentication, authorisation,
#          pagination, response shapes and status codes of the CmdbController endpoints.

require File.expand_path('../../../test_helper', __FILE__)

class Redmine::ApiTest::CmdbApiTest < Redmine::ApiTest::Base
  fixtures :users, :email_addresses, :roles,
           :hrzcm_locat_hier, :hrzcm_location, :hrzcm_ci_class,
           :hrzcm_lifecycle_status, :hrzcm_ci

  # Enables the REST API and grants the admin account, which bypasses the group based
  # CMDB permissions, so that the tests can focus on the API behaviour itself.
  def setup
    super
    @admin = credentials('admin')
  end

  # Resets the plugin settings that the permission helpers of the test suite modify.
  def teardown
    Setting.plugin_hrz_cmdb = {}
    super
  end

  # ---------------------------------------------------------------------------------------
  # Authentication and authorisation
  # ---------------------------------------------------------------------------------------

  test "should reject anonymous api request" do
    get '/cmdb/locations.json'
    assert_response :unauthorized
  end

  test "should reject api request of user without cmdb permission" do
    user_without_cmdb_permission
    get '/cmdb/locations.json', :headers => credentials('dlopper')
    assert_response :forbidden
  end

  test "should accept api request of user with view permission" do
    user = user_with_cmdb_permission('view_cmdb')
    get '/cmdb/locations.json', :headers => credentials(user.login)
    assert_response :success
  end

  test "should reject create of user with view permission only" do
    user = user_with_cmdb_permission('view_cmdb')
    post '/cmdb/location.json',
         :params => { :location => { :b_name_abbr => 'NEW', :j_type_id => 3 } },
         :headers => credentials(user.login)
    assert_response :forbidden
  end

  # ---------------------------------------------------------------------------------------
  # Locations
  # ---------------------------------------------------------------------------------------

  test "should index locations with pagination meta" do
    get '/cmdb/locations.json', :headers => @admin
    assert_response :success
    assert_equal 'application/json', response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['hrzcm_locations']
    assert_equal HrzcmLocation.count, json['total_count']
    assert_equal 0, json['offset']
    assert_equal 25, json['limit']
  end

  test "should honour limit and offset when indexing locations" do
    get '/cmdb/locations.json?limit=1&offset=1', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['limit']
    assert_equal 1, json['offset']
    assert_equal 1, json['hrzcm_locations'].size
  end

  test "should filter locations by hierarchy type" do
    get '/cmdb/locations.json?j_type_id=3', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert json['hrzcm_locations'].any?
    assert json['hrzcm_locations'].all? { |l| l['locat_hier']['id'] == 3 }
  end

  test "should show location" do
    get '/cmdb/location/3.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 3, json['hrzcm_location']['id']
    assert_equal 'Room 101', json['hrzcm_location']['b_name_full']
    assert_equal 2, json['hrzcm_location']['part_of1']['id']
  end

  test "should return 404 for unknown location" do
    get '/cmdb/location/999999.json', :headers => @admin
    assert_response :not_found
  end

  test "should create location" do
    assert_difference 'HrzcmLocation.count' do
      post '/cmdb/location.json',
           :params => { :location => { :b_name_full => 'Room 103', :b_name_abbr => '103',
                                       :b_key => 'r103', :j_type_id => 3, :j_part_of1_id => 2 } },
           :headers => @admin
    end
    assert_response :created

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'Room 103', json['hrzcm_location']['b_name_full']
    assert_not_nil response.headers['Location']
  end

  test "should not create location without hierarchy type" do
    assert_no_difference 'HrzcmLocation.count' do
      post '/cmdb/location.json',
           :params => { :location => { :b_name_abbr => 'BAD' } },
           :headers => @admin
    end
    assert_response :unprocessable_entity

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['errors']
  end

  test "should update location" do
    put '/cmdb/location/4.json',
        :params => { :location => { :b_name_full => 'Renamed Room' } },
        :headers => @admin
    assert_response :no_content
    assert_equal 'Renamed Room', HrzcmLocation.find(4).b_name_full
  end

  test "should destroy location" do
    assert_difference 'HrzcmLocation.count', -1 do
      delete '/cmdb/location/4.json', :headers => @admin
    end
    assert_response :no_content
  end

  # ---------------------------------------------------------------------------------------
  # Configuration items
  # ---------------------------------------------------------------------------------------

  test "should index cis" do
    get '/cmdb/cis.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['hrzcm_cis']
    assert_equal HrzcmCi.count, json['total_count']
  end

  test "should filter cis by serial number" do
    get '/cmdb/cis.json?b_tag_serial=SN67890', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['hrzcm_cis'].size
    assert_equal 'DB01', json['hrzcm_cis'].first['b_name_abbr']
  end

  test "should filter cis by assigned user" do
    HrzcmCi.find(3).update!(j_assigned_user_id: 2)

    get '/cmdb/cis.json?j_assigned_user_id=2', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['hrzcm_cis'].size
    assert_equal 3, json['hrzcm_cis'].first['id']
    assert_equal 2, json['hrzcm_cis'].first['assigned_user']['id']
  end

  test "should show ci with linked issues" do
    get '/cmdb/ci/2.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['hrzcm_ci']['id']
    assert_equal 2, json['hrzcm_ci']['ci_class']['id']
    assert_kind_of Array, json['hrzcm_ci']['issues']
  end

  test "should create ci" do
    assert_difference 'HrzcmCi.count' do
      post '/cmdb/cis.json',
           :params => { :ci => { :b_name_full => 'New Server', :b_name_abbr => 'NEW01',
                                 :j_ci_class_id => 2, :j_location_id => 3, :j_status_id => 2 } },
           :headers => @admin
    end
    assert_response :created

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'NEW01', json['hrzcm_ci']['b_name_abbr']
  end

  test "should not create ci without ci class" do
    assert_no_difference 'HrzcmCi.count' do
      post '/cmdb/cis.json',
           :params => { :ci => { :b_name_abbr => 'BAD01' } },
           :headers => @admin
    end
    assert_response :unprocessable_entity
  end

  test "should update ci" do
    put '/cmdb/cis/3.json',
        :params => { :ci => { :b_producer => 'Dell' } },
        :headers => @admin
    assert_response :no_content
    assert_equal 'Dell', HrzcmCi.find(3).b_producer
  end

  test "should assign ci to a user" do
    put '/cmdb/cis/3.json',
        :params => { :ci => { :j_assigned_user_id => 2 } },
        :headers => @admin
    assert_response :no_content
    assert_equal 2, HrzcmCi.find(3).j_assigned_user_id

    get '/cmdb/ci/3.json', :headers => @admin
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['hrzcm_ci']['assigned_user']['id']
  end

  test "should destroy ci" do
    assert_difference 'HrzcmCi.count', -1 do
      delete '/cmdb/cis/3.json', :headers => @admin
    end
    assert_response :no_content
  end

  # ---------------------------------------------------------------------------------------
  # CI classes, lifecycle statuses and external systems
  # ---------------------------------------------------------------------------------------

  test "should index ci classes" do
    get '/cmdb/ci_classes.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal HrzcmCiClass.count, json['total_count']
  end

  test "should show ci class" do
    get '/cmdb/ci_class/2.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['hrzcm_ci_class']['id']
  end

  test "should index lifecycle statuses" do
    get '/cmdb/lifecycle_statuses.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal HrzcmLifecycleStatus.count, json['total_count']
  end

  test "should index external systems" do
    get '/cmdb/external_systems.json', :headers => @admin
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['hrzcm_ext_systems']
  end

  # ---------------------------------------------------------------------------------------
  # XML format
  # ---------------------------------------------------------------------------------------

  test "should render locations as xml" do
    get '/cmdb/locations.xml', :headers => @admin
    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'hrzcm_locations hrzcm_location id'
  end
end
