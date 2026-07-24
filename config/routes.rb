Rails.application.routes.draw do
  root "projects#index"
  resource :inbox, only: :show do
    patch :mark_all_read
  end
  resource :onboarding, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resources :projects, only: [ :index, :show, :create ] do
    patch :reorder, on: :member
    resource :chat, only: :show do
      resources :messages, controller: "chat_messages", only: :create do
        resources :reactions, only: :create
      end
      resources :subscriptions, controller: "chat_subscriptions", only: :update
    end
    resources :briefings, except: :destroy do
      post :run_now, on: :member
      patch :toggle, on: :member
      resources :comments, controller: "briefing_comments", only: %i[create edit update destroy] do
        resources :reactions, only: :create
      end
    end
    resources :file_entries, path: "files", only: %i[index create destroy] do
      get :download, on: :member
    end
    resources :task_lists, path: "task-lists", only: :create do
      patch :reorder, on: :member
    end
    resources :tasks, except: :destroy do
      patch :reorder, on: :member
      resources :assignments, controller: "task_assignments", only: %i[create destroy]
      resources :reactions, only: :create
      resources :comments, controller: "task_comments", only: %i[create edit update destroy] do
        resources :reactions, only: :create
      end
    end
  end
  resources :agent_invitations, only: %i[new create show]
  resources :agents, only: :index
  resources :agent_approvals, only: :update
  get "database", to: "database#index", as: :database
  get "database/:table", to: "database#show", as: :database_table
  get "database/:table/records/:id", to: "database#record", as: :database_record
  namespace :api do
    resources :projects, only: %i[index show] do
      get :search, on: :member
      resources :tasks, only: %i[index show create update] do
        resources :comments, controller: "task_comments", only: %i[index create]
      end
    end
    get "projects/:project_id/chat/messages", to: "chat_messages#index", as: :project_chat_messages
    post "projects/:project_id/chat/messages", to: "chat_messages#create"
    get "projects/:project_id/chat/messages/:message_id/attachments/:id",
      to: "chat_messages#attachment",
      as: :project_chat_message_attachment
    post "restart", to: "restarts#create", as: :restart if Rails.env.local?
    post "agent/status", to: "agent_presences#update", as: :agent_status
    post "agent_events/:id/acknowledge", to: "agent_events#acknowledge", as: :acknowledge_agent_event
    post "agent_invitations/:token/redeem", to: "agent_invitations#create", as: :redeem_agent_invitation
  end
  get "up" => "rails/health#show", as: :rails_health_check
end
