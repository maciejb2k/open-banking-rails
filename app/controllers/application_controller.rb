class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_first_run_setup

  private

  def require_first_run_setup
    return if User.exists?
    return if request.path == setup_path
    return if request.path == rails_health_check_path

    redirect_to setup_path
  end
end
