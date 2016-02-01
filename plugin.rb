# name: discourse-riot
# about: Support to link your account to a League of Legends account
# version: 0.1
# authors: Ed Ceaser <ed@tehasdf.com>

gem "httparty", "0.13.7" # Dependency for ruby-lol
gem "ruby-lol", "0.11.4", :require_name => "lol"

enabled_site_setting :riot_enabled

register_asset "javascripts/discourse/connectors/user-custom-preferences/riot.hbs"

after_initialize do
  module ::DiscourseRiot
    require_dependency 'rest_client'

    class Engine < ::Rails::Engine
      engine_name "discourse_riot"
      isolate_namespace DiscourseRiot
    end


    TOKEN_REDIS_KEY_PREFIX ||= "riot_link_token:1".freeze
    TOKEN_FIELD_NAME ||= "discourse_riot_token".freeze
    TOKEN_TTL ||= 300
    ACCOUNT_NAME_FIELD_NAME ||= "discourse_riot_account_name".freeze

    # TODO: Probably shouldn't be global.
    # TODO: Support multiple regions.
    LOL_CLIENT ||= Lol::Client.new SiteSetting.riot_api_key, {region: "na"}

    # TODO: lookup account name here and store id.
    # TODO: use an alnum string for the token.
    # TODO: redis expiration
    def self.create_new_token(user, riot_account_name)
      return nil unless user
      return nil unless riot_account_name

      new_token = rand(100000...1000000)
      link_payload = {
        :account_name => riot_account_name,
        :account_region => "na",
        :token => new_token
      }

      $redis.setex(token_key(user), TOKEN_TTL, link_payload.to_json)
      new_token
    end

    def self.token_key(user)
      "#{TOKEN_REDIS_KEY_PREFIX}:#{user.id}"
    end

    # TODO: Handle expired
    def self.validate_rune_page_token(user)
      payload = JSON.parse($redis.get(token_key(user)))
      summoner = LOL_CLIENT.summoner.by_name(payload["account_name"])
      runes = LOL_CLIENT.summoner.runes(summoner.first.id)[summoner.first.id.to_s]
      runes.any? { |page| page.name.to_s == payload["token"].to_s }
    end

    require_dependency 'application_controller'

    class DiscourseRiot::RiotController < ::ApplicationController
      requires_plugin 'discourse-riot'

      before_filter :ensure_logged_in

      def initiate_link
        account_name = params[:riot_name]
        new_token = ::DiscourseRiot.create_new_token(current_user, account_name)
        render json: {token: new_token}
      end

      def confirm_link
        rv = ::DiscourseRiot.validate_rune_page_token(current_user)
        render json: {confirmed: rv}
      end
    end

    DiscourseRiot::Engine.routes.draw do
      post '/link' => 'riot#initiate_link'
      post '/link/confirm' => 'riot#confirm_link'
    end

    Discourse::Application.routes.append do
      mount ::DiscourseRiot::Engine, at: "/riot"
    end
  end
end

