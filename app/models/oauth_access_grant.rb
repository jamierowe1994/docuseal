# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_access_grants
#
#  id                    :bigint           not null, primary key
#  application_id        :bigint           not null
#  code_challenge        :string
#  code_challenge_method :string
#  created_at            :datetime         not null
#  expires_in            :integer          not null
#  redirect_uri          :text             not null
#  resource_owner_id     :bigint           not null
#  revoked_at            :datetime
#  scopes                :string           default(""), not null
#  token                 :string           not null
#
# Indexes
#
#  index_oauth_access_grants_on_application_id    (application_id)
#  index_oauth_access_grants_on_resource_owner_id (resource_owner_id)
#  index_oauth_access_grants_on_token             (token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (application_id => oauth_applications.id)
#  fk_rails_...  (resource_owner_id => users.id)
#
class OauthAccessGrant < ApplicationRecord
  EXPIRY_SECONDS = 600 # 10 minutes

  belongs_to :application, class_name: 'OauthApplication'
  belongs_to :resource_owner, class_name: 'User'

  validates :token, :redirect_uri, :expires_in, presence: true
  validates :token, uniqueness: true

  before_validation :set_defaults, on: :create

  scope :active, -> { where(revoked_at: nil).where('created_at > ?', EXPIRY_SECONDS.seconds.ago) }

  def expired?
    created_at < EXPIRY_SECONDS.seconds.ago
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  private

  def set_defaults
    self.token      ||= SecureRandom.hex(32)
    self.expires_in ||= EXPIRY_SECONDS
  end
end
