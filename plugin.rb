# name: discourse-riot
# about: Support to link your account to a League of Legends account
# version: 0.1
# authors: Ed Ceaser <ed@tehasdf.com>
# url: https://github.com/eaceaser/discourse-riot

gem "httparty", "0.13.7" # Dependency for ruby-lol
gem "ruby-lol", "0.11.4", :require_name => "lol"

enabled_site_setting :riot_enabled

ACCOUNTS_CUSTOM_FIELD ||= "discourse_riot_accounts".freeze
CACHE_NAMESPACE ||= "discourse_riot".freeze

DiscoursePluginRegistry.serialized_current_user_fields << ACCOUNTS_CUSTOM_FIELD

register_asset "javascripts/discourse/connectors/user-custom-preferences/riot.hbs"
register_asset "javascripts/discourse/connectors/user-card-post-names/riot-user-card-post-names.hbs"
register_asset "stylesheets/riot.scss"

after_initialize do
  module ::DiscourseRiot
    @cache = ::Cache.new(:namespace => CACHE_NAMESPACE)

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

      existing = RiotAccountLink.where(user.id)
      if existing &&
        existing.any? { |link| link.riot_id == summoner_id && link.riot_region == riot_region}
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

    def self.validate_rune_page_token(user)
      cached = $redis.get(token_key(user))
      if cached.nil?
        raise Discourse::NotFound
      end

      payload = JSON.parse(cached)
      region = payload["account_region"]
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
      RiotAccountLink.new(user, riot_id, riot_region).save
    end

    def self.lookup_riot_name_from_id(riot_id, region)
      client = client_for(region)
      client.summoner.name(riot_id)[riot_id.to_s]
    end

    def self.lookup_league_for_id(riot_id, region)
      begin
        client = client_for(region)
        leagues = client.league.get_entries(riot_id)[riot_id.to_s]
        solo = leagues.find { |l| l.queue == "RANKED_SOLO_5x5" }
        translate_league(solo.tier)
      rescue Lol::NotFound
        I18n.t("riot.league.unranked")
      end
    end

    def self.translate_league(league)
      I18n.t("riot.league.#{league.downcase}")
    end

    def self.get_payload_for_user(user)
        if user.custom_fields[ACCOUNTS_CUSTOM_FIELD]
          parsed = JSON.parse(user.custom_fields[ACCOUNTS_CUSTOM_FIELD])
          parsed.map do |f|
            id = f["riot_id"]
            region = f["riot_region"]

            remote_info = @cache.fetch("summoner:#{region}:#{id}") do
              league = lookup_league_for_id(id, region)
              name = lookup_riot_name_from_id(id, region)
              { riot_name: name,
                riot_league: league
              }
            end

            remote_info.merge({
              riot_id: f["riot_id"],
              riot_region: f["riot_region"]
            })
          end
        else
          []
        end
#      end
    end
  end

  # Controllers
  require_dependency 'application_controller'
  class ::DiscourseRiot::RiotController < ::ApplicationController
    requires_plugin 'discourse-riot'

    before_filter :ensure_logged_in

    def initiate_link
      begin
        account_name = params[:riot_name]
        region = params[:riot_region]
        if account_name.nil? || account_name.empty?
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
      begin
        rv = ::DiscourseRiot.validate_rune_page_token(current_user)
        render json: {confirmed: rv}
      rescue Discourse::NotFound => e
        render json: {errors: [I18n.t("riot.link_expired")]}, status: 404
      end
    end

    def delete_link
      begin
        riot_id = params[:riot_id].to_i
        if riot_id.nil?
          raise Discourse::InvalidParameters.new I18n.t("riot.account_id_empty")
        end

        riot_region = params[:riot_region]
        if riot_region.nil?
          raise Discourse::InvalidParameters.new I18n.t("riot.region_empty")
        end

        links = ::DiscourseRiot::RiotAccountLink.where(current_user.id)
        if links.nil? || links.empty?
          raise Discourse::NotFound
        end

        l = links.find { |l| l.riot_id == riot_id && l.riot_region == riot_region }
        if l.nil?
          raise Discourse::NotFound
        end
        l.delete
        render :nothing => true, status: 204
      rescue Discourse::NotFound => e
        render :nothing => true, status: 404
      rescue Discourse::InvalidParameters => e
        render json: {errors: [e.message]}, status: 400
      end
    end
  end

  ::DiscourseRiot::Engine.routes.draw do
    post '/link' => 'riot#initiate_link'
    delete '/link' => 'riot#delete_link'
    post '/link/confirm' => 'riot#confirm_link'
  end

  Discourse::Application.routes.append do
    mount ::DiscourseRiot::Engine, at: "/riot"
  end

  # Model

  class ::RiotAccountLinkSerializer < ActiveModel::Serializer
    attributes :riot_id, :riot_region
    define_method :riot_id, -> {object.riot_id}
    define_method :riot_region, -> {object.riot_region}
  end

  ::DiscourseRiot::RiotAccountLink = Struct.new(:user_id, :riot_id, :riot_region) do
    def self.where(user_id)
      if existing = UserCustomField.find_by_user_id_and_name(user_id, ACCOUNTS_CUSTOM_FIELD)
        x = JSON.parse(existing.value)
        x.map { |v| ::DiscourseRiot::RiotAccountLink.new(user_id, v["riot_id"], v["riot_region"]) }
      else
        nil
      end
    end

    def save
      UserCustomField.transaction do
        if existing = UserCustomField.find_by_user_id_and_name(user_id, ACCOUNTS_CUSTOM_FIELD)
          parsed = JSON.parse(existing.value)
          filtered = parsed.reject { |link| link.riot_id == riot_id && link.riot_region == riot_region }
          appended = filtered.push(self)

          existing.value = ActiveModel::ArraySerializer.new(appended, each_serializer: ::RiotAccountLinkSerializer).to_json
          existing.save
        else
          payload = [self]
          to_serialize = ActiveModel::ArraySerializer.new(payload, each_serializer: ::RiotAccountLinkSerializer)
          UserCustomField.create({ user_id: user_id, name: ACCOUNTS_CUSTOM_FIELD, value: to_serialize.to_json })
        end
      end
      self
    end

    def delete
      UserCustomField.transaction do
        existing = UserCustomField.find_by_user_id_and_name(user_id, ACCOUNTS_CUSTOM_FIELD)
        if existing
          x = JSON.parse(existing.value)
          rejected = x.map { |v| ::DiscourseRiot::RiotAccountLink.new(user_id, v["riot_id"], v["riot_region"]) }
           .reject { |v| riot_id == v.riot_id && riot_region == v.riot_region }
          existing.value = rejected.to_json
          existing.save
        end
      end
    end
  end

  # User Serialization

  User.class_eval do
    def riot_accounts
      ::DiscourseRiot::get_payload_for_user(self)
    end

    def save_custom_fields(force=false)
      if @custom_fields
        @custom_fields.reject! { |k,v| k == ACCOUNTS_CUSTOM_FIELD }
        @custom_fields_orig.reject! { |k,v| k == ACCOUNTS_CUSTOM_FIELD }
        _custom_fields.reject { |k| k == ACCOUNTS_CUSTOM_FIELD }
      end
      super(force)
    end
  end

  UserSerializer.class_eval do
    attributes :riot_accounts

    def riot_accounts
      ActiveModel::ArraySerializer.new(object.riot_accounts)
    end
  end
end
