Rails.application.routes.draw do
  root "projects#index"
  resource :onboarding, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resources :messages, only: :create
  resources :projects, only: [ :index, :show, :create ] do
    get :chat, on: :member, to: "messages#index"
    get :agents, on: :member, to: "project_agents#index"
    resources :agent_terminal_panes, path: "agents/panes", only: %i[create destroy]
    resources :messages, only: :create do
      resources :reactions, only: :create
    end
    resource :room_setting, only: :update
    resources :agent_subscriptions, only: :update
    resources :board_posts, path: "board", only: %i[index show]
    resources :board_automations, path: "board/automations", only: %i[new create show edit update] do
      post :run_now, on: :member
      patch :toggle, on: :member
    end
    resources :file_entries, path: "files", only: %i[index create destroy] do
      get :download, on: :member
    end
    resources :todos, except: :destroy do
      patch :reorder, on: :member
      resources :assignments, controller: "todo_assignments", only: %i[create destroy]
      resources :comments, controller: "todo_comments", only: %i[create edit update destroy] do
        resources :reactions, only: :create
      end
    end
  end
  resources :agent_invitations, only: %i[new create show]
  resources :agents, only: %i[index new create show update] do
    post :start, on: :member
    post :stop, on: :member
    post :restart, on: :member
  end
  resources :agent_approvals, only: :update
  get "database", to: "database#index", as: :database
  get "database/:table", to: "database#show", as: :database_table
  get "database/:table/records/:id", to: "database#record", as: :database_record
  resource :room_setting, only: :update
  namespace :api do
    resources :projects, only: %i[index show] do
      get :search, on: :member
      resources :messages, only: %i[index create]
      get "messages/:message_id/attachments/:id", to: "messages#attachment", as: :message_attachment
      resources :todos, only: %i[index show create update] do
        resources :comments, controller: "todo_comments", only: %i[index create]
      end
    end
    post "restart", to: "restarts#create", as: :restart if Rails.env.local?
    post "agent/status", to: "agent_presences#update", as: :agent_status
    post "agent_invitations/:token/redeem", to: "agent_invitations#create", as: :redeem_agent_invitation
  end
  get "up" => "rails/health#show", as: :rails_health_check
end
