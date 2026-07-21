Rails.application.routes.draw do
  root "messages#index"
  resource :onboarding, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resources :messages, only: :create do
    resources :reactions, only: :create
  end
  resources :agent_invitations, only: %i[new create show]
  namespace :api do
    resources :messages, only: %i[index create]
    post "agent_invitations/:token/redeem", to: "agent_invitations#create", as: :redeem_agent_invitation
  end
  get "up" => "rails/health#show", as: :rails_health_check
end
