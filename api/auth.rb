#!/usr/bin/env ruby
# encoding: utf-8

require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "bcrypt"
require_relative "../models/auth.rb"

# Login

get("/login") do
  slim(:login)
end

post("/login") do
  email = params[:email].strip!
  password = params[:password].strip!

  # Check if fields are not empty

  if (email == "" || email == nil || password == "" || password == nil)
    session[:error] = { "login" => "Du måste fylla i alla fält", fields: params }
    redirect("/")
  end

  # Get user from database

  result = get_user(email)

  # Check if password is correct
  if result && BCrypt::Password.new(result["password"]) == password
    session[:user_id] = result["user_id"]
    session[:error] = nil

    redirect("/")
  else
    session[:error] = { "login" => "Fel användarnamn eller lösenord" }
    redirect("/login")
  end
end

# Signup

get("/signup") do
  slim(:signup)
end

post("/signup") do
  name = params[:name].strip
  email = params[:email].strip
  password = params[:password].strip

  # Check if user already exists

  if (name == "" || name == nil || email == "" || email == nil || password == "" || password == nil)
    session[:error] = { "signup" => "Du måste fylla i alla fält", "fields" => {
      "name" => name,
      "email" => email,
      "password" => password,
    } }
    redirect("/signup")
  elsif (password.length < 8)
    session[:error] = { "signup" => "Lösenordet måste vara minst 8 tecken", "fields" => {
      "name" => name,
      "email" => email,
      "password" => "",

    } }

    redirect("/signup")
  elsif (name.include? "@")
    session[:error] = { "signup" => "Namnet får inte innehålla @-tecken", "fields" => {
      "name" => name,
      "email" => email,
      "password" => password,
    } }
    redirect("/signup")
  else
    session[:error] = nil
  end

  # Add user to database
  password_digest = BCrypt::Password.create(password)

  new_user(name, email, password_digest)
end
