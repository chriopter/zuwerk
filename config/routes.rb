Rails.application.routes.draw do
  root "messages#index"
  resource :onboarding, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resources :messages, only: :create do
    resources :reactions, only: :create
  end
  resources :projects, only: :create do
    get :chat, on: :member, to: "messages#index"
    resources :messages, only: :create
    resource :room_setting, only: :update
  end
  resources :agent_invitations, only: %i[new create show]
  resources :agents, only: %i[index new create show] do
    post :start, on: :member
    post :stop, on: :member
    post :restart, on: :member
  end
  resource :room_setting, only: :update
  namespace :api do
    resources :messages, only: %i[index create]
    post "agent/status", to: "agent_presences#update", as: :agent_status
    post "messages/streams", to: "message_streams#create", as: :message_streams
    patch "messages/:id/stream", to: "message_streams#update", as: :message_stream
    post "agent_invitations/:token/redeem", to: "agent_invitations#create", as: :redeem_agent_invitation
  end
  get "up" => "rails/health#show", as: :rails_health_check
end
