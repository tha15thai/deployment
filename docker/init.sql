CREATE TABLE IF NOT EXISTS items (
  id   SERIAL PRIMARY KEY,
  name TEXT NOT NULL
);
INSERT INTO items (name) VALUES ('Apple'), ('Banana'), ('Cherry')
ON CONFLICT DO NOTHING;
