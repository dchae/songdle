require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'httparty'
require 'pkce_challenge'
require 'json'

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, escape_html: true
end

before do
  session[:messages] ||= []
  p session[:challenge] ||= PkceChallenge.challenge(char_length: 64)
  #
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
    challenge = session[:challenge]
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
              code_challenge: challenge.code_challenge,
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
  response.to_s
  # erb :spotify_profile_data
end

get '/callback' do
  error = params['error']
  if error
    add_message 'User did not accept access' if error == 'access_denied'
    redirect '/'
  end

  clientId = 'a6c331f9a46f4198904b69b4dea82f74' # My Spotify Dev App Client ID
  redirectUri = 'http://localhost:4567/callback'
  challenge = session[:challenge]
  code = params['code']
  encoded_body =
    URI.encode_www_form(
      {
        client_id: clientId,
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirectUri,
        code_verifier: challenge.code_verifier,
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
