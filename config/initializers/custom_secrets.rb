unless Rails.env == "production"
  begin
    `source #{Rails.root}/env_secret.sh`
  rescue
  end
end
