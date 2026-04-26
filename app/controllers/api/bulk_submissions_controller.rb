# frozen_string_literal: true

module Api
  class BulkSubmissionsController < ApiBaseController
    load_and_authorize_resource :template

    before_action do
      authorize!(:create, Submission)
    end

    # POST /api/templates/:template_id/submissions/bulk
    #
    # Send one submission per contact in a single API call.
    #
    # Body params:
    #   submitters  – Array of submitter objects. Each entry may contain:
    #                   email, name, phone, external_id, metadata,
    #                   send_email, values (field pre-fills)
    #   send_email  – Top-level default for all submitters (default: true)
    #
    # Returns an array of submitter objects (same shape as
    #   POST /api/templates/:id/submissions).
    def create
      return render json: { error: 'Template not found' }, status: :not_found if @template.nil?

      if @template.fields.blank?
        return render json: { error: 'Template does not contain fields' }, status: :unprocessable_content
      end

      submitters_list = bulk_submitters_params

      if submitters_list.blank?
        return render json: { error: 'submitters is required and must be a non-empty array' },
                      status: :unprocessable_content
      end

      submissions = create_bulk_submissions(submitters_list)

      WebhookUrls.enqueue_events(submissions, 'submission.created')
      Submissions.send_signature_requests(submissions)
      SearchEntries.enqueue_reindex(submissions)

      render json: build_response(submissions), status: :created
    rescue Submitters::NormalizeValues::BaseError, Submissions::CreateFromSubmitters::BaseError,
           DownloadUtils::UnableToDownload => e
      Rollbar.warning(e) if defined?(Rollbar)

      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def create_bulk_submissions(submitters_list)
      is_send_email = !params[:send_email].in?(['false', false])

      submissions_attrs = submitters_list.map do |submitter_attrs|
        {
          submitters: [submitter_attrs.merge(
            send_email: submitter_attrs.key?(:send_email) ? submitter_attrs[:send_email] : is_send_email
          )]
        }
      end

      Submissions.create_from_submitters(
        template: @template,
        user: current_user,
        source: :api,
        submitters_order: 'preserved',
        submissions_attrs:,
        params: { send_email: is_send_email }
      )
    end

    def build_response(submissions)
      expires_at = Accounts.link_expires_at(current_account)

      submissions.map do |submission|
        submission.submitters.map do |submitter|
          Submitters::SerializeForApi.call(submitter, with_documents: false, with_urls: true,
                                                      params:, expires_at:)
        end
      end.flatten
    end

    def bulk_submitters_params
      submitter_permitted = [
        :send_email, :send_sms, :completed_redirect_url, :uuid, :name, :email, :role,
        :completed, :phone, :application_key, :external_id, :reply_to, :go_to_last,
        :require_phone_2fa, :require_email_2fa, :order, :index, :invite_by,
        { metadata: {}, values: {}, roles: [], readonly_fields: [],
          message: %i[subject body],
          fields: [:name, :uuid, :default_value, :value, :title, :description,
                   :readonly, :required, :validation_pattern, :invalid_message,
                   { default_value: [], value: [], preferences: {}, validation: {} }] }
      ]

      params.permit(submitters: [submitter_permitted])[:submitters]
    end
  end
end
