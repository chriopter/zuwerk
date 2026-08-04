ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

User.after_create(if: -> { !skip_automatic_test_membership && memberships.empty? }) do
  memberships.create!(account: Account.test_default, role: human? ? :owner : :member)
end

Project.before_validation(on: :create, if: -> { account.nil? }) do
  self.account = Account.test_default
end

module AccountRouteTestHelpers
  ACCOUNT_ROUTES = %i[
    inbox_path mark_all_read_inbox_path projects_path project_path reorder_project_path
    project_agent_turn_path project_chat_path project_chat_messages_path project_chat_message_reactions_path
    project_chat_subscription_path project_briefings_path project_briefing_path new_project_briefing_path
    edit_project_briefing_path run_now_project_briefing_path toggle_project_briefing_path
    project_briefing_comments_path project_briefing_comment_path edit_project_briefing_comment_path
    project_briefing_comment_reactions_path project_file_entries_path project_file_entry_path
    download_project_file_entry_path project_task_lists_path reorder_project_task_list_path
    project_tasks_path project_task_path new_project_task_path edit_project_task_path reorder_project_task_path
    project_task_assignments_path project_task_assignment_path project_task_reactions_path
    project_task_comments_path project_task_comment_path edit_project_task_comment_path
    project_task_comment_reactions_path agents_path agent_invitations_path new_agent_invitation_path
    agent_invitation_path agent_approval_path
  ].freeze

  ACCOUNT_ROUTES.each do |route_name|
    define_method(route_name) do |*args, **options|
      account = args.first.respond_to?(:account) ? args.first.account : Account.test_default
      options[:account_number] ||= account.account_number
      super(*args, **options)
    end
  end
end

ActiveSupport::TestCase.prepend(AccountRouteTestHelpers)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
