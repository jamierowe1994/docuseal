# frozen_string_literal: true

module Integrations
  # Browser-facing OAuth 2.0 Authorization Endpoint for backed.crm.
  #
  # backed.crm redirects the user's browser here with:
  #   client_id     – The OauthApplication UID registered for backed.crm
  #   redirect_uri  – The CRM callback URL (must match the registered URI)
  #   state         – Opaque value the CRM uses to prevent CSRF
  #
  # Flow:
  #   1. Devise's authenticate_user! ensures the user is logged in.
  #      If not, they are sent to the sign-in page and redirected back here
  #      after a successful login.
  #   2. A one-time authorization code (OauthAccessGrant) valid for 10 minutes
  #      is created and the user is redirected to redirect_uri?code=…&state=…
  class CrmAuthorizeController < ApplicationController
    skip_authorization_check

    def show
      client_id    = params[:client_id].to_s.strip
      redirect_uri = params[:redirect_uri].to_s.strip
      state        = params[:state].to_s.strip

      application = OauthApplication.find_by(uid: client_id)

      return render plain: 'Invalid client_id.', status: :bad_request unless application
      return render plain: 'Invalid redirect_uri.', status: :bad_request unless
        application.redirect_uri_allowed?(redirect_uri)

      grant = OauthAccessGrant.create!(
        application:,
        resource_owner: current_user,
        redirect_uri:,
        scopes: 'read'
      )

      redirect_to build_callback_url(redirect_uri, grant.token, state),
                  allow_other_host: true
    end

    private

    def build_callback_url(redirect_uri, code, state)
      uri   = URI.parse(redirect_uri)
      query = URI.decode_www_form(uri.query.to_s)
      query << ['code', code]
      query << ['state', state] if state.present?
      uri.query = URI.encode_www_form(query)
      uri.to_s
    end
  end
end
