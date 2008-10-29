require 'test/unit'

require 'rubygems'
gem 'activerecord', '>= 1.15.4.7794'
require 'active_record'

require "#{File.dirname(__FILE__)}/../init"

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :dbfile => ":memory:")

def setup_db
  ActiveRecord::Schema.define(:version => 1) do
    create_table :contacts do |t|
      t.column :name, :string
    end
    
    create_table :orders do |t|
      t.column :number, :string
      t.column :contact_id, :integer
    end
    
    create_table :notes do |t|
      t.column :object_id, :integer
      t.column :object_type, :string, :limit => 20
      t.column :content, :text
    end
    
    create_table :redundant_links, :force => true do |t|
      t.string :from_type, :limit => 20, :null => false
      t.integer :from_id, :null => false
      t.string :to_type, :limit => 20, :null => false
      t.integer :to_id, :null => false
    end
  end
end

def teardown_db
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table)
  end
end

class Contact < ActiveRecord::Base
  has_many :orders
  has_many :notes, :as => :object
end
class Order < ActiveRecord::Base
  belongs_to :contact
  has_many :notes, :as => :object
end
class Note < ActiveRecord::Base
  belongs_to :object, :polymorphic => true
  
  has_redundant_links Note => :object, Order => :contact, Contact => nil
end

class RedundantLinksTest < Test::Unit::TestCase
  def setup
    setup_db
    @contact = Contact.create!
    @order = @contact.orders.create!
    @note = @order.notes.create!
  end

  def teardown
    teardown_db
  end

  def test_links
    assert_equal 2, RedundantLink.count
    assert_equal 1, @contact.redundant_links.count
    assert_equal 1, @order.redundant_links.count
  end
  
  def test_linked_notes
    assert_equal @note, @order.redundant_linked_notes.first
    assert_equal @note, @contact.redundant_linked_notes.first
  end
  
  def test_change_note
    other_order = @contact.orders.create!
    @note.update_attributes! :object => other_order
    assert_equal 0, @order.redundant_links.count
    assert_equal 1, other_order.redundant_links.count
  end
  
  def test_change_order_to_other_contact
    last_max = RedundantLink.maximum(:id)
    other_contact = Contact.create!
    @order.update_attributes! :contact => other_contact
    assert_equal 0, @contact.redundant_links.count
    assert_equal 1, other_contact.redundant_links.count
    assert_not_equal last_max, RedundantLink.maximum(:id)
  end

  def test_change_order_to_nil_contact
    last_count = RedundantLink.count
    last_max = RedundantLink.maximum(:id)
    @order.update_attributes! :contact => nil
    assert_equal 0, @contact.redundant_links.count
    assert_not_equal last_max, RedundantLink.maximum(:id)
    assert_equal last_count-1, RedundantLink.count
  end
  
  def test_change_order_other_attribute
    last_max = RedundantLink.maximum(:id)
    @order.update_attributes! :number => 'new number'
    assert_equal 1, @contact.redundant_links.count
    assert_equal last_max, RedundantLink.maximum(:id)
  end
  
  def test_change_empty_order_to_contact
    order = Order.create!
    note = order.notes.create!

    assert_equal false, @contact.redundant_linked_notes.include?(note)
    last_count = RedundantLink.count
    order.update_attributes :contact => @contact
    assert_equal true, @contact.redundant_linked_notes.include?(note)
    assert_equal last_count+1, RedundantLink.count
  end
  
  def test_delete
    @note.destroy
    assert_equal 0, @contact.redundant_links.count
    assert_equal 0, @contact.redundant_linked_notes.count
    assert_equal 0, @order.redundant_links.count
    assert_equal 0, @order.redundant_linked_notes.count
  end
  
  def test_rebuild
    RedundantLink.destroy_all
    assert_equal 0, RedundantLink.count
    Note.rebuild_redundant_links
    assert_equal 2, RedundantLink.count
  end
end