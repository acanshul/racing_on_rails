require 'test_helper'

class Admin::PagesControllerTest < ActionController::TestCase
  def setup
    super
    @request.session[:user_id] = users(:administrator).id
  end

  test "Only admins can edit pages" do
    session[:user_id] = nil
    get(:index)
    assert_redirected_to(:action => "login")
  end
  
  test "View pages as tree" do
    get(:index)
    assert_response(:success)
  end
  
  test "Update title inplace" do
    page = pages(:plain)
    post(:set_page_title, 
        :id => page.to_param,
        :value => "OBRA Banquet",
        :editorId => "page_#{page.id}_name"
    )
    assert_response(:success)
    assert_template(nil)
    assert_equal(page, assigns("item"), "@page")
    page.reload
    assert_equal("OBRA Banquet", page.title, "Page title")
    assert_equal(users(:administrator), page.author, "author")
  end
  
  test "Edit page" do
    page = pages(:plain)
    get(:edit, :id => page.id)
  end
  
  test "Update page" do
    page = pages(:plain)
    put(:update, 
        :id => page.to_param,
        :page => {
          :title => "My Awesome Bike Racing Page",
          :body => "<blink>Race</blink>",
          :parent_id => nil
        }
    )
    assert_redirected_to(edit_admin_page_path(page))
    page.reload
    assert_equal("My Awesome Bike Racing Page", page.title, "title")
    assert_equal("<blink>Race</blink>", page.body, "body")
    assert_equal(users(:administrator), page.author, "author")
  end
  
  test "Update page parent" do
    parent_page = Page.create!(:title => "Root")
    page = pages(:plain)
    put(:update,
        :id => page.to_param,
        :page => {
          :title => "My Awesome Bike Racing Page",
          :body => "<blink>Race</blink>",
          :parent_id => parent_page.to_param
        }
    )
    page.reload
    assert_equal("My Awesome Bike Racing Page", page.title, "title")
    assert_equal("<blink>Race</blink>", page.body, "body")
    assert_equal(users(:administrator), page.author, "author")
    assert_equal(parent_page, page.parent, "Page parent")
    assert_redirected_to(edit_admin_page_path(page))
  end
  
  test "New page" do
    get(:new)
  end
  
  test "New page parent" do
    parent_page = pages(:plain)
    get(:new, :page => { :parent_id => parent_page.to_param })
    page = assigns(:page)
    assert_not_nil(page, "@page")
    assert_equal(parent_page, page.parent, "New page parent")
  end
  
  test "Create page" do
    put(:create, 
        :page => {
          :title => "My Awesome Bike Racing Page",
          :body => "<blink>Race</blink>"          
        }
    )
    page = Page.find_by_title("My Awesome Bike Racing Page")
    assert_redirected_to(edit_admin_page_path(page))
    page.reload
    assert_equal("My Awesome Bike Racing Page", page.title, "title")
    assert_equal("<blink>Race</blink>", page.body, "body")
    assert_equal(users(:administrator), page.author, "author")
  end
  
  test "Create child page" do
    parent_page = pages(:plain)
    post(:create, 
        :page => {
          :title => "My Awesome Bike Racing Page",
          :body => "<blink>Race</blink>",
          :parent_id => parent_page.to_param
        }
    )
    page = Page.find_by_title("My Awesome Bike Racing Page")
    assert_redirected_to(edit_admin_page_path(page))
    page.reload
    assert_equal("My Awesome Bike Racing Page", page.title, "title")
    assert_equal("<blink>Race</blink>", page.body, "body")
    assert_equal(users(:administrator), page.author, "author")
    assert_equal(parent_page, page.parent, "Page parent")
  end
  
  test "Delete page" do
    page = pages(:plain)
    delete(:destroy, :id => page.to_param)
    assert_redirected_to(admin_pages_path)
    assert(!Page.exists?(page.id), "Page should be deleted")
  end
end