#!/usr/bin/env ruby
# encoding: utf-8

require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "bcrypt"
require_relative "../models/auth.rb"

# Login

get("/login") do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  slim(:login)
end

post("/login") do
  email = params[:email].strip!
  password = params[:password].strip!

  session[:errors] = {}
  session[:values] = { :email => email, :password => password }

  # Check if fields are not empty

  if (email == "" || email == nil || password == "" || password == nil)
    session[:errors][:login] = "Du måste fylla i alla fält"

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
    session[:error] = { :login => "Fel användarnamn eller lösenord" }
    redirect("/login")
  end
end

# Signup

get("/signup") do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  slim(:signup)
end

post("/signup") do
  name = params[:name].strip
  email = params[:email].strip
  password = params[:password].strip

  session[:errors] = {}
  session[:values] = { :name => name, :email => email, :password => password }

  # Check if user already exists

  if (name == "" || name == nil || email == "" || email == nil || password == "" || password == nil)
    session[:errors][:signup] = "Du måste fylla i alla fält"

    redirect("/signup")
  elsif (password.length < 8)
    session[:errors][:signup] = "Lösenordet måste vara minst 8 tecken"
    session[:values][:password] = ""

    redirect("/signup")
  elsif (name.include? "@")
    session[:errors][:signup] = "Namnet får inte innehålla @-tecken"
    session[:values][:password] = ""

    redirect("/signup")
  else
    session[:error] = nil
  end

  # Add user to database
  password_digest = BCrypt::Password.create(password)

  begin
    new_user = new_user(name, email, password_digest)

    session[:user_id] = new_user
    redirect("/")
  rescue Exception => e
    if e.message.include? "name"
      session[:errors][:name] = "Användarnamnet är redan upptagen"
      session[:values][:name] = ""
    end

    if e.message.include? "email"
      session[:errors][:email] = "E-postadressen är redan upptagen"
      session[:values][:email] = ""
    end

    redirect("/signup")
  end
end
