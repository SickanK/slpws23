def new_database(user_id, name)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Database (name, created_at) VALUES (?, ?)", [name, created_at])
  new_database_id = db.last_insert_row_id
  db.execute("INSERT INTO UserDatabaseRel (user_id, database_id) VALUES (?, ?)", [user_id, new_database_id])
  db.close

  return new_database_id
end

def get_databases(user_id)
  db = connect_to_db()

  databases = db.execute(%{
    SELECT * FROM Database
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [[], user_id])

  # Get posts
  posts = db.execute(%{ 
    SELECT * FROM Post
    INNER JOIN UserDatabaseRel ON Post.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])
  db.close

  # Add posts to their respective database (should be done in a single sql query in the future)
  posts.each do |post|
    database = databases.find { |database| database["database_id"] == post["database_id"] }
    database["posts"] = [] if database["posts"].nil?
    database["posts"].push(post)
  end

  return databases
end
