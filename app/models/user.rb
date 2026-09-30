class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  ROLES = %w[admin member].freeze
  MAX_BETA_USERS = 5

  has_many :rewritten_articles, class_name: "Article", foreign_key: :rewritten_by_id, inverse_of: :rewritten_by
  has_many :activity_logs, dependent: :destroy

  validates :role, inclusion: { in: ROLES }
  validate :beta_user_limit, on: :create

  def admin?
    return self[:role] == "admin" if has_attribute?(:role)

    email.to_s.casecmp?(ENV["ADMIN_EMAIL"].to_s)
  end

  def online?
    last_seen_at.present? && last_seen_at >= 5.minutes.ago
  end

  private

  def beta_user_limit
    errors.add(:base, "O beta permite no máximo #{MAX_BETA_USERS} usuários") if User.count >= MAX_BETA_USERS
  end
end
