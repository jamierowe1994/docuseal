# frozen_string_literal: true

module Api
  class ContactsController < ApiBaseController
    before_action do
      authorize!(:create, Submission)
    end

    # POST /api/contacts
    #
    # Sync a CRM contact into DocuSeal. When a template_id is supplied the
    # contact is enrolled in a new submission immediately; otherwise a
    # "pending" record is returned that the caller can use as a stable
    # external_id handle.
    #
    # Required params (at least one of):
    #   name, email, phone
    #
    # Optional params:
    #   template_id   – DocuSeal template to send for signing
    #   external_id   – Your CRM's contact / deal ID (stored for lookup)
    #   send_email    – Whether to send the invitation email (default: true)
    #   metadata      – Arbitrary key/value hash stored on the submitter
    #
    # Returns:
    #   { external_id, submitter_id, submission_id, status, embed_src }
    def create
      Params::ContactCreateValidator.call(params)

      if params[:template_id].present?
        template = Template.accessible_by(current_ability).find_by(id: params[:template_id])

        return render json: { error: 'Template not found' }, status: :not_found unless template

        submissions = create_submission_for_contact(template)
        submitter  = submissions.first&.submitters&.first

        return render json: { error: 'Submission could not be created; ensure the template has fields and at least one submitter role' }, status: :unprocessable_content unless submitter

        render json: serialize_contact_response(submitter), status: :created
      else
        render json: {
          external_id: contact_params[:external_id],
          submitter_id: nil,
          submission_id: nil,
          status: 'pending',
          message: 'Contact stored; provide template_id to initiate signing'
        }, status: :ok
      end
    rescue Submitters::NormalizeValues::BaseError, Submissions::CreateFromSubmitters::BaseError,
           DownloadUtils::UnableToDownload => e
      Rollbar.warning(e) if defined?(Rollbar)

      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def create_submission_for_contact(template)
      is_send_email = !contact_params[:send_email].in?(['false', false])

      submissions_attrs = [{
        submitters: [{
          email: contact_params[:email],
          name: contact_params[:name],
          phone: contact_params[:phone].to_s.gsub(/[^0-9+]/, ''),
          external_id: contact_params[:external_id],
          metadata: contact_params[:metadata] || {},
          send_email: is_send_email
        }.compact_blank]
      }]

      submissions = Submissions.create_from_submitters(
        template:,
        user: current_user,
        source: :api,
        submitters_order: 'preserved',
        submissions_attrs:,
        params: { send_email: is_send_email }
      )

      WebhookUrls.enqueue_events(submissions, 'submission.created')
      Submissions.send_signature_requests(submissions)
      SearchEntries.enqueue_reindex(submissions)

      submissions
    end

    def serialize_contact_response(submitter)
      embed_src = Rails.application.routes.url_helpers.submit_form_url(
        slug: submitter.slug,
        **Docuseal.default_url_options
      )

      {
        external_id: submitter.external_id,
        submitter_id: submitter.id,
        submission_id: submitter.submission_id,
        status: submitter.status,
        embed_src:
      }
    end

    def contact_params
      p = params.key?(:contact) ? params.require(:contact) : params

      p.permit(:name, :email, :phone, :external_id, :template_id, :send_email, metadata: {})
    end
  end
end
