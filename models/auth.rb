require "date"
require "sinatra/reloader"
require_relative "../app.rb"

def new_user(name, email, password_digest)
  db = connect_to_db()

  # Hash password
  created_at = Time.now.to_i

  # Insert user into database
  begin
    # Insert user into databse and return user_id
    db.execute("INSERT INTO User (name, email, password_digest, created_at) VALUES (?, ?, ?, ?)", [name, email, password_digest, created_at])
    new_user_id = db.last_insert_row_id
    db.close
    return new_user_id
  rescue SQLite3::ConstraintException => e
    conflict = []

    if db.execute("SELECT COUNT(*) FROM User WHERE name = ?", [name]).first[0] > 0
      conflict << "conflict:name"
    end
    if db.execute("SELECT COUNT(*) FROM User WHERE email = ?", [email]).first[0] > 0
      conflict << "conflict:email"
    end

    db.close
    raise Exception.new(conflict.join(", "))
  end
end

def get_user(identifier)
  db = connect_to_db()

  result = db.execute("SELECT * FROM User WHERE email = ? or name = ?", [identifier, identifier]).first

  db.close

  return result
end
