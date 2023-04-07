#!/usr/bin/env ruby
# encoding: utf-8

require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "bcrypt"
require_relative "../utils/rate_limiter.rb"
require_relative "../utils/form.rb"
require_relative "../models/auth.rb"

# Displays the login page
#
get("/login") do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  slim(:"routes/auth/login")
end

# Authenticates a user and redirects to the '/app' page upon successful login
#
# @param [String] email, The email address of the user
# @param [String] password, The password for the user
#
# @see get_user
post("/login") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form

  form.validate(:email) do |email|
    raise "Du måste fylla i fältet" if email.empty?
    raise "E-postadressen måste vara giltig" if !email.include? "@"
  end

  form.validate(:password) do |password|
    raise "Du måste fylla i fältet" if password.empty?
  end

  send_response(form, rate_limiter, "/login") if !form.success?

  # Get user from database

  result = get_user(form.values[:email])

  form.validate(:password) do |password|
    if result == nil
      form.error(:general) { raise "Fel användarnamn eller lösenord" }
    else
      password_digest = result["password_digest"]

      raise "Fel användarnamn eller lösenord" if !BCrypt::Password.new(password_digest) == password
    end
  end

  send_response(form, rate_limiter, "/login") if !form.success?

  # Login user

  session[:user_id] = result["user_id"]
  session.delete(:errors)
  session.delete(:values)
  redirect("/app")
end

# Displays the signup page
#
get("/signup") do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  slim(:"routes/auth/signup")
end

# Registers a new user and redirects to the '/app' page upon successful registration
#
# @param [String] name, The name of the new user
# @param [String] email, The email address of the new user
# @param [String] password, The password for the new user
#
# @see new_user
post("/signup") do
  rate_limiter = RateLimiter.new(REDIS, request, 8, 10)
  form = FormValidator.new(params)

  # Validate form

  form.validate(:name) do |name|
    raise "Du måste fylla i fältet" if name.empty?
    raise "Namnet får inte innehålla @-tecken" if name.include? "@"
  end

  form.validate(:email) do |email|
    raise "Du måste fylla i fältet" if email.empty?
    raise "E-postadressen är inte giltig" if !email.include? "@"
  end

  form.validate(:password) do |password|
    raise "Du måste fylla i fältet" if password.empty?
    raise ClearField, "Lösenordet måste vara minst 8 tecken" if password.length < 8
  end

  # Check if form is valid

  send_response(form, rate_limiter, "/signup") if !form.success?

  # Add user to database

  password_digest = BCrypt::Password.create(form.values[:password])

  begin
    new_user = new_user(form.values[:name], form.values[:email], password_digest)
    session[:user_id] = new_user

    session.delete(:errors)
    session.delete(:values)
    redirect("/app")
  rescue Exception => e
    form.error(:name) { raise ClearField, "Användarnamnet används redan" if e.message.include? "conflict:name" }
    form.error(:email) { raise ClearField, "E-postadressen används redan" if e.message.include? "conflict:email" }
    form.error(:general) { raise "Något gick fel, försök igen" } if form.success?

    send_response(form, rate_limiter, "/signup") if !form.success?
  end
end

# Logs out a user and redirects to the home page
#
# @see delete_user_session
post("/logout") do
  session.delete(:user_id)
  redirect("/")
end
