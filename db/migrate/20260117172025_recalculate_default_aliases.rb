class RecalculateDefaultAliases < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Fix persons without users - recalculate based on sender_count
    # Priority: 1) non-Noname with messages, 2) non-Noname, 3) Noname with messages, 4) any
    execute <<~SQL
      UPDATE people
      SET default_alias_id = (
        SELECT a.id FROM aliases a
        WHERE a.person_id = people.id
        ORDER BY
          (CASE WHEN a.name != 'Noname' AND a.sender_count > 0 THEN 0
                WHEN a.name != 'Noname' THEN 1
                WHEN a.sender_count > 0 THEN 2
                ELSE 3 END),
          a.sender_count DESC,
          a.created_at ASC
        LIMIT 1
      )
      WHERE NOT EXISTS (SELECT 1 FROM users WHERE users.person_id = people.id)
        AND EXISTS (SELECT 1 FROM aliases WHERE aliases.person_id = people.id)
    SQL

    # Fix persons WITH users who have Noname as default - find better option
    execute <<~SQL
      UPDATE people
      SET default_alias_id = (
        SELECT a.id FROM aliases a
        WHERE a.person_id = people.id
          AND a.name != 'Noname'
        ORDER BY a.sender_count DESC, a.created_at ASC
        LIMIT 1
      )
      WHERE EXISTS (SELECT 1 FROM users WHERE users.person_id = people.id)
        AND EXISTS (
          SELECT 1 FROM aliases a
          WHERE a.id = people.default_alias_id
            AND a.name = 'Noname'
        )
        AND EXISTS (
          SELECT 1 FROM aliases a
          WHERE a.person_id = people.id
            AND a.name != 'Noname'
        )
    SQL
  end

  def down
    # Cannot reverse - would need to restore original values
  end
end
