# frozen_string_literal: true

class IntegrationAuthController < ApplicationController
  skip_before_action :redirect_to_login_if_required
  skip_before_action :check_xhr
  skip_before_action :preload_json
  skip_before_action :verify_authenticity_token

  before_action :ensure_discourse_api_key!
  # 根据用户名进行登录，用户不存在则自动创建
  # POST /integration-auth/login
  # 参数: { username: "xxx" }
  # 返回: { success: true, user_id: 123, username: "xxx" }
  def login
    params.require(:username)

    username = params[:username].to_s.strip
    return render_invalid("username 不能为空") if username.blank?

    if User.reserved_username?(username)
      return render_invalid("username 是保留名称")
    end

    user = User.find_by_username(username)

    if user.nil?
      return render_invalid("不允许新注册") unless SiteSetting.allow_new_registrations

      email = "#{username}@integration.local"
      user = create_integration_user(username, email)
      return render_invalid(user.errors.full_messages.join(", ")) unless user.persisted?

      user.email_tokens.update_all(confirmed: true)
      user.set_automatic_groups
    end

    return render_invalid("用户已被停用") if user.suspended?

    user.update!(active: true) unless user.active?

    log_on_user(user, replay_anonymous_action: true)

    render json: {
      success: true,
      user_id: user.id,
      username: user.username,
      email: user.primary_email&.email,
    }
  end

  private

  def create_integration_user(username, email)
    user =
      User.new(
        username: username,
        name: username,
        primary_email: UserEmail.new(email: email, primary: true),
        active: true,
        approved: true,
        staged: false,
      )
    user.skip_email_validation = true
    user.save
    user
  end

  def render_invalid(error)
    render json: { success: false, error: error }, status: :unprocessable_entity
  end

  def ensure_discourse_api_key!
    api_key = request.headers["Api-Key"].presence
    api_username = request.headers["Api-Username"].presence

    if api_key.blank? || api_username.blank?
      render json: {
        success: false,
        error: "missing api key"
      }, status: 401
      return
    end

    # Discourse 原生 API Key 认证成功后，current_user 应该是 Api-Username 对应的用户
    if current_user.blank?
      render json: {
        success: false,
        error: "invalid api key"
      }, status: 401
      return
    end

    unless current_user.admin?
      render json: {
        success: false,
        error: "admin api key required"
      }, status: 403
      return
    end
  end
end
