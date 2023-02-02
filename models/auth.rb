require "date"
require_relative "../app.rb"

def new_user(name, email, password)
  db = connect_to_db()
  db.results_as_hash = true

  created_at = Time.now.to_i

  db.execute("INSERT INTO User (name, email, password_hash, created_at) VALUES (?, ?, ?, ?)", [name, email, password, created_at])

  db.close
end

def get_user(identifier)
  db = connect_to_db()
  db.results_as_hash = true

  result = db.execute("SELECT * FROM User WHERE email = ? or name = ?", [identifier, identifier]).first

  db.close

  return result
end
