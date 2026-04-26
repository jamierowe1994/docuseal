# frozen_string_literal: true

class ApiDocsController < ApplicationController
  def show
    authorize!(:read, current_user.access_token)
  end
end
