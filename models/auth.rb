require "date"
require_relative "../app.rb"

def connect_to_db()
  db = SQLite3::Database.new(DB_PATH)
  db.results_as_hash = true
  return db
end

def new_user(name, email, password)
  db = connect_to_db()
  db.results_as_hash = true

  # Hash password
  created_at = Time.now.to_i

  # Insert user into database
  begin
    db.execute("INSERT INTO User (name, email, password_hash, created_at) VALUES (?, ?, ?, ?)", [name, email, password, created_at])
  rescue SQLite3::ConstraintException
    conflict = []

    if db.execute("SELECT COUNT(*) FROM User WHERE name = ?", [name]).first[0] > 0
      conflict << "name"
    end
    if db.execute("SELECT COUNT(*) FROM User WHERE email = ?", [email]).first[0] > 0
      conflict << "email"
    end

    db.close
    raise Exception.new(conflict.join(", "))
  end

  db.close
end

def get_user(identifier)
  db = connect_to_db()
  db.results_as_hash = true

  result = db.execute("SELECT * FROM User WHERE email = ? or name = ?", [identifier, identifier]).first

  db.close

  return result
end
