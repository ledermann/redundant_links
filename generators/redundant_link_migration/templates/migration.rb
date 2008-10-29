class <%= class_name %> < ActiveRecord::Migration
  def self.up
    create_table :redundant_links, :force => true do |t|
      t.string :from_type, :limit => 20, :null => false
      t.integer :from_id, :null => false
      t.string :to_type, :limit => 20, :null => false
      t.integer :to_id, :null => false
    end
    
    add_index :redundant_links, [ :from_type, :from_id, :to_type, :to_id ], :name => 'index_redundant_links_1'
    add_index :redundant_links, [ :to_type, :to_id, :from_type, :from_id ], :name => 'index_redundant_links_2'
  end

  def self.down
    drop_table :redundant_links
  end
end