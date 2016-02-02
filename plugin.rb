# name: discourse-riot
# about: Support to link your account to a League of Legends account
# version: 0.1
# authors: Ed Ceaser <ed@tehasdf.com>
# url: https://github.com/eaceaser/discourse-riot

gem "httparty", "0.13.7" # Dependency for ruby-lol
gem "ruby-lol", "0.11.4", :require_name => "lol"

enabled_site_setting :riot_enabled

ACCOUNTS_CUSTOM_FIELD ||= "discourse_riot_accounts".freeze

DiscoursePluginRegistry.serialized_current_user_fields << ACCOUNTS_CUSTOM_FIELD

register_asset "javascripts/discourse/connectors/user-custom-preferences/riot.hbs"

after_initialize do
  module ::DiscourseRiot
    require_dependency 'rest_client'

    class Engine < ::Rails::Engine
      engine_name "discourse_riot"
      isolate_namespace DiscourseRiot
    end

    def self.riot_api_key
      SiteSetting.riot_api_key
    end

    def self.client_for(region)
      Lol::Client.new riot_api_key, { region: region }
    end


    TOKEN_REDIS_KEY_PREFIX ||= "riot_link_token:1".freeze
    TOKEN_FIELD_NAME ||= "discourse_riot_token".freeze
    TOKEN_TTL ||= 300

    # TODO: lookup account name here and store id.
    # TODO: use an alnum string for the token.
    # TODO: redis expiration
    def self.create_new_token(user, riot_account_name, riot_region)
      client = client_for riot_region
      summoner_id = begin
        summoners = client.summoner.by_name(riot_account_name)
        summoners.first.id
      rescue Lol::NotFound
        raise Discourse::InvalidParameters.new(I18n.t("riot.account_not_found"))
      end

      if user.custom_fields[ACCOUNTS_CUSTOM_FIELD] &&
        user.custom_fields[ACCOUNTS_CUSTOM_FIELD].any? { |link| link['id'] == summoner_id && link['region'] == riot_region}
        raise Discourse::InvalidParameters.new(I18n.t("riot.account_already_linked"))
      end

      new_token = rand(100000...1000000)
      link_payload = {
        :account_name => riot_account_name,
        :account_id => summoner_id,
        :account_region => riot_region,
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
      region = client_for(payload["account_region"])
      client = client_for(region)
      summoner = client.summoner.by_name(payload["account_name"]).first
      summoner_id = summoner.id
      runes = client.summoner.runes(summoner_id)[summoner_id.to_s]
      valid = runes.any? { |page| page.name.to_s == payload["token"].to_s }

      if valid
        save_riot_account(user, summoner_id, region)
      end

      valid
    end

    def self.save_riot_account(user, riot_id, riot_region)
      accounts = user.custom_fields[ACCOUNTS_CUSTOM_FIELD] || []
      payload = {
        :id => riot_id,
        :region => riot_region
      }
      accounts.push payload
      user.custom_fields[ACCOUNTS_CUSTOM_FIELD] = accounts.to_json
      user.save_custom_fields(true)
    end

    def self.lookup_riot_name_from_id(riot_id, region)
      client = client_for(region)
      client.summoner.name(riot_id)[riot_id.to_s]
    end

    require_dependency 'application_controller'

    class DiscourseRiot::RiotController < ::ApplicationController
      requires_plugin 'discourse-riot'

      before_filter :ensure_logged_in

      def initiate_link
        begin
          account_name = params[:riot_name]
          region = params[:riot_region]
          if account_name.nil?
            raise Discourse::InvalidParameters.new I18n.t("riot.account_name_empty")
          end

          if region.nil?
            raise Discourse::InvalidParameters.new I18n.t("riot.region_empty")
          end

          new_token = ::DiscourseRiot.create_new_token(current_user, account_name, region)
          render json: {token: new_token}
        rescue Discourse::InvalidParameters => e
          render json: {errors: [e.message]}, status: 400
        end

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

  User.register_custom_field_type(ACCOUNTS_CUSTOM_FIELD, :json)

  # TODO: Probably should not put an API call here in the serializer.
  add_to_serializer(:user, :riot_accounts, false) do
    custom_fields[ACCOUNTS_CUSTOM_FIELD].each do |riot_account|
      riot_id = riot_account["id"]
      account_name = ::DiscourseRiot.lookup_riot_name_from_id(riot_id, "na")
      riot_account["name"] = account_name
      riot_account
    end
  end
end
