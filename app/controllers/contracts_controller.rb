# frozen_string_literal: true

class ContractsController < ApplicationController
  load_and_authorize_resource :submission, parent: false

  def index
    base = @submissions.left_joins(:template)
                       .where(archived_at: nil)
                       .where(templates: { archived_at: nil })

    @total_count = base.count

    pending_ids = Submitter.where(completed_at: nil).select(:submission_id)
    @completed_count = base.joins(:submitters).where.not(id: pending_ids).distinct.count
    @pending_count   = base.where(id: pending_ids).distinct.count

    @submissions = base.preload(:created_by_user, template: :author)
    @submissions = Submissions.search(current_user, @submissions, params[:q], search_template: true)
    @submissions = Submissions::Filter.call(@submissions, current_user, params)
    @submissions = @submissions.order(id: :desc)

    @pagy, @submissions = pagy_auto(@submissions.preload(submitters: :start_form_submission_events))
  end
end
