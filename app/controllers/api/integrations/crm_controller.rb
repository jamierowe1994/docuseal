# frozen_string_literal: true

module Api
  module Integrations
    # JSON API endpoints powering the backed.crm ↔ backed.sign integration.
    #
    # token     POST /api/integrations/crm/token
    #   – Exchanges an OAuth authorization code for a JWT access token.
    #     Called server-to-server by backed.crm.
    #
    # templates GET /api/integrations/crm/templates
    #   – Returns paginated active templates for the authenticated user.
    #
    # template  GET /api/integrations/crm/templates/:id
    #   – Returns a single template's full body for field pre-filling.
    #
    # Authentication for templates endpoints:
    #   Authorization: Bearer <jwt>
    class CrmController < ActionController::API
      include ActiveStorage::SetCurrent

      JWT_EXPIRY = 3600 # 1 hour

      before_action :set_cors_headers
      before_action :authenticate_with_jwt!, only: %i[templates template]

      # POST /api/integrations/crm/token
      def token
        application = OauthApplication.find_by(uid: params[:client_id])

        return render json: { error: 'Invalid client credentials' }, status: :unauthorized unless application
        return render json: { error: 'Invalid client credentials' }, status: :unauthorized unless
          ActiveSupport::SecurityUtils.secure_compare(application.secret, params[:client_secret].to_s)

        grant = application.access_grants.active.find_by(token: params[:code])

        return render json: { error: 'Invalid or expired authorization code' }, status: :unauthorized unless grant

        grant.revoke!

        user = grant.resource_owner
        jwt  = JsonWebToken.encode({
                                     user_id: user.id,
                                     account_id: user.account_id,
                                     exp: JWT_EXPIRY.seconds.from_now.to_i
                                   })

        render json: {
          access_token: jwt,
          token_type: 'Bearer',
          expires_in: JWT_EXPIRY,
          scope: 'read'
        }
      end

      # GET /api/integrations/crm/templates
      def templates
        templates = Template.accessible_by(current_ability).active
                            .preload(:author, folder: :parent_folder)
                            .order(id: :desc)
                            .limit(50)

        render json: {
          data: templates.map { |t| Templates::SerializeForApi.call(t) },
          pagination: {
            count: templates.size,
            next: templates.last&.id,
            prev: templates.first&.id
          }
        }
      end

      # GET /api/integrations/crm/templates/:id
      def template
        tmpl = Template.accessible_by(current_ability).find_by(id: params[:id])

        return render json: { error: 'Template not found' }, status: :not_found unless tmpl

        render json: Templates::SerializeForApi.call(tmpl)
      end

      # OPTIONS /api/integrations/crm/* – CORS pre-flight
      def preflight
        head :no_content
      end

      private

      def authenticate_with_jwt!
        render json: { error: 'Not authenticated' }, status: :unauthorized unless current_user
      end

      def current_user
        @current_user ||= user_from_jwt
      end

      def current_ability
        @current_ability ||= Ability.new(current_user)
      end

      def user_from_jwt
        auth = request.headers['Authorization'].to_s
        # Extract token after literal "Bearer " prefix to avoid ReDoS with greedy \s+
        token = auth.start_with?('Bearer ') ? auth[7..] : nil
        return if token.blank?

        # JWT.decode raises JWT::DecodeError (including JWT::ExpiredSignature) for
        # invalid or expired tokens, so no separate expiry check is needed.
        payload = JsonWebToken.decode(token)
        User.active.find_by(id: payload['user_id'])
      rescue JWT::DecodeError
        nil
      end

      def set_cors_headers
        origin = ENV.fetch('CRM_ORIGIN', '*')
        headers['Access-Control-Allow-Origin']  = origin
        headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
        headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
        headers['Access-Control-Max-Age']       = '86400'
      end
    end
  end
end
