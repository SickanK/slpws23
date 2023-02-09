#!/usr/bin/env ruby
# encoding: utf-8

require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "bcrypt"
require_relative "../utils/rate_limiter.rb"
require_relative "../utils/form.rb"
require_relative "../models/auth.rb"

# Login

get("/login") do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  slim(:login)
end

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

  if !form.success?
    rate_limiter.call()
    form.error(:general, true) do
      raise "Du har gjort för många misslyckade försök. Vänta en liten stund innan du försöker igen." if rate_limiter.limit_exceeded?
    end

    session[:errors] = form.errors
    session[:values] = form.values
    redirect("/login")
  end

  # Get user from database

  result = get_user(email)
  password_digest = result["password_digest"]

  form.validate(:password) do |password|
    if result == nil
      form.error(:general) { raise "Fel användarnamn eller lösenord" }
      return
    end

    raise "Fel användarnamn eller lösenord" if !BCrypt::Password.new(password_digest) == password
  end

  if !form.success?
    rate_limiter.call()
    form.error(:general, true) do
      raise "Du har gjort för många misslyckade försök. Vänta en liten stund innan du försöker igen." if rate_limiter.limit_exceeded?
    end

    session[:errors] = form.errors
    session[:values] = form.values
    redirect("/login")
  end

  session[:user_id] = result["user_id"]
  session.delete(:errors)
  session.delete(:values)
  redirect("/")
end

# Signup

get("/signup") do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  slim(:signup)
end

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
    raise "E-postadressen måste vara giltig" if !email.include? "@"
  end

  form.validate(:password) do |password|
    raise "Du måste fylla i fältet" if password.empty?
    raise "Lösenordet måste vara minst 8 tecken" if password.length < 8
  end

  # Check if form is valid

  if !form.success?
    rate_limiter.call()
    form.error(:general, true) do
      raise "Du har gjort för många misslyckade försök. Vänta en liten stund innan du försöker igen." if rate_limiter.limit_exceeded?
    end

    session[:errors] = form.errors
    session[:values] = form.values
    redirect("/signup")
  end

  # Add user to database

  password_digest = BCrypt::Password.create(form.values[:password])

  begin
    new_user = new_user(form.values[:name], form.values[:email], password_digest)
    session[:user_id] = new_user

    session.delete(:errors)
    session.delete(:values)
    redirect("/")
  rescue Exception => e
    form.error(:name) { raise "Användarnamnet finns redan" if e.message.include? "conflict:name" }
    form.error(:email) { raise "E-postadressen finns redan" if e.message.include? "conflict:email" }
    form.error(:general) { raise "Något gick fel, försök igen" } if form.success?

    rate_limiter.call()
    form.error(:general, true) do
      raise "Du har gjort för många misslyckade försök. Vänta en liten stund innan du försöker igen." if rate_limiter.limit_exceeded?
    end

    session[:errors] = form.errors
    session[:values] = form.values
    redirect("/signup")
  end
end
