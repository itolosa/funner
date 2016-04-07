class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  def read_config(filename)
    YAML.load(ERB.new(IO.read(filename)).result) || {}
  end

  def fb_atoken
    @@oauth_access_token ||= read_config('config/facebook.yml')['access_token']
  end

  def twitter
    @@twitter_config ||= read_config('config/twitter.yml')
    @@twitter_client ||= Twitter::REST::Client.new(@@twitter_config)
  end

  def facebook
    @@facebook_graph_cache ||= Koala::Facebook::API.new(fb_atoken)
  end

  def facebook_event
    @@facebook_event_cache ||= FbEventLocation.new(fb_atoken)
  end
end