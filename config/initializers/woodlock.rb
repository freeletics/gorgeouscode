Woodlock.setup do |config|
  config.site_name = "Gorgeous Code"
  config.site_email = "noreply@gorgeouscode.com"
  config.site_url = "https://www.gorgeouscode.com"
  config.gravatar_default_url = "https://www.gorgeouscode.com/no_user.png"
  config.authentication_services = ["github"]
  config.github_scope = "user:email, repo"
  config.github_callback_url = "https://www.gorgeouscode.com/auth/github/callback"
  # config.disable_welcome_email = true
end
