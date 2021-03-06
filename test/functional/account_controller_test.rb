require File.dirname(__FILE__) + '/../test_helper'
require 'account_controller'

# Re-raise errors caught by the controller.
class AccountController; def rescue_action(e) raise e end; end

class AccountControllerTest < Test::Unit::TestCase
  # Be sure to include AuthenticatedTestHelper in test/test_helper.rb instead
  # Then, you can remove it from this and the units test.
  include AuthenticatedTestHelper
  
  # Note-- account creation is handled in it's own file account_creation_test

  common_fixtures

  def setup
    get_renderer
    @controller = AccountController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
  end

  def test_create_successful   
    login_as :joe_user
    assert_difference ActionMailer::Base.deliveries, :size do 
      assert_new_account do 
        post_invite
      end
    end
  end  
  

  def test_should_login_and_redirect
    logout
    post :signin, :login => 'u3@user.com', :password => 'u3_pass'
    assert session[:user]
    assert_response :redirect
  end

  def test_should_fail_login_and_not_redirect
    logout
    post :signin, :login => 'webmaster@grasscommons.org', :password => 'bad password'
    assert_nil session[:user]
    assert_response 403
  end
  
  def test_should_logout
    get :logout
    assert_nil session[:user]
    assert_response :redirect
  end

  def test_forgot_password_not_found
  end                        
   
  def test_forgot_password
  end 



end
