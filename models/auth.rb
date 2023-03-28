require "date"
require "sinatra/reloader"
require_relative "../app.rb"

# Creates a new user and inserts it into the database
#
# @param [String] name The name of the user
# @param [String] email The email of the user
# @param [String] password_digest The hashed password of the user
#
# @return [Integer] The ID of the new user
#
# @raise [Exception] if there is a conflict with the name or email already existing in the database
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

# Get User
#
# Retrieves a user from the database based on their email or name.
#
# @param [String] identifier email or name of the user
# @return [Hash]
#   * :user_id [Integer] the ID of the user
#   * :name [String] the name of the user
#   * :email [String] the email of the user
#   * :password [String] the encrypted password of the user
# @return [nil] if the user is not found
def get_user(identifier)
  db = connect_to_db()

  result = db.execute("SELECT * FROM User WHERE email = ? or name = ?", [identifier, identifier]).first

  db.close

  return result
end
