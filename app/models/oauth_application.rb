# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_applications
#
#  id           :bigint           not null, primary key
#  confidential :boolean          default(TRUE), not null
#  name         :string           not null
#  redirect_uri :text
#  scopes       :string           default(""), not null
#  secret       :string           not null
#  uid          :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_oauth_applications_on_uid  (uid) UNIQUE
#
class OauthApplication < ApplicationRecord
  has_many :access_grants, class_name: 'OauthAccessGrant', foreign_key: :application_id,
                           inverse_of: :application, dependent: :destroy

  validates :name, :uid, :secret, presence: true
  validates :uid, uniqueness: true

  before_validation :generate_credentials, on: :create

  # Returns the registered OauthApplication for backed.crm, creating it on
  # first use from environment variables when present.
  def self.crm_application
    uid = ENV.fetch('CRM_CLIENT_ID') { 'backed-crm' }

    find_or_initialize_by(uid:).tap do |app|
      if app.new_record?
        app.name   = 'backed.crm'
        app.secret = ENV.fetch('CRM_CLIENT_SECRET') { SecureRandom.hex(32) }
        app.redirect_uri = ENV.fetch('CRM_REDIRECT_URI', nil)
        app.save!
      end
    end
  end

  # Returns true when the redirect_uri supplied by the client is acceptable.
  # If the application has no registered redirect URIs, any https URI is
  # accepted in production; all URIs are accepted otherwise.
  def redirect_uri_allowed?(requested_uri)
    return false if requested_uri.blank?

    allowed = redirect_uri.to_s.split.compact_blank
    return allowed.any? { |uri| requested_uri.start_with?(uri) } if allowed.any?

    uri = URI.parse(requested_uri)
    Rails.env.production? ? uri.scheme == 'https' : true
  rescue URI::InvalidURIError
    false
  end

  private

  def generate_credentials
    self.uid    ||= SecureRandom.hex(16)
    self.secret ||= SecureRandom.hex(32)
  end
end
