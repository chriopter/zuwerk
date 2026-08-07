require "application_system_test_case"

class LibraryPagesTest < ApplicationSystemTestCase
  setup do
    @human = User.create!(name: "Library Editor", email: "library-editor@example.com", password: "password1")
    @project = Project.create!(name: "Product studio")
    @root = @project.library_root

    visit new_session_path
    fill_in "Email", with: @human.email
    fill_in "Password", with: "password1"
    click_button "Sign in"
    assert_current_path projects_path
  end

  test "creates and edits a nested library page" do
    page.current_window.resize_to(1400, 1000)
    visit project_library_page_path(@project, @root)

    assert_selector ".topbar-project-tools .is-active", text: "Library"
    assert_selector ".library-tree-home", text: "Home"
    find("#new-page > summary").click
    geometry = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const panel = document.querySelector(".library-tree-panel").getBoundingClientRect()
        const form = document.querySelector("#new-page form").getBoundingClientRect()
        const documentPanel = document.querySelector(".library-document").getBoundingClientRect()
        return { panelLeft: panel.left, panelRight: panel.right, formLeft: form.left, formRight: form.right, documentLeft: documentPanel.left }
      })()
    JAVASCRIPT
    assert_operator geometry["formLeft"], :>=, geometry["panelLeft"]
    assert_operator geometry["formRight"], :<=, geometry["panelRight"]
    assert_operator geometry["formRight"], :<=, geometry["documentLeft"]
    within "#new-page" do
      find("input[name='library_page[title]']", visible: :all).set("Research")
      find("select[name='library_page[parent_id]']", visible: :all).select("Home")
      click_button "Create"
    end

    assert_selector ".library-title[value='Research']"
    editor = find("lexxy-editor [contenteditable='true']", wait: 5)
    assert_selector "lexxy-toolbar button[name='bold']", visible: false
    find(".library-format-toggle").click
    assert_selector "lexxy-toolbar button[name='bold']", visible: true
    assert_selector ".library-format-toggle[aria-expanded='true']"
    editor.click
    editor.send_keys("Customer findings")

    assert_selector "[data-autosave-target='status']", text: "Saved", wait: 5
    assert_equal "Customer findings", LibraryPage.find_by!(title: "Research").content.to_plain_text
    assert_selector ".library-tree-row.is-active", text: "Research"
    save_screenshot("/tmp/zuwerk-library.png") if ENV["LIBRARY_SCREENSHOT"]
  end

  test "keeps mobile navigation and expanded controls inside the viewport" do
    page.current_window.resize_to(390, 844)
    visit project_library_page_path(@project, @root)

    topbar = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const first = document.querySelector(".topbar-zone-start").getBoundingClientRect()
        const tools = document.querySelector(".topbar-zone-center").getBoundingClientRect()
        return { firstBottom: first.bottom, toolsTop: tools.top }
      })()
    JAVASCRIPT
    assert_operator topbar["toolsTop"], :>=, topbar["firstBottom"]

    find(".project-switcher > summary").click
    menu = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const rect = document.querySelector(".project-switcher-menu").getBoundingClientRect()
        return { left: rect.left, right: rect.right, viewport: window.innerWidth }
      })()
    JAVASCRIPT
    assert_operator menu["left"], :>=, 0
    assert_operator menu["right"], :<=, menu["viewport"]
    find(".project-switcher > summary").click

    find("#new-page > summary").click
    create_form = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const panel = document.querySelector(".library-tree-panel").getBoundingClientRect()
        const form = document.querySelector("#new-page form").getBoundingClientRect()
        const documentPanel = document.querySelector(".library-document").getBoundingClientRect()
        return { panelLeft: panel.left, panelRight: panel.right, formLeft: form.left, formRight: form.right, formBottom: form.bottom, documentTop: documentPanel.top }
      })()
    JAVASCRIPT
    assert_operator create_form["formLeft"], :>=, create_form["panelLeft"]
    assert_operator create_form["formRight"], :<=, create_form["panelRight"]
    assert_operator create_form["formBottom"], :<=, create_form["documentTop"]
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
