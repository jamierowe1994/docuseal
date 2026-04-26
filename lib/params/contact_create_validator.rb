# frozen_string_literal: true

module Params
  class ContactCreateValidator < BaseValidator
    def call
      required(params, %i[email phone name])
      type(params, :name, String)
      type(params, :email, String)
      email_format(params, :email, message: 'email is invalid')
      type(params, :phone, String)
      format(params, :phone, /\A\+\d+\z/,
             message: 'phone should start with +<country code> and contain only digits')
      type(params, :external_id, String)
      type(params, :template_id, Integer)
      type(params, :metadata, Hash)
      boolean(params, :send_email)

      true
    end
  end
end
