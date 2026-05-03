# frozen_string_literal: true

class SetupController < ApplicationController
  layout "admin_auth"

  def new
    redirect_to(after_setup_path) and return if User.exists?

    @user = User.new
  end

  def create
    redirect_to(after_setup_path) and return if User.exists?

    @user = User.new(user_params)

    if @user.save
      Seeders::Categories.call(@user)
      Seeders::MerchantRules.call(@user)
      sign_in @user
      redirect_to admin_root_path, notice: "Welcome - your account is ready."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def after_setup_path
    user_signed_in? ? admin_root_path : new_user_session_path
  end
end
