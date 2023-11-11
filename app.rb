require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'httparty'
require 'pkce_challenge'
require 'json'
require 'yaml'

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, escape_html: true
end

before do
  session[:messages] ||= []
  @challenge = load_challenge
end

def add_message(msg)
  session[:messages] << msg
end

def file_path(filename = nil, subfolder = 'temp')
  if ENV['RACK_ENV'] == 'test'
    subfolder = 'test/' + subfolder
  else
    subfolder = '/' + subfolder
  end
  filename = File.basename(filename) if filename
  File.join(*[File.expand_path('..', __FILE__), subfolder, filename].compact)
end

def session_file_path(filename = nil)
  path = file_path(nil, 'temp/' + session[:session_id])
  FileUtils.mkdir_p(path) unless File.directory?(path)
  File.join([path, filename].compact)
end

def load_yaml(filepath)
  YAML.load_file(filepath) if File.file?(filepath)
  # File.open(filepath, "r") { |f| YAML.load(f)}
end

def write_yaml(filepath, obj)
  File.open(filepath, 'w') { |f| YAML.dump(obj, f) }
end

def load_challenge
  path = session_file_path('challenge.yaml')
  loaded_challenge_hash = load_yaml(path)
  return loaded_challenge_hash if loaded_challenge_hash

  challenge = PkceChallenge.challenge(char_length: 64)
  challenge_hash = {
    code_challenge: challenge.code_challenge,
    code_verifier: challenge.code_verifier,
  }
  write_yaml(path, challenge_hash)
  challenge_hash
end

def load_user_data(response)
  load_yaml(session_file_path('user_data.yml'))
end

get '/' do
  redirect '/play'
end

get '/play' do
  # IF NOT AUTHENTICATED, DO:
  # need to implement:
  # if access token is expired, get new token with session[:refresh_token]
  unless session[:access_token]
    # Spotify API authentication
    clientId = 'a6c331f9a46f4198904b69b4dea82f74' # My Spotify Dev App Client ID
    redirectUri = 'http://localhost:4567/callback'
    scope = 'user-read-private user-read-email'
    auth_url = 'https://accounts.spotify.com/authorize'
    newuri =
      URI::HTTP.build(
        host: 'accounts.spotify.com',
        path: '/authorize',
        query:
          URI.encode_www_form(
            {
              response_type: 'code',
              client_id: clientId,
              scope: scope,
              code_challenge_method: 'S256',
              code_challenge: @challenge[:code_challenge],
              redirect_uri: redirectUri,
            },
          ),
      )
    redirect newuri
  end
  response =
    HTTParty.get(
      'https://api.spotify.com/v1/me',
      { headers: { Authorization: 'Bearer ' + session[:access_token] } },
    )
  @display_name = response['display_name']
  @profile_url = response['external_urls']['spotify']
  @id = response["id"]
  @profile_image = response["images"][1]["url"]
  @follower_count = response["followers"]["total"]
  @country = response["country"]
  @email = response["email"]
  erb :spotify_profile_data
end

get '/callback' do
  error = params['error']
  if error
    add_message 'User did not accept access' if error == 'access_denied'
    redirect '/'
  end

  clientId = 'a6c331f9a46f4198904b69b4dea82f74' # My Spotify Dev App Client ID
  redirectUri = 'http://localhost:4567/callback'
  code = params['code']
  encoded_body =
    URI.encode_www_form(
      {
        client_id: clientId,
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirectUri,
        code_verifier: @challenge[:code_verifier],
      },
    )

  response =
    HTTParty.post(
      'https://accounts.spotify.com/api/token',
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: encoded_body,
      },
    )
  body = JSON.parse(response.body)
  session[:access_token] = body['access_token']
  session[:refresh_token] = body['refresh_token']
  redirect '/play'
end
