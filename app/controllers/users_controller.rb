class UsersController < ApplicationController
  before_action :require_admin!
  before_action :set_user, only: %i[edit update destroy]

  def index
    @users = User.includes(:activity_logs).order(:name, :email)
  end

  def new
    @user = User.new(role: "member")
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to users_path, notice: "Usuário criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attributes = user_params
    attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?
    if @user.update(attributes)
      redirect_to users_path, notice: "Usuário atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "Você não pode remover sua própria conta."
    else
      @user.destroy!
      redirect_to users_path, notice: "Usuário removido."
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :role, :password, :password_confirmation)
  end
end
